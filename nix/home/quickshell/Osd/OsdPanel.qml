import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// The OSD surface: a small slab at the bottom centre with an icon, a level
// bar and a number.
//
// Mapped only while showing, and it never takes keyboard focus — an overlay
// that grabbed the keyboard for 1.5s every time you nudged the volume would
// eat whatever you typed next.
PanelWindow {
    id: root

    property bool shown: false
    property string icon: ""
    // 0-100, or -1 for "no level" (mute, or a backlight we could not read).
    property int level: 0
    property bool muted: false

    visible: root.shown

    anchors {
        bottom: true
        left: true
        right: true
    }

    margins {
        bottom: Theme.osdMarginBottom
    }

    implicitHeight: slab.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "the-shell-osd"
    // Overlay, unlike the notification banners on Top: an OSD is feedback for
    // a key you just pressed, and pressing volume-up while watching something
    // fullscreen is the single most common time to want it.
    WlrLayershell.layer: WlrLayer.Overlay
    // Default keyboardFocus (None) is left alone deliberately — see above.

    Rectangle {
        id: slab

        anchors.horizontalCenter: parent.horizontalCenter

        width: Theme.osdWidth
        implicitHeight: row.implicitHeight + Theme.osdPadding * 2

        radius: Theme.osdRadius
        color: Theme.osdBackground
        border.width: 1
        border.color: Theme.osdBorder

        Row {
            id: row

            anchors.fill: parent
            anchors.margins: Theme.osdPadding
            spacing: Theme.osdPadding

            Text {
                id: glyph

                anchors.verticalCenter: parent.verticalCenter
                text: root.icon
                color: root.muted ? Theme.osdMuted : Theme.foreground
                font.pixelSize: Theme.osdIconSize
            }

            // The track. Drawn even when muted (as an empty track) so the slab
            // does not change width and jump about between states.
            Rectangle {
                id: track

                anchors.verticalCenter: parent.verticalCenter
                width: row.width - glyph.width - value.width - row.spacing * 2
                height: Theme.osdTrackHeight
                radius: height / 2
                color: Theme.osdTrack

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // Clamped: wpctl will happily set a sink above 100%, and
                    // an unclamped fill would draw outside its own track.
                    width: track.width * Math.max(0, Math.min(100, root.level)) / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.muted ? Theme.osdMuted : Theme.osdFill
                    visible: root.level >= 0 && !root.muted
                }
            }

            Text {
                id: value

                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the slab's internals do not shuffle sideways
                // as the number goes 9 → 10 → 100.
                width: 40
                horizontalAlignment: Text.AlignRight
                text: root.muted ? "mute" : (root.level < 0 ? "" : root.level + "%")
                color: root.muted ? Theme.osdMuted : Theme.foreground
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
