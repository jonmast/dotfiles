.pragma library

// Fuzzy matching for the launcher menu (issue 04).
//
// Pure JavaScript over plain objects: this file knows nothing about Quickshell
// types, so the QML side owns "what is an application" and this side owns "how
// well does a query describe one". That seam is the reason the scoring is
// legible at all — it can be reasoned about without a compositor.
//
// A candidate is:
//   { entry, name, generic, comment, keywords }
// where everything but `entry` is a plain string. `entry` is passed straight
// back out untouched.

// Lower scores rank higher. Field bases keep a weak hit on a strong field from
// outranking a strong hit on a weak one: a subsequence in the name (>= 100)
// still beats any keyword match (>= 400), and the comment — free-form prose
// that mentions half the system — is last by a wide margin.
var NAME_BASE = 0;
var GENERIC_BASE = 400;
var KEYWORD_BASE = 400;
var COMMENT_BASE = 1200;

// A match that is not contiguous. Costs the distance from the start of the
// field plus every character skipped between matched ones, so "dol" scores
// Dolphin far ahead of "Disk Usage Analyzer" even though both contain d-o-l in
// order.
function subsequenceScore(hay, needle) {
    var searchFrom = 0;
    var gaps = 0;
    var first = -1;
    var previous = -1;

    for (var i = 0; i < needle.length; i++) {
        var at = hay.indexOf(needle[i], searchFrom);
        if (at < 0)
            return -1;
        if (first < 0)
            first = at;
        if (previous >= 0 && at > previous + 1)
            gaps += at - previous - 1;
        previous = at;
        searchFrom = at + 1;
    }

    return first * 2 + gaps;
}

// Word starts are what people actually type at: "text editor" should be found
// by "edit". Anything after a space, dash, dot or underscore counts.
function isWordStart(hay, index) {
    if (index === 0)
        return true;
    var before = hay[index - 1];
    return before === " " || before === "-" || before === "_" || before === "." || before === "/";
}

// -1 for no match at all. Otherwise: prefix beats word start beats any other
// contiguous run beats a subsequence, and within each tier an earlier match
// wins.
function fieldScore(hay, needle) {
    if (!hay || !needle)
        return -1;

    var at = hay.indexOf(needle);
    if (at === 0)
        return 0;
    if (at > 0)
        return (isWordStart(hay, at) ? 10 : 40) + at;

    var scattered = subsequenceScore(hay, needle);
    return scattered < 0 ? -1 : 100 + scattered;
}

function best(current, candidate) {
    if (candidate < 0)
        return current;
    if (current < 0)
        return candidate;
    return Math.min(current, candidate);
}

function candidateScore(candidate, needle) {
    var score = -1;
    score = best(score, addBase(fieldScore(String(candidate.name || "").toLowerCase(), needle), NAME_BASE));
    score = best(score, addBase(fieldScore(String(candidate.generic || "").toLowerCase(), needle), GENERIC_BASE));
    score = best(score, addBase(fieldScore(String(candidate.keywords || "").toLowerCase(), needle), KEYWORD_BASE));
    score = best(score, addBase(fieldScore(String(candidate.comment || "").toLowerCase(), needle), COMMENT_BASE));
    return score;
}

function addBase(score, base) {
    return score < 0 ? -1 : score + base;
}

function byName(a, b) {
    var an = String(a.name || "").toLowerCase();
    var bn = String(b.name || "").toLowerCase();
    if (an < bn)
        return -1;
    if (an > bn)
        return 1;
    return 0;
}

// The whole query is one needle, spaces included. Splitting it into terms would
// need a rule for how terms may interleave across fields, and every rule I tried
// was more surprising than "the letters you typed appear in that order".
function search(candidates, query) {
    var needle = String(query || "").trim().toLowerCase();

    if (!needle)
        return candidates.slice().sort(byName);

    var matched = [];
    for (var i = 0; i < candidates.length; i++) {
        var score = candidateScore(candidates[i], needle);
        if (score < 0)
            continue;
        // Copied rather than mutated: candidates is a QML-owned binding result
        // and writing to its members would outlive this call.
        matched.push({
            entry: candidates[i].entry,
            name: candidates[i].name,
            generic: candidates[i].generic,
            comment: candidates[i].comment,
            keywords: candidates[i].keywords,
            icon: candidates[i].icon,
            score: score
        });
    }

    // Name is the tiebreak, so equally-scored rows keep a stable, predictable
    // order instead of whatever the desktop entry scan happened to produce.
    matched.sort(function (a, b) {
        if (a.score !== b.score)
            return a.score - b.score;
        return byName(a, b);
    });

    return matched;
}
