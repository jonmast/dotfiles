import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Multi-provider AI quota and CPAMP activity, following the existing pill idiom
// (see DwtWidget for the same Process-on-a-Timer shape).
//
// All fetching, caching, key handling and provider parsing live in `ai-quota`
// (nix/home/scripts/ai-quota.py). This file renders a record and nothing else.
// The quota half of that record is one read-only GET against the
// cpa-quota-api-extension plugin's quota route, which returns a normalized,
// provider-nested snapshot. A widget that fetched for itself would have to own
// a backoff policy, and every side-by-side dev instance
// (`quickshell -p ./nix/home/quickshell`) would run a second copy of it against
// the same rate limit.
//
// Because the script serves from cache, polling here is cheap and is NOT the
// upstream request rate: this timer reads a file, and the script decides when a
// real request is due (default 30 min for quota, 5 min for activity).
Item {
    id: root

    property var record: null

    readonly property var tightest: record && record.tightest ? record.tightest : null
    readonly property bool stale: record ? record.stale === true : false
    readonly property bool ok: record ? record.ok === true : false

    // Ticks the reset countdowns in the tooltip. Only runs while the tooltip is
    // up — a bar that wakes every second to recompute text nobody is reading is
    // exactly the kind of idle drain that shortens battery life on a laptop.
    property double now: Date.now()

    visible: record !== null
    implicitWidth: visible ? pill.implicitWidth : 0
    implicitHeight: pill.implicitHeight

    function formatCountdown(targetMs) {
        const delta = targetMs - root.now;
        if (!targetMs || delta <= 0)
            return "now";
        const minutes = Math.floor(delta / 60000);
        if (minutes < 60)
            return minutes + "m";
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return hours + "h " + (minutes % 60) + "m";
        return Math.floor(hours / 24) + "d " + (hours % 24) + "h";
    }

    function formatTokens(count) {
        if (count >= 1000000)
            return (count / 1000000).toFixed(1) + "M";
        if (count >= 1000)
            return Math.round(count / 1000) + "k";
        return String(count);
    }

    // Thresholds are on percent *consumed*. Amber at 75 and red at 90 leave
    // enough runway to change what you are doing; the battery widget's 30/15
    // would be far too late on a weekly window that cannot be recharged.
    function percentColor(percent) {
        if (percent >= 90)
            return Theme.nord11;
        if (percent >= 75)
            return Theme.nord13;
        return Theme.foreground;
    }

    // A malformed record means the script is mid-write or missing. Keep whatever
    // is on screen: the previous reading is still the best answer available, and
    // blanking the pill would invite a manual check that costs a rate-limited
    // request.
    function applyRecord(text) {
        try {
            root.record = JSON.parse(text);
        } catch (e) {}
    }

    // Two processes rather than one with a mutable `command`: reassigning the
    // command of a Process around `running` races the launch, and the forced
    // refresh is the one path that can deliberately spend a rate-limited
    // request — it must not be able to fire the wrong argv.
    Process {
        id: fetch

        command: ["ai-quota"]
        stdout: StdioCollector {
            id: fetchOut
        }
        onExited: code => {
            if (code === 0)
                root.applyRecord(fetchOut.text);
        }
    }

    Process {
        id: forceFetch

        command: ["ai-quota", "--force"]
        stdout: StdioCollector {
            id: forceOut
        }
        onExited: code => {
            if (code === 0)
                root.applyRecord(forceOut.text);
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }

    Timer {
        interval: 1000
        running: hover.hovered
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    Pill {
        id: pill

        Text {
            // Dimmed rather than hidden when the reading is old. A 5-hour or
            // 7-day window barely moves in the minutes a fetch might be failing,
            // so the number is still substantially true — it just should not
            // claim to be live.
            opacity: root.stale ? 0.55 : 1.0
            text: {
                if (!root.ok)
                    return "AI —";
                const t = root.tightest;
                // Tolerate a record in an unexpected shape (e.g. a half-written
                // cache or a transitional format) rather than printing "NaN%".
                const pct = t != null ? (t.usedPercent != null ? t.usedPercent : t.percent) : null;
                if (pct == null || isNaN(pct))
                    return "AI —";
                const prefix = t.prefix ? t.prefix + " " : "";
                return prefix + Math.round(pct) + "%";
            }
            color: {
                const t = root.tightest;
                const pct = t != null ? (t.usedPercent != null ? t.usedPercent : t.percent) : null;
                return (pct != null && !isNaN(pct)) ? root.percentColor(pct) : Theme.nord3;
            }
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hover
    }

    // A person asking for fresh numbers overrules the reuse window, the same way
    // the admin panel's refresh button does. This is the only path that can
    // deliberately spend a rate-limited request.
    TapHandler {
        onTapped: forceFetch.running = true
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Column {
            spacing: Theme.notifLineSpacing

            // One section per provider. The plugin already collapsed each
            // provider's accounts into a single provider entry carrying its
            // windows, so the client renders from that shape alone — no
            // provider-specific parsing here.
            Repeater {
                model: root.record && root.record.providers ? root.record.providers : []

                Column {
                    spacing: Theme.notifLineSpacing

                    Text {
                        text: modelData.prefix + "  " + modelData.name
                        color: Theme.foreground
                        font.pixelSize: Theme.tooltipFontSize
                        font.bold: true
                        renderType: Text.NativeRendering
                    }

                    // A provider that errored is shown as such rather than being
                    // silently omitted: one broken provider must not blank the
                    // others.
                    Text {
                        visible: !!modelData.error
                        text: "error: " + (modelData.error ? modelData.error.message : "")
                        color: Theme.nord13
                        font.pixelSize: Theme.tooltipFontSize
                        font.family: Theme.monoFamily
                        renderType: Text.NativeRendering
                    }

                    // Every window, not just the one on the pill: the pill
                    // answers "how close am I?", the tooltip answers "to what?".
                    Repeater {
                        model: modelData.windows || []

                        Text {
                            required property var modelData

                            // The window the provider's own API says binds is
                            // marked with a bullet. OpenCode Go also carries the
                            // dollar figures behind its percent, shown in the
                            // tooltip.
                            text: {
                                const pct = (modelData.usedPercent != null) ? modelData.usedPercent : modelData.percent;
                                const pctStr = (pct != null && !isNaN(pct)) ? Math.round(pct) + "%" : "—";
                                let line = (modelData.binding ? "• " : "") + modelData.label + "  " + pctStr + "  ·  resets " + root.formatCountdown(modelData.resetAtMs);
                                if (modelData.usedDollars != null && modelData.limitDollars != null)
                                    line += "  ($" + modelData.usedDollars.toFixed(2) + " / $" + modelData.limitDollars.toFixed(2) + ")";
                                return line;
                            }
                            color: {
                                const pct = (modelData.usedPercent != null) ? modelData.usedPercent : modelData.percent;
                                return (pct != null && !isNaN(pct)) ? root.percentColor(pct) : Theme.foreground;
                            }
                            font.pixelSize: Theme.tooltipFontSize
                            font.family: Theme.monoFamily
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            Text {
                visible: root.record && root.record.today && root.record.today.calls !== undefined
                text: {
                    if (!root.record || !root.record.today)
                        return "";
                    const today = root.record.today;
                    let line = "Today  " + today.calls + " calls  ·  " + root.formatTokens(today.tokens) + " tokens";
                    if (today.failures > 0)
                        line += "  ·  " + today.failures + " failed";
                    return line;
                }
                color: Theme.notifForeground
                opacity: Theme.notifMetaOpacity
                font.pixelSize: Theme.tooltipFontSize
                font.family: Theme.monoFamily
                renderType: Text.NativeRendering
            }

            // Cache hit rate is a prompt-side efficiency number, so it sits with
            // today's token line rather than with the quota windows above — it
            // explains the token count, it is not another limit.
            Text {
                visible: root.record && root.record.today && root.record.today.cacheHitRate >= 0
                text: {
                    if (!root.record || !root.record.today)
                        return "";
                    const today = root.record.today;
                    return "Cache   " + today.cacheHitRate.toFixed(1) + "% hit  ·  " + root.formatTokens(today.cacheReadTokens) + " read  ·  " + root.formatTokens(today.cacheCreationTokens) + " written";
                }
                // Coloured, unlike the other activity lines: this one is
                // actionable. Anything under half means prompts are churning
                // and the cache is not paying for itself.
                color: {
                    if (!root.record || !root.record.today)
                        return Theme.notifForeground;
                    const rate = root.record.today.cacheHitRate;
                    if (rate >= 80)
                        return Theme.nord14;
                    if (rate >= 50)
                        return Theme.nord13;
                    return Theme.nord11;
                }
                font.pixelSize: Theme.tooltipFontSize
                font.family: Theme.monoFamily
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.record && root.record.rolling30m && root.record.rolling30m.rpm > 0
                text: {
                    if (!root.record || !root.record.rolling30m)
                        return "";
                    return "30m     " + root.record.rolling30m.rpm + " rpm  ·  " + root.formatTokens(root.record.rolling30m.tpm) + " tpm";
                }
                color: Theme.notifForeground
                opacity: Theme.notifMetaOpacity
                font.pixelSize: Theme.tooltipFontSize
                font.family: Theme.monoFamily
                renderType: Text.NativeRendering
            }

            Repeater {
                model: root.record && root.record.topModels ? root.record.topModels : []

                Text {
                    required property var modelData

                    text: "  " + modelData.model + "  " + modelData.calls + " calls  ·  " + root.formatTokens(modelData.tokens)
                    color: Theme.notifForeground
                    opacity: Theme.notifMetaOpacity
                    font.pixelSize: Theme.tooltipFontSize
                    font.family: Theme.monoFamily
                    renderType: Text.NativeRendering
                }
            }

            // Only ever shown when there is something to say. An always-present
            // status line trains you to ignore it.
            Text {
                visible: root.record && root.record.error
                text: root.record ? root.record.error : ""
                color: Theme.nord13
                font.pixelSize: Theme.tooltipFontSize
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.stale
                text: {
                    if (!root.record || !root.record.fetchedAtMs)
                        return "";
                    const minutes = Math.floor((root.now - root.record.fetchedAtMs) / 60000);
                    return "Last reading " + (minutes < 1 ? "just now" : minutes + "m ago");
                }
                color: Theme.notifForeground
                opacity: Theme.notifMetaOpacity
                font.pixelSize: Theme.tooltipFontSize
                renderType: Text.NativeRendering
            }

            Text {
                text: "Click to refresh"
                color: Theme.menuDetailForeground
                font.pixelSize: Theme.tooltipFontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
