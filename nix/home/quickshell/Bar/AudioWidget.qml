import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common

// waybar's `pulseaudio` module, configured as:
//   format         "{icon} {volume}%"
//   format-muted   "muted"
//   format-icons   default: [🔊, 🔉, 🔈]
// with `.muted` red.
//
// The icon order looks inverted, and it is — but waybar picks from an unkeyed
// `format-icons` array by slicing the 0-100 range into equal buckets, so this
// config genuinely showed 🔊 when quiet and 🔈 when loud. Parity means
// reproducing the bug, not fixing it; retheming comes later.
Item {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property bool muted: audio ? audio.muted : false
    // Pipewire volume is 0.0-1.0; waybar spoke in whole percent.
    readonly property int volume: audio ? Math.round(audio.volume * 100) : 0

    // Correct ramp: quiet → loud. waybar's shipped config had these inverted,
    // showing 🔊 at low volume — a bug, not a deliberate choice.
    readonly property var icons: ["🔈", "🔉", "🔊"]

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Without a tracker the default sink's audio properties are never bound
    // and volume/mute read as zero forever.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    Pill {
        id: pill

        Text {
            text: {
                if (root.muted)
                    return "muted";
                const idx = Math.min(Math.floor(root.volume / (100 / root.icons.length)), root.icons.length - 1);
                return root.icons[idx] + " " + root.volume + "%";
            }
            color: root.muted ? Theme.nord11 : Theme.foreground
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    // Click opens the mixer panel. waybar had no equivalent — its audio module
    // ran `pavucontrol` on click, and before that omarchy's ran a `wiremix`
    // TUI in a floating terminal. Both are the same admission: the bar could
    // display audio but not change it. This one can.
    // TapHandler, not a MouseArea: a MouseArea filling the pill sits between
    // the pointer and the WheelHandler below, and scroll-to-change-volume is
    // the most used thing this widget does. Handlers compose; a MouseArea
    // claims the whole item.
    TapHandler {
        onTapped: root.panelOpen = !root.panelOpen
    }

    property bool panelOpen: false

    Popout {
        anchorItem: root
        opened: root.panelOpen
        onDismissed: root.panelOpen = false

        AudioPanel {
            // Gates the peak monitor's capture stream — see AudioPanel.
            active: root.panelOpen
        }
    }

    // waybar's pulseaudio module changed volume on scroll by `scroll-step`,
    // which defaults to 1%.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (!root.audio)
                return;
            const step = event.angleDelta.y > 0 ? 0.01 : -0.01;
            root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + step));
        }
    }
}
