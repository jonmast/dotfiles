import QtQuick
import qs.Common

// The ring gauge behind each AI-quota provider card.
//
// Draws one band per entry in `bands`, outermost = longest period. That
// ordering is meaningful rather than cosmetic: a 5-hour window sits INSIDE the
// weekly window that contains it, so the nesting is a real containment
// relationship. In practice the quota tooltip passes a SINGLE band — three
// marks across four bands was unreadable — but the stack is kept because the
// containment is what makes more than one band legible at all if it is ever
// wanted again.
//
// Each band carries two marks on the same radius:
//   - a full-thickness arc for usage
//   - a bright thin arc, drawn on the band's outer edge, for where pace says
//     usage should be
//
// Comparing the two endpoints answers "am I on pace for this window".
Item {
    id: root

    // [{ pct, pacePct, clockPct, known, tone, paceOpacity }], outermost first.
    //
    // `pacePct` is the profile-weighted expectation and `clockPct` the raw
    // wall-clock one. Both are drawn when they disagree, because the gap is
    // the interesting part: usage sitting between them means the clock is
    // alarmed and your actual pattern is not.
    property var bands: []

    // When set, the named lane is brightened and the others dimmed.
    property string hoveredLane: ""

    property int bandThickness: 7
    property int bandGap: 3

    // The two pace marks. Derived from the band rather than fixed, so changing
    // `bandThickness` keeps their proportions instead of leaving hairlines on a
    // fat band.
    //
    // The profile mark is the one being compared against usage, so it is the
    // heavier of the two; the clock mark is a second opinion and stays lighter.
    property real paceThickness: Math.max(3, bandThickness * 0.38)
    property real clockThickness: Math.max(2.5, bandThickness * 0.30)

    // Dash geometry for the clock lane, in pixels of arc length.
    //
    // These were tied to the stroke width — a square dash and an equal gap —
    // which made the dashes grow with the band and read as a chain of blocks
    // rather than as a dashed line. Short marks in a wider gap keep the lane
    // legible as "the provisional one" without it competing with the two solid
    // arcs either side of it.
    // Overridden by the caller, which also draws the key and must match it.
    property real clockDash: 2
    property real clockDashGap: 4

    // Clear space between lanes. Each mark gets its OWN concentric lane rather
    // than being drawn over the usage arc: overlapping strokes on a curve are
    // illegible, because the eye cannot separate two arcs that share pixels and
    // differ only in width and alpha. Comparing arc ENDPOINTS is the whole job,
    // and that needs each arc to own its radius.
    property real markGap: 2

    // Total radial depth of one window's three lanes.
    readonly property real laneExtent: clockThickness + markGap + bandThickness + markGap + paceThickness

    // Colour carries the lane's ROLE, not its value:
    //
    //   usage  the status hue (green / amber / red), set per band by the caller
    //   pace   frost — a reference mark, deliberately outside the status
    //          palette so it can never be misread as a verdict
    //   clock  dimmed foreground — the same kind of thing as `pace`, but the
    //          weaker opinion, so it recedes rather than competing
    //
    // Previously both marks were white at different alphas, which meant the
    // only thing separating them was opacity — invisible once they were on
    // different radii and no longer adjacent for comparison.
    property color paceColor: Theme.nord8
    property color clockColor: Theme.nord4

    // Lane tracks. Faint, but present: without one an empty pace lane and a
    // pace lane that happens to start at zero look identical.
    property color laneTrack: Qt.rgba(1, 1, 1, 0.06)

    // The centre has to stay clear for the forecast number. Bands that would
    // encroach on it are dropped rather than drawn over — a provider with more
    // windows than fit gets fewer rings, not an unreadable middle.
    // Sized so a four-window provider (Claude) still gets a band each, which
    // is the busiest case the record actually produces.
    property int centreRadius: 22

    // Outermost edge of band `index`, walking inward one lane-stack at a time.
    function outerEdgeFor(index) {
        return width / 2 - 1 - index * (laneExtent + bandGap);
    }

    function innerEdgeFor(index) {
        return outerEdgeFor(index) - laneExtent;
    }

    readonly property int maxBands: {
        let n = 0;
        while (innerEdgeFor(n) >= centreRadius && n < 8)
            n++;
        return n;
    }

    // Exposed lane radii (centres) so the caller can do hit-testing, e.g. a
    // tooltip that explains which mark the pointer is over.
    readonly property real paceRadius: {
        const outer = width / 2 - 1;
        return outer - paceThickness / 2;
    }
    readonly property real usageRadius: {
        const outer = width / 2 - 1;
        return outer - paceThickness - markGap - bandThickness / 2;
    }
    readonly property real clockRadius: {
        const outer = width / 2 - 1;
        return outer - paceThickness - markGap - bandThickness - markGap - clockThickness / 2;
    }

    implicitWidth: 112
    implicitHeight: 112

    onBandsChanged: canvas.requestPaint()
    onHoveredLaneChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onBandThicknessChanged: canvas.requestPaint()
    onClockDashChanged: canvas.requestPaint()
    onClockDashGapChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const cx = width / 2;
            const cy = height / 2;
            const start = -Math.PI / 2;

            // Draws a track plus a value arc in one lane. Every lane is the
            // same shape of thing, so they share one routine — which is also
            // what guarantees they never bleed into each other.
            //
            // When `hovered` is true the arc is brightened with a white
            // overlay; when another lane IS hovered the arc is dimmed. Both
            // effects are light enough to read through but make the focused
            // lane unambiguous.
            function lane(radius, thickness, pct, colour, dashed, rounded, hovered) {
                const dimmed = root.hoveredLane !== "" && !hovered;
                ctx.setLineDash([]);
                ctx.lineCap = "butt";
                ctx.lineWidth = thickness;

                ctx.globalAlpha = dimmed ? 0.35 : 1.0;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.strokeStyle = root.laneTrack;
                ctx.stroke();
                ctx.globalAlpha = 1.0;

                if (pct == null || isNaN(pct))
                    return;
                const v = Math.min(Math.max(pct, 0), 100);
                if (v <= 0)
                    return;

                ctx.globalAlpha = dimmed ? 0.35 : 1.0;
                ctx.beginPath();
                if (dashed)
                    ctx.setLineDash([root.clockDash, root.clockDashGap]);
                ctx.lineCap = rounded ? "round" : "butt";
                ctx.arc(cx, cy, radius, start, start + Math.PI * 2 * v / 100);
                ctx.strokeStyle = colour;
                ctx.stroke();
                ctx.setLineDash([]);

                // Brighten the hovered lane with a soft white overlay.
                if (hovered && !dimmed) {
                    ctx.globalAlpha = 0.15;
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, start, start + Math.PI * 2 * v / 100);
                    ctx.strokeStyle = "white";
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;
            }

            const count = Math.min(root.bands.length, root.maxBands);
            for (let i = 0; i < count; i++) {
                const band = root.bands[i];
                const outer = root.outerEdgeFor(i);

                // Three lanes, outermost first: pace, usage, clock.
                const paceR = outer - root.paceThickness / 2;
                const usageR = outer - root.paceThickness - root.markGap - root.bandThickness / 2;
                const clockR = outer - root.paceThickness - root.markGap - root.bandThickness - root.markGap - root.clockThickness / 2;

                const known = band.known === true;

                const hPace = root.hoveredLane === "pace";
                const hUsage = root.hoveredLane === "usage";
                const hClock = root.hoveredLane === "clock";

                lane(paceR, root.paceThickness, known ? band.pacePct : null, Qt.rgba(root.paceColor.r, root.paceColor.g, root.paceColor.b, band.paceOpacity != null ? band.paceOpacity : 1), false, false, hPace);

                lane(usageR, root.bandThickness, known ? band.pct : null, band.tone, false, true, hUsage);

                // The clock lane is drawn whenever there is a reading, even
                // when it agrees with the profile exactly. It used to appear
                // only on a >=3 point disagreement, on the reasoning that a
                // duplicate arc is noise — but that made an arc that comes and
                // goes, which is harder to learn than one that is simply always
                // there, and it meant the key below could name a lane the card
                // was not drawing.
                //
                // When the two coincide the arcs are equal length, which is
                // itself the correct reading: no usage profile, so the clock is
                // all the plugin had to go on.
                lane(clockR, root.clockThickness, known ? band.clockPct : null, Qt.rgba(root.clockColor.r, root.clockColor.g, root.clockColor.b, 0.55), true, false, hClock);
            }
        }
    }
}