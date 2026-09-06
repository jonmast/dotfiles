.pragma library

// Pace arithmetic for the AI-quota tooltip's ring gauges.
//
// "Am I on pace?" needs to know how far through the window we are, which needs
// a window START — really a window LENGTH, since the reset time is known.
//
// The plugin now supplies both `windowSeconds` and a computed `projection` on
// most windows, and `ai-quota.py` plumbs them through. That is the preferred
// path and is tried first.
//
// It is not universal, though, so the fallback below is live code rather than
// scaffolding. Three windows arrive with no projection: `claude/extra` and
// `opencode-go/monthly` have no span for the plugin to forecast against, and
// Claude's model-scoped weeklies (`claude-weekly-scoped-*`) arrive with
// neither span nor forecast. The ID table covers that last case — the
// collector deliberately does not guess their span, so the guess lives here,
// where it can be tagged `inferred: true` and shown as such.

// Fixed-length windows, in milliseconds. Keyed on the IDs the collector emits.
var FIXED = {
    "five_hour": 5 * 3600 * 1000,
    "seven_day": 7 * 86400 * 1000,
    "weekly": 7 * 86400 * 1000,
    // OpenCode Go's usage-triggered 5h window. The plugin already hardcodes
    // this span (providers.go:45), so the real record will carry it.
    "rolling": 5 * 3600 * 1000
};

// Windows that reset on a calendar boundary rather than after a fixed span.
// Their length varies (28-31 days), so it is measured back from the reset date
// rather than assumed.
var CALENDAR_MONTH = {
    "monthly": true,
    "premium_interactions": true,
    "chat": true,
    "completions": true
};

// NOTE: "rolling" windows need no special case. A rolling window is started by
// the first use after the previous one lapsed, and then runs a fixed span from
// that point — so at any given moment it has a concrete start and end just like
// a calendar window, and `resetAt - duration` recovers the start. "Rolling"
// describes how the start gets CHOSEN, not whether one exists.
//
// (Two earlier drafts of this file got that wrong in different ways — first
// refusing to pace them at all, then treating them as always-fully-elapsed.
// Both produced a worse reading than just doing the normal arithmetic.)

// Returns [durationMs, inferred]. The provider's own figure always wins.
function durationOf(window) {
    if (window.windowSeconds)
        return [window.windowSeconds * 1000, false];
    return [durationFor(window.id, window.resetAtMs), true];
}

function durationFor(id, resetAtMs) {
    if (FIXED[id])
        return FIXED[id];

    // Claude's per-model scoped limits ride the weekly window.
    if (id.indexOf("claude-weekly-scoped-") === 0)
        return FIXED["seven_day"];

    if (CALENDAR_MONTH[id] && resetAtMs) {
        var reset = new Date(resetAtMs);
        var start = new Date(resetAtMs);
        start.setMonth(reset.getMonth() - 1);
        return resetAtMs - start.getTime();
    }

    return 0;
}

// Returns a pace reading, or `{ known: false, reason: ... }` when one cannot
// honestly be produced. Every caller must handle the unknown case: refusing to
// answer is a valid answer, and a made-up projection on a quota widget is worse
// than no projection.
// PREFERRED PATH: the plugin computed the projection and we just render it.
//
// The plugin can weight elapsed time by a usage PROFILE — "81% of a typical
// week's burn is already behind you" — which the client cannot do, because the
// client has no history. `expectedFraction` is that profile figure;
// `elapsedFraction` is the raw clock. The gap between them is informative on
// its own: usage sitting between the two means the clock says you are in
// trouble and your actual pattern says you are not.
//
// `basis: "uniform"` means the profile had nothing to go on (cold start) and
// the plugin fell back to clock-only, in which case the two fractions are
// equal and there is no second opinion to show.
function fromProjection(window, pct, projection) {
    var expected = projection.expectedFraction * 100;
    return {
        "known": true,
        "source": "plugin",
        "inferred": false,
        "usedPercent": pct,
        // Profile-weighted. This is the one the UI should lead with.
        "expectedPercent": expected,
        // Raw wall-clock, kept as the second opinion.
        "clockPercent": projection.elapsedFraction * 100,
        "deltaPercent": pct - expected,
        "projectedPercent": projection.projectedUsedPercent,
        "naiveProjectedPercent": projection.naiveProjectedPercent,
        "exhaustAtMs": projection.projectedExhaustionAtMs || null,
        "verdict": projection.verdict,
        "confidence": projection.confidence,
        "basis": projection.basis,
        // True when the profile and the clock materially disagree, which is
        // the case worth drawing attention to.
        "disagrees": projection.basis === "profile" && Math.abs(projection.projectedUsedPercent - projection.naiveProjectedPercent) >= 10
    };
}

function compute(window, nowMs) {
    var pct = window.usedPercent != null ? window.usedPercent : window.percent;
    if (pct == null || isNaN(pct))
        return { "known": false, "reason": "no reading" };

    if (window.projection && window.projection.expectedFraction > 0)
        return fromProjection(window, pct, window.projection);

    if (!window.resetAtMs)
        return { "known": false, "reason": "no reset date" };

    var pair = durationOf(window);
    var duration = pair[0];
    var inferred = pair[1];
    if (!duration)
        return { "known": false, "reason": "window length unknown" };

    var startMs = window.resetAtMs - duration;
    var elapsed = (nowMs - startMs) / duration;

    // Right at the boundary the divisor collapses and the projection explodes.
    // Below ~2% elapsed there is not enough of a window to extrapolate from.
    if (elapsed <= 0.02)
        return { "known": false, "reason": "window just started" };
    if (elapsed >= 1)
        return { "known": false, "reason": "window has lapsed" };

    var expected = elapsed * 100;
    // Where usage lands at reset if the current average rate continues.
    var projected = pct / elapsed;

    // Time until 100% at the current average rate. Only meaningful when the
    // projection actually crosses the limit.
    var exhaustAtMs = null;
    if (projected > 100 && pct > 0) {
        var msPerPercent = (nowMs - startMs) / pct;
        exhaustAtMs = startMs + msPerPercent * 100;
    }

    // FALLBACK: no projection on the window, so do the clock-only arithmetic
    // here. Equivalent to the plugin's `basis: "uniform"` cold-start answer.
    return {
        "known": true,
        "source": "client",
        "usedPercent": pct,
        "clockPercent": expected,
        "naiveProjectedPercent": projected,
        "verdict": projected >= 100 ? "will_exhaust" : projected >= 90 ? "tight" : "on_track",
        "confidence": "low",
        "basis": "uniform",
        "disagrees": false,
        // True when the duration came from the ID table rather than from the
        // provider — i.e. the plugin has not been taught this window yet.
        "inferred": inferred,
        "startMs": startMs,
        "durationMs": duration,
        "elapsedPercent": expected,
        "expectedPercent": expected,
        // Positive means burning faster than the window replenishes.
        "deltaPercent": pct - expected,
        "projectedPercent": projected,
        "exhaustAtMs": exhaustAtMs
    };
}

// A short verdict. The dead band is +/-10 points: below that the projection is
// well inside the error introduced by assuming a uniform burn rate, and a
// widget that says "ahead" on a 3-point drift is a widget you learn to ignore.
function verdict(pace) {
    if (!pace.known)
        return { "text": "—", "tone": "neutral" };

    // The plugin's verdict wins when there is one: it was computed against a
    // usage profile the client cannot see, so second-guessing it from the
    // delta alone would throw away the better answer.
    if (pace.verdict === "will_exhaust")
        return { "text": "will exhaust", "tone": "bad" };
    if (pace.verdict === "tight")
        return { "text": "tight", "tone": "warn" };
    if (pace.verdict === "on_track")
        return { "text": "on track", "tone": "good" };

    if (pace.deltaPercent > 10)
        return { "text": "over pace", "tone": "bad" };
    if (pace.deltaPercent < -10)
        return { "text": "under pace", "tone": "good" };
    return { "text": "on pace", "tone": "neutral" };
}

// Confidence is rendered as opacity on the pace marks rather than as a badge.
// A low-confidence forecast should look tentative, not carry a label you have
// to read and then map back onto the arc it qualifies.
function confidenceOpacity(pace) {
    if (!pace.known)
        return 0;
    if (pace.confidence === "high")
        return 1.0;
    if (pace.confidence === "medium")
        return 0.7;
    return 0.4;
}
