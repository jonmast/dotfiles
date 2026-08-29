import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Common

// Volume and brightness OSDs (issue 05).
//
// The two halves are triggered differently on purpose:
//
//   Volume    — reactive. Pipewire publishes the default sink's volume and
//               mute as properties, so the OSD just watches them. That means
//               the media keys need no change at all, and the Bar's
//               scroll-to-change-volume gets the same feedback for free.
//
//   Brightness — pushed over IPC from the keybind. There is no usable change
//               event for a backlight: sysfs does not deliver reliable
//               inotify, and polling would be a process spawn per tick for a
//               value that only moves when a key is pressed.
//
// Either way the keys themselves keep working through `wpctl` and
// `brightnessctl` exactly as they did before, per the plan: an OSD that
// breaks never costs jon working hardware keys.
//
//   bindl = , XF86MonBrightnessUp, exec, brightnessctl set 5%+ && qs -c shell ipc call osd brightness
Scope {
    id: root

    // "volume" or "brightness" — whichever fired last owns the surface. One
    // surface rather than two, because they are never both wanted: the second
    // key press should replace the first OSD, not stack under it.
    property string mode: "volume"

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink ? root.sink.audio : null
    readonly property bool muted: root.audio ? root.audio.muted : false
    readonly property int volume: root.audio ? Math.round(root.audio.volume * 100) : 0

    // Without a tracker the sink's audio properties are never bound and read
    // as zero forever — the same trap AudioWidget documents.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // ---- priming --------------------------------------------------------
    //
    // A reactive OSD has one failure mode: it fires on values it did not
    // cause. Two cases, both real —
    //
    //   1. At login, Pipewire connects a moment after the shell starts and
    //      the volume property goes 0 → its actual value. Ungated, every
    //      login opens with an OSD.
    //   2. Plugging headphones swaps the default sink, and the new sink's
    //      volume and mute differ from the old one's. That is a device
    //      change, not a volume change; jon did not press anything.
    //
    // So changes are ignored until things have been still for a moment, and
    // the clock restarts whenever the sink itself changes.
    property bool primed: false

    onAudioChanged: {
        root.primed = false;
        primer.restart();
    }

    Timer {
        id: primer

        interval: 500
        running: true
        onTriggered: root.primed = true
    }

    Connections {
        target: root.audio

        function onVolumeChanged() {
            root.showVolume();
        }

        function onMutedChanged() {
            root.showVolume();
        }
    }

    // ---- triggers -------------------------------------------------------

    function showVolume() {
        if (!root.primed)
            return;

        root.mode = "volume";
        panel.shown = true;
        hide.restart();
    }

    function showBrightness() {
        root.mode = "brightness";
        // Asynchronous: the panel maps now and the number lands a few
        // milliseconds later through Brightness.percent. Waiting for the read
        // before showing would put a visible stall on every key press for a
        // value that is about to be correct anyway.
        Brightness.refresh();
        panel.shown = true;
        hide.restart();
    }

    IpcHandler {
        target: "osd"

        function brightness(): string {
            root.showBrightness();
            return "shown";
        }

        // Not used by any keybind — volume is reactive — but exposed so the
        // OSD can be checked by hand without touching the hardware keys.
        function volume(): string {
            root.mode = "volume";
            panel.shown = true;
            hide.restart();
            return "shown";
        }
    }

    // Restarted on every trigger, so holding a volume key down keeps one OSD
    // up for the whole run rather than flickering it per repeat.
    Timer {
        id: hide

        interval: Theme.osdVisibleMs
        onTriggered: panel.shown = false
    }

    OsdPanel {
        id: panel

        // Correct ramp, quiet → loud. The Bar's audio widget deliberately
        // preserves waybar's inverted one for parity; this is new UI and owes
        // that bug nothing.
        readonly property var volumeIcons: ["🔈", "🔉", "🔊"]

        icon: {
            if (root.mode === "brightness")
                return "☀";
            if (root.muted)
                return "🔇";
            const index = Math.min(Math.floor(root.volume / (100 / panel.volumeIcons.length)), panel.volumeIcons.length - 1);
            return panel.volumeIcons[index];
        }

        // -1 means "no level to draw". Only reachable for brightness before
        // the first successful brightnessctl read, e.g. on a desktop with no
        // backlight at all.
        level: {
            if (root.mode === "brightness")
                return Brightness.available ? Brightness.percent : -1;
            return root.volume;
        }

        muted: root.mode === "volume" && root.muted
    }
}
