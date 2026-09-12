import QtQuick
import qs.Common
import "Pace.js" as Pace

// The AI-quota tooltip body: one ring per provider, showing ONE window — by
// default the longest timescale, which is the one whose pace is worth planning
// against. Every other window is a legend row, and clicking a row swaps it into
// the ring.
//
// (An earlier draft drew every window as a concentric band at once. Three marks
// x four bands was too busy to read — the glyph became decoration. Showing one
// window at a time keeps all three pace marks legible and makes the comparison
// sequential rather than simultaneous.)
//
// Because the legend rows are clickable, the tooltip hosting this must be an
// interactive HoverTooltip — otherwise the popup dismisses as the pointer
// leaves the bar pill, before it can reach a row.
//
// The ring carries three marks:
//   - thick arc        usage
//   - thin outer arc   profile-weighted pace (`expected_fraction`)
//   - dashed inner arc raw wall-clock pace, drawn only when it disagrees
//
// Note what does NOT follow the hover: the card's border and its alarm state
// stay pinned to the provider's WORST window. Hover changes what you are
// inspecting, never whether the card is shouting — otherwise pointing at a
// healthy window would make a card in trouble look fine.
Column {
    id: root

    required property var host
    required property var record
    required property double now

    readonly property int cardWidth: 178

    // The width the content is actually built for: one row of provider cards,
    // not a single card. The hosting Popout sizes its panel from this — same
    // measured-content idiom as GoogleTvPanel's `contentWidth`.
    readonly property int contentWidth: providerRow.implicitWidth

    // Clock-lane dash geometry. Declared here rather than left to
    // `ConcentricRings`' own defaults because the key at the foot of the
    // tooltip has to draw the same rhythm, and two copies of these numbers
    // would drift apart the first time either is tuned. The rings below are
    // bound to them.
    readonly property real clockDash: 2
    readonly property real clockDashGap: 4

    function toneColor(tone) {
        if (tone === "bad")
            return Theme.nord11;
        if (tone === "warn")
            return Theme.nord13;
        if (tone === "good")
            return Theme.nord14;
        return Theme.notifForeground;
    }

    // Outermost = longest window, by the window's LENGTH — not by how long is
    // left of it.
    //
    // Those are not interchangeable, and using the second was a bug: OpenCode Go
    // ships `monthly` without a `windowSeconds`, so it fell back to its reset
    // distance, and a month with 5 days left sorted below a 7-day weekly. The
    // card led with Weekly instead of Monthly. Worse, it was not even a stable
    // wrong answer — the remaining time shrinks toward zero as the reset nears,
    // so the default window silently changed partway through every month.
    //
    // `Pace.durationOf` already owns this inference (calendar months measured
    // back from their reset date, Claude's scoped weeklies mapped onto the
    // weekly span), so ordering asks it rather than keeping a second, worse copy
    // of the same reasoning. Reset distance survives only as a last resort, for
    // a window with neither a declared span nor a known id.
    function orderedWindows(provider) {
        const windows = (provider.windows || []).slice();
        function span(w) {
            const known = Pace.durationOf(w)[0];
            if (known > 0)
                return known;
            return w.resetAtMs ? w.resetAtMs - root.now : 0;
        }
        windows.sort((a, b) => {
            const delta = span(b) - span(a);
            if (delta !== 0)
                return delta;
            // Ties go to the containing window. Claude's model-scoped weeklies
            // have the same span as the account weekly that contains them, and
            // defaulting the ring to "Fable" rather than "Weekly (7d)" would
            // lead with a subdivision instead of the whole.
            return (a.model === true ? 1 : 0) - (b.model === true ? 1 : 0);
        });
        return windows;
    }

    function readingFor(window) {
        const pct = window.usedPercent != null ? window.usedPercent : window.percent;
        const known = pct != null && !isNaN(pct);
        const pace = Pace.compute(window, root.now);
        return {
            "window": window,
            "pct": pct,
            "known": known,
            "pace": pace,
            "verdict": Pace.verdict(pace),
            "tone": known ? root.host.percentColor(pct) : Theme.nord3
        };
    }

    spacing: 12

    Row {
        id: providerRow

        spacing: 8

        Repeater {
            model: root.record && root.record.providers ? root.record.providers : []

            Rectangle {
                id: card

                required property var modelData

                readonly property var readings: {
                    const out = [];
                    const windows = root.orderedWindows(card.modelData);
                    for (let i = 0; i < windows.length; i++)
                        out.push(root.readingFor(windows[i]));
                    return out;
                }

                // Which window the ring is showing. 0 is the longest timescale,
                // since `orderedWindows` sorts longest first. Clicking a legend
                // row sets this, and it STAYS set — there is no restore-on-exit,
                // because a selection that undoes itself when the pointer moves
                // cannot be compared against the card next to it.
                property int selectedIndex: 0

                readonly property var selected: card.readings.length > 0 ? card.readings[Math.min(card.selectedIndex, card.readings.length - 1)] : null

                // The provider's worst window by the plugin's own verdict. Only
                // drives the alarm treatment, never the ring — see the note at
                // the top of the file.
                readonly property var lead: {
                    const rank = { "will_exhaust": 3, "tight": 2, "on_track": 1 };
                    let best = null;
                    let bestScore = -1;
                    for (let i = 0; i < card.readings.length; i++) {
                        const r = card.readings[i];
                        if (!r.known)
                            continue;
                        const score = (rank[r.pace.verdict] || 0) * 1000 + r.pct;
                        if (score > bestScore) {
                            bestScore = score;
                            best = r;
                        }
                    }
                    return best;
                }

                width: root.cardWidth
                implicitHeight: cardBody.implicitHeight + 26
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: card.modelData.error ? Theme.nord11 : card.lead && card.lead.verdict.tone === "bad" ? Theme.nord11 : Qt.rgba(1, 1, 1, 0.07)

                Column {
                    id: cardBody

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 6

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.name
                        color: Theme.foreground
                        font.pixelSize: Theme.tooltipFontSize
                        font.bold: true
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    Item {
                        id: ringArea
                        width: parent.width
                        height: 112

                        // Hover detection for the visual effect, driven by the
                        // same distance-from-centre logic the click handler uses.
                        readonly property string hoveredLane: {
                            if (!ringMouse.containsMouse)
                                return "";
                            const dx = ringMouse.mouseX - width / 2;
                            const dy = ringMouse.mouseY - height / 2;
                            const dist = Math.sqrt(dx * dx + dy * dy);
                            if (Math.abs(dist - rings.paceRadius) <= rings.paceThickness / 2 + 2)
                                return "pace";
                            if (Math.abs(dist - rings.usageRadius) <= Theme.quotaRingThickness / 2 + 2)
                                return "usage";
                            if (Math.abs(dist - rings.clockRadius) <= rings.clockThickness / 2 + 2)
                                return "clock";
                            return "";
                        }

                        property string selectedLane: ""

                        MouseArea {
                            id: ringMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: ringArea.hoveredLane !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                const lane = ringArea.hoveredLane;
                                ringArea.selectedLane = (lane === ringArea.selectedLane) ? "" : lane;
                            }
                        }

                        // Lane explainer, anchored to the ring. Only possible
                        // now that we are in a PanelWindow — a HoverTooltip
                        // inside a PopupWindow (the old tooltip path) could not
                        // resolve its anchorItem.
                        HoverTooltip {
                            anchorItem: ringArea
                            visible: ringArea.hoveredLane !== ""

                            Text {
                                text: {
                                    switch (ringArea.hoveredLane) {
                                    case "pace": return "expected pace — where you should be based on your usage profile";
                                    case "usage": return "used — current quota consumed";
                                    case "clock": return "clock — where a linear rate would put you by now";
                                    default: return "";
                                    }
                                }
                                color: Theme.foreground
                                font.pixelSize: Theme.tooltipFontSize
                                renderType: Text.NativeRendering
                            }
                        }

                        ConcentricRings {
                            id: rings

                            anchors.centerIn: parent
                            width: 112
                            height: 112
                            visible: !card.modelData.error
                            // A single band, so it can afford to be thick
                            // enough to carry all three marks clearly.
                            bandThickness: Theme.quotaRingThickness
                            clockDash: root.clockDash
                            clockDashGap: root.clockDashGap
                            hoveredLane: ringArea.selectedLane || ringArea.hoveredLane
                            bands: {
                                const r = card.selected;
                                if (!r)
                                    return [];
                                return [
                                    {
                                        "pct": r.pct,
                                        "known": r.known,
                                        "tone": r.tone,
                                        "pacePct": r.pace.known ? r.pace.expectedPercent : null,
                                        "clockPct": r.pace.known ? r.pace.clockPercent : null,
                                        "paceOpacity": Pace.confidenceOpacity(r.pace)
                                    }
                                ];
                            }
                        }

                        // Click-to-reveal lane description. Sits at the
                        // bottom of the ring area, below the clock lane,
                        // inside the existing 112px height.
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            visible: ringArea.selectedLane !== ""
                            text: {
                                switch (ringArea.selectedLane) {
                                case "pace": return "expected pace — where you should be based on your usage profile";
                                case "usage": return "used — current quota consumed";
                                case "clock": return "clock — where a linear rate would put you by now";
                                default: return "";
                                }
                            }
                            color: Theme.notifForeground
                            opacity: 0.55
                            font.pixelSize: 8
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }

                        // The centre is the selected window's CURRENT usage —
                        // the measured fact, and the number the ring's usage
                        // band is drawing. A forecast sat here previously, on
                        // the reasoning that the arcs already show usage so the
                        // centre should add something new. That was wrong twice
                        // over: it put the least certain number in the most
                        // prominent slot, and it labelled the glyph with a
                        // figure that matched none of its three arcs, so the
                        // eye had nothing to tie the number back to.
                        //
                        // The forecast is still on the card, in the two places
                        // that suit it: the verdict chip below, and each legend
                        // row's "now → projected".
                        Column {
                            anchors.centerIn: parent
                            spacing: -2
                            visible: !card.modelData.error && card.selected

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: card.selected && card.selected.known ? Math.round(card.selected.pct) + "%" : "—"
                                // The usage hue, not the verdict's — this
                                // number is the usage band restated, so it
                                // takes the band's colour. The verdict keeps
                                // its own colour on the chip below.
                                color: card.selected && card.selected.known ? card.selected.tone : Theme.nord3
                                font.pixelSize: 16
                                font.bold: true
                                renderType: Text.NativeRendering
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "used"
                                color: Theme.notifForeground
                                opacity: 0.5
                                font.pixelSize: 8
                                renderType: Text.NativeRendering
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            visible: !!card.modelData.error
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: card.modelData.error ? card.modelData.error.message : ""
                            color: Theme.nord11
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                        }
                    }



                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !card.modelData.error && !!card.selected
                        width: verdictText.implicitWidth + 14
                        height: 17
                        radius: 8
                        color: {
                            if (!card.selected)
                                return "transparent";
                            const c = root.toneColor(card.selected.verdict.tone);
                            return Qt.rgba(c.r, c.g, c.b, 0.20);
                        }

                        Text {
                            id: verdictText

                            anchors.centerIn: parent
                            text: {
                                if (!card.selected)
                                    return "";
                                if (card.selected.pace.exhaustAtMs)
                                    return "out in " + root.host.formatCountdown(card.selected.pace.exhaustAtMs);
                                return card.selected.verdict.text;
                            }
                            color: card.selected ? root.toneColor(card.selected.verdict.tone) : Theme.notifForeground
                            font.pixelSize: 10
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    // When the quota comes back. Sits directly under the
                    // verdict because the two are read together: "out in 37m"
                    // means one thing against a window that resets in 4h and
                    // something else entirely against one that resets in 6d.
                    // The forecast is only actionable next to its deadline.
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !card.modelData.error && !!card.selected && !!card.selected.window.resetAtMs
                        text: card.selected && card.selected.window.resetAtMs ? "resets in " + root.host.formatCountdown(card.selected.window.resetAtMs) : ""
                        color: Theme.notifForeground
                        opacity: 0.6
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }

                    // Legend, and the control surface. Ordering is stable
                    // (longest period first) so the default selection is always
                    // the top row, which is also where the pointer lands first.
                    Repeater {
                        model: card.readings

                        Item {
                            id: legend

                            required property var modelData
                            required property int index

                            readonly property bool active: card.selectedIndex === legend.index

                            width: cardBody.width
                            implicitHeight: 16

                            // The whole row is the target, not just the label —
                            // a 10px word is a miserable thing to have to hit
                            // with a pointer.
                            //
                            // CLICK, not hover. Hover-to-select made the ring
                            // change under the pointer on the way to somewhere
                            // else, so crossing the legend to reach another
                            // card animated three windows you never asked to
                            // see. Selection is a deliberate act and now needs
                            // a deliberate gesture; hover is demoted to an
                            // affordance that says "this row is clickable".
                            HoverHandler {
                                id: legendHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: card.selectedIndex = legend.index
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -4
                                anchors.rightMargin: -4
                                radius: 3
                                // Selection is the stronger of the two states:
                                // hover only says the row can be clicked, so it
                                // must not look like the row that IS selected.
                                color: legend.active ? Qt.rgba(1, 1, 1, 0.07) : legendHover.hovered ? Qt.rgba(1, 1, 1, 0.03) : "transparent"
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 1
                                color: legend.modelData.tone
                                opacity: legend.active ? 1.0 : 0.55
                            }

                            Text {
                                x: 11
                                width: parent.width - 11 - 62
                                anchors.verticalCenter: parent.verticalCenter
                                text: legend.modelData.window.label
                                color: legend.active ? Theme.foreground : Theme.notifForeground
                                opacity: legend.active ? 1.0 : 0.6
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }

                            // Current, then projected. The arrow is the whole
                            // point of the variant in text form, and it is the
                            // fallback for anyone who cannot read the arcs.
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (!legend.modelData.known)
                                        return "—";
                                    const now = Math.round(legend.modelData.pct) + "%";
                                    if (!legend.modelData.pace.known)
                                        return now;
                                    return now + " → " + Math.round(legend.modelData.pace.projectedPercent) + "%";
                                }
                                color: root.toneColor(legend.modelData.verdict.tone)
                                opacity: 0.9
                                font.pixelSize: 10
                                font.family: Theme.monoFamily
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    // Said once per card, not once per band: when the plugin
                    // had no profile to work from, every forecast on the card
                    // is clock-only and should be read as provisional.
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: !card.modelData.error && !!card.selected && card.selected.pace.known && card.selected.pace.basis === "uniform"
                        text: "no usage profile yet — clock only"
                        color: Theme.notifForeground
                        opacity: 0.45
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }

                    // Flagged only when the two disagree enough to change the
                    // decision. The dashed inner arc shows it; this says it.
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: !card.modelData.error && !!card.selected && card.selected.pace.known && card.selected.pace.disagrees === true
                        text: card.selected && card.selected.pace.known ? "clock alone says " + Math.round(card.selected.pace.naiveProjectedPercent) + "%" : ""
                        color: Theme.notifForeground
                        opacity: 0.45
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    // The key. Once for the whole tooltip, not once per card — it describes the
    // glyph, and the glyph is the same on every card.
    //
    // Listed outermost-to-innermost, matching the order the ring draws them, so
    // the key can be mapped onto the glyph by POSITION as well as by colour.
    // Each swatch uses its lane's real colour, stroke weight and dash pattern;
    // a key drawn in some tidier house style would be a second thing to learn.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14

        Repeater {
            model: [
                {
                    "label": "expected pace",
                    "colour": Theme.nord8,
                    "thickness": Math.max(3, Theme.quotaRingThickness * 0.38),
                    "dashed": false
                },
                {
                    // The only lane whose colour carries a value rather than a
                    // role, so the swatch is deliberately neutral: showing it
                    // in green here would read as "used is green".
                    "label": "used",
                    "colour": Theme.notifForeground,
                    "thickness": Theme.quotaRingThickness,
                    "dashed": false
                },
                {
                    "label": "clock",
                    "colour": Qt.rgba(Theme.nord4.r, Theme.nord4.g, Theme.nord4.b, 0.55),
                    "thickness": Math.max(2.5, Theme.quotaRingThickness * 0.30),
                    "dashed": true
                }
            ]

            Row {
                id: keyEntry

                required property var modelData

                spacing: 5

                // A straightened-out piece of the lane it names.
                Item {
                    width: 18
                    height: keyEntry.modelData.thickness
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        // Solid lanes draw one bar; the dashed lane repeats the
                        // ring's own dash rhythm so it is recognisably the same
                        // mark. Both come from `ConcentricRings` rather than
                        // being restated here, or the key drifts out of step
                        // with the glyph the moment either is tuned.
                        model: keyEntry.modelData.dashed ? Math.floor(18 / (root.clockDash + root.clockDashGap)) + 1 : 1

                        Rectangle {
                            required property int index

                            width: keyEntry.modelData.dashed ? root.clockDash : 18
                            height: keyEntry.modelData.thickness
                            x: keyEntry.modelData.dashed ? index * (root.clockDash + root.clockDashGap) : 0
                            color: keyEntry.modelData.colour
                        }
                    }
                }

                Text {
                    text: keyEntry.modelData.label
                    color: Theme.notifForeground
                    opacity: 0.55
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                }
            }
        }
    }

    Row {
        spacing: 8

        Repeater {
            model: {
                const today = root.record && root.record.today ? root.record.today : null;
                const rolling = root.record && root.record.rolling30m ? root.record.rolling30m : null;
                if (!today)
                    return [];
                return [
                    {
                        "value": String(today.calls),
                        "label": today.failures > 0 ? "calls today · " + today.failures + " failed" : "calls today",
                        "tone": today.failures > 0 ? Theme.nord13 : Theme.foreground
                    },
                    {
                        "value": root.host.formatTokens(today.tokens),
                        "label": rolling && rolling.tpm > 0 ? "tokens · " + root.host.formatTokens(rolling.tpm) + " tpm" : "tokens today",
                        "tone": Theme.foreground
                    },
                    {
                        "value": today.cacheHitRate.toFixed(0) + "%",
                        "label": "cache hit",
                        "tone": today.cacheHitRate >= 80 ? Theme.nord14 : today.cacheHitRate >= 50 ? Theme.nord13 : Theme.nord11
                    }
                ];
            }

            Rectangle {
                id: stat

                required property var modelData

                width: root.cardWidth
                height: 44
                radius: 6
                color: Qt.rgba(1, 1, 1, 0.04)

                Column {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: stat.modelData.value
                        color: stat.modelData.tone
                        font.pixelSize: 16
                        font.bold: true
                        renderType: Text.NativeRendering
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: stat.modelData.label
                        color: Theme.notifForeground
                        opacity: Theme.notifMetaOpacity
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    // The one gesture in the shell that deliberately spends a rate-limited
    // upstream request, and the age of what it would replace — stated together,
    // because "refresh" is only a meaningful offer next to how stale the thing
    // being refreshed is.
    //
    // The age shown is the SERVER's, not this client's. The plugin holds its own
    // cache and only calls the providers on a miss, so the moment the local
    // fetch happened says nothing about how old the numbers are.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
            const age = root.record ? root.host.formatAge(root.record.generatedAtMs) : "";
            return age ? "click the bar to refresh · updated " + age : "click the bar to refresh";
        }
        color: Theme.notifForeground
        opacity: 0.45
        font.pixelSize: 9
        renderType: Text.NativeRendering
    }
}
