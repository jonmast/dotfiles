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

    // Ticks the reset countdowns in the panel. Only runs while the panel is
    // open — a bar that wakes every second to recompute text nobody is reading
    // is exactly the kind of idle drain that shortens battery life on a laptop.
    property double now: Date.now()
    property bool panelOpen: false

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

    // Age of a past instant, as against `formatCountdown`'s distance to a future
    // one. Coarse on purpose: the useful question is "is this reading minutes or
    // hours old", and a ticking seconds figure would draw the eye to the least
    // important number on the card.
    function formatAge(atMs) {
        if (!atMs)
            return "";
        const minutes = Math.floor((root.now - atMs) / 60000);
        if (minutes < 1)
            return "just now";
        if (minutes < 60)
            return minutes + "m ago";
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return hours + "h ago";
        return Math.floor(hours / 24) + "d ago";
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
        // Keyed to the panel rather than to `hover`, because the panel
        // outlives the pill's hover: once the pointer is inside the popup
        // clicking a legend row, the countdowns must keep ticking.
        running: popout.opened
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

    TapHandler {
        onTapped: root.panelOpen = !root.panelOpen
    }

    Popout {
        id: popout

        anchorItem: root
        opened: root.panelOpen
        onDismissed: root.panelOpen = false
        // The tooltip body is a row of provider cards three `cardWidth`s wide,
        // not one — the default panel width would either clip the row or leave
        // the single-card measurement hugging the left edge. Sizing from the
        // row itself keeps it right if the provider count ever changes. Same
        // measured-content idiom as GoogleTvWidget.
        panelWidth: body.contentWidth + Theme.panelPadding * 2

        QuotaTooltip {
            id: body

            host: root
            record: root.record
            now: root.now
        }
    }
}
