import QtQuick

// Theme needs no import: singleton in this same directory.
//
// The on/off switch at the head of a panel — bluetooth's adapter, wifi's
// radio. A switch rather than a button because the thing it controls has a
// state you need to read at a glance, which a button labelled "Disable" tells
// you only by implication.
//
// `busy` is not decoration. Both radios go through a real transitional state
// (`BluetoothAdapterState.Enabling`, and NetworkManager taking a moment over
// `wifiEnabled`), and a switch that snapped to its new position instantly
// would be lying for as long as that took. While busy the knob sits where it
// is and dims, so the panel says "asked, not yet done".
Item {
    id: root

    property bool checked: false
    property bool busy: false
    // Distinct from `checked`: a bluetooth adapter that is rfkill-blocked, or
    // a wifi radio killed by a hardware switch, cannot be turned on from here
    // at all.
    property bool interactive: true

    signal toggled

    implicitWidth: Theme.toggleWidth
    implicitHeight: Theme.toggleHeight

    opacity: root.interactive ? (root.busy ? 0.6 : 1) : 0.4

    Rectangle {
        id: groove

        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.panelAccent : Theme.panelSliderTrack

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Rectangle {
        id: knob

        // Inset by the same margin at both ends, so the travel is the groove
        // minus the knob minus both insets.
        readonly property int inset: 2

        y: knob.inset
        x: root.checked ? groove.width - width - knob.inset : knob.inset

        width: root.height - knob.inset * 2
        height: width
        radius: width / 2
        color: Theme.nord6

        Behavior on x {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
