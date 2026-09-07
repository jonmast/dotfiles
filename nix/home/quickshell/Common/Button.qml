import QtQuick

// Theme needs no import: singleton in this same directory.
//
// The Shell's push button. Was `Polkit/PolkitButton.qml`, whose header said it
// should move here as soon as a second plugin needed one — the network panel's
// "Connect"/"Cancel" pair is that second plugin, so here it is. The polkit
// dialog now uses this and looks identical: every token it referenced
// (`polkitAccent`, `polkitFieldBackground`, `polkitBorder`, `polkitButtonHeight`,
// `polkitBodyFontSize`) aliases the same value as the panel token that replaced
// it, so the promotion is a rename, not a retheme.
//
// Not from QtQuick.Controls: bringing Controls in for a handful of buttons
// would drag a whole styling system into a shell that is otherwise plain
// QtQuick, and the default style does not look like anything else here.
Rectangle {
    id: root

    property string text: ""
    // The affirmative action, drawn as a filled accent slab; everything else
    // is an outline.
    property bool primary: false
    // NOT called `enabled`: Item already has one, and a second meaning for the
    // same word in the same file is a trap for whoever reads it next.
    property bool interactive: true

    signal activated

    implicitWidth: label.implicitWidth + Theme.panelPadding * 2
    implicitHeight: Theme.buttonHeight

    radius: Theme.panelRowRadius
    opacity: root.interactive ? 1 : 0.5
    color: {
        if (!root.primary)
            return pointer.containsMouse && root.interactive ? Theme.panelRowHover : "transparent";
        return pointer.containsMouse && root.interactive ? Qt.lighter(Theme.panelAccent, 1.1) : Theme.panelAccent;
    }
    border.width: root.primary ? 0 : 1
    border.color: Theme.panelBorder

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.primary ? Theme.nord0 : Theme.panelForeground
        font.pixelSize: Theme.panelRowFontSize
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
