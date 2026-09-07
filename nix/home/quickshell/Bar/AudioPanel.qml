import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common

// The audio pill's click-through panel: a volume slider, an output picker and
// an input picker with a live mic level.
//
// This is what replaced reaching for a mixer TUI. omarchy 4's equivalent panel
// (shell/plugins/panels/audio) also adds a per-app mixer and MPRIS transport
// controls; both are deliberately out of scope here — the panel is for the
// things you open it to do, and per-stream volumes are a thing you do once a
// month in pavucontrol.
//
// Everything is native Pipewire. There is no `wpctl`, no `pactl`, no polling:
// Quickshell 0.3.1 exposes `volume`/`muted` as writable properties and
// `preferredDefaultAudioSink` as the way to move the default. omarchy shells
// out for parts of its network panel; nothing here needs to.
Column {
    id: root

    // Panels are built even while closed (they are children of a widget that
    // is always mapped), so anything expensive — the peak monitor's polling in
    // particular — is gated on this rather than running all session.
    property bool active: false

    spacing: Theme.panelSpacing

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // The pickable devices: real audio nodes, not application streams.
    //
    // `isStream` is what separates a device from a playing application —
    // Firefox appears in `Pipewire.nodes` exactly like a sound card does. The
    // `audio` guard drops video nodes, which carry no volume to show.
    readonly property var sinks: {
        const out = [];
        for (const node of Pipewire.nodes.values) {
            if (node.isStream || !node.audio || !node.isSink)
                continue;
            out.push(node);
        }
        return out;
    }

    readonly property var sources: {
        const out = [];
        for (const node of Pipewire.nodes.values) {
            if (node.isStream || !node.audio || node.isSink)
                continue;
            out.push(node);
        }
        return out;
    }

    // A node's properties stay unbound until something tracks it, so an
    // untracked list renders as a column of blank rows with zero volume. The
    // bar widget tracks only the default sink; the panel has to track
    // everything it draws, for as long as it draws it.
    PwObjectTracker {
        objects: root.active ? root.sinks.concat(root.sources) : []
    }

    // ---- volume --------------------------------------------------------

    Item {
        width: parent.width
        implicitHeight: Theme.panelRowHeight

        readonly property var audio: root.sink ? root.sink.audio : null
        readonly property bool muted: audio ? audio.muted : false
        readonly property int volume: audio ? Math.round(audio.volume * 100) : 0

        // Mute toggle. The glyph matches the bar pill's ramp so the panel and
        // the pill never disagree about what the icon means.
        Text {
            id: muteGlyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            text: parent.muted ? "🔇" : (parent.volume < 34 ? "🔈" : (parent.volume < 67 ? "🔉" : "🔊"))
            color: parent.muted ? Theme.panelSliderMuted : Theme.panelForeground
            font.pixelSize: Theme.osdIconSize

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (parent.parent.audio)
                        parent.parent.audio.muted = !parent.parent.audio.muted;
                }
            }
        }

        Text {
            id: volumeValue

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            // Fixed width so the track does not breathe as the number goes
            // 9 → 10 → 100 (the OSD does the same).
            width: 40
            horizontalAlignment: Text.AlignRight
            text: parent.muted ? "mute" : parent.volume + "%"
            color: parent.muted ? Theme.panelSliderMuted : Theme.panelForeground
            font.pixelSize: Theme.panelRowFontSize
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: track

            anchors.left: muteGlyph.right
            anchors.right: volumeValue.left
            anchors.leftMargin: Theme.panelSpacing
            anchors.rightMargin: Theme.panelSpacing
            anchors.verticalCenter: parent.verticalCenter

            height: Theme.panelSliderHeight
            radius: height / 2
            color: Theme.panelSliderTrack

            Rectangle {
                // Clamped: Pipewire allows volumes above 1.0, and an
                // unclamped fill would draw outside its own track.
                width: track.width * Math.max(0, Math.min(1, track.parent.audio ? track.parent.audio.volume : 0))
                height: parent.height
                radius: parent.radius
                color: track.parent.muted ? Theme.panelSliderMuted : Theme.panelSliderFill
            }

            // Click-to-set and drag-to-scrub in one handler. `preventStealing`
            // keeps a drag that started on the track from being taken by the
            // dismissal MouseArea when the pointer leaves the card mid-drag —
            // without it, dragging past the panel edge closes the panel.
            MouseArea {
                anchors.fill: parent
                // Vertical slop, so grabbing a 10px track does not demand
                // pixel-perfect aim.
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                preventStealing: true

                function apply(x) {
                    if (!track.parent.audio)
                        return;
                    track.parent.audio.volume = Math.max(0, Math.min(1, x / track.width));
                }

                onPressed: event => apply(event.x)
                onPositionChanged: event => {
                    if (pressed)
                        apply(event.x);
                }
            }
        }
    }

    // ---- output --------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing

        PanelSectionHeader {
            text: "Output"
        }

        Repeater {
            model: root.sinks

            PanelRow {
                required property var modelData

                // `description` is the human string ("Built-in Audio Analog
                // Stereo"); `name` is the node path, which is what the bar
                // pill deliberately shows and a picker should not.
                label: modelData.description || modelData.name
                selected: root.sink === modelData
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    // ---- input ---------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing

        PanelSectionHeader {
            text: "Input"
        }

        Repeater {
            model: root.sources

            PanelRow {
                required property var modelData

                label: modelData.description || modelData.name
                selected: root.source === modelData
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }

        // The mic level. Not decoration: "is this thing picking me up" is the
        // question you open an input picker to answer, and a device list alone
        // cannot answer it — a muted or misrouted mic looks identical to a
        // working one until something moves.
        Item {
            width: parent.width
            implicitHeight: Theme.panelRowHeight

            PwNodePeakMonitor {
                id: peak

                node: root.source
                // Peak monitoring opens a real capture stream on the device.
                // Leaving that running while the panel is shut would hold the
                // mic open all session, which is both a battery cost and the
                // kind of thing that lights the "microphone in use" indicator
                // on hardware that has one.
                enabled: root.active
            }

            Text {
                id: micGlyph

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "🎙"
                color: Theme.panelForeground
                font.pixelSize: Theme.osdIconSize
            }

            Rectangle {
                anchors.left: micGlyph.right
                anchors.right: parent.right
                anchors.leftMargin: Theme.panelSpacing
                anchors.verticalCenter: parent.verticalCenter

                height: Theme.panelSliderHeight
                radius: height / 2
                color: Theme.panelSliderTrack

                Rectangle {
                    // The peak is linear amplitude, which spends almost all of
                    // its range near zero for speech — a linear meter barely
                    // twitches when you talk. The square root is the cheap
                    // standard fix, giving a bar that moves the way a level
                    // meter is expected to.
                    width: parent.width * Math.max(0, Math.min(1, Math.sqrt(peak.peak)))
                    height: parent.height
                    radius: parent.radius
                    color: Theme.panelAccent

                    // Falls at a fixed rate rather than tracking the peak down
                    // instantly, so the bar reads as a level meter instead of
                    // flickering at the frame rate.
                    Behavior on width {
                        NumberAnimation {
                            duration: 90
                        }
                    }
                }
            }
        }
    }
}
