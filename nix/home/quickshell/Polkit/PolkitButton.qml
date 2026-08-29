import QtQuick
import qs.Common

// A push button, local to the polkit dialog.
//
// Not from QtQuick.Controls: bringing Controls in for two buttons would drag a
// whole styling system into a shell that is otherwise plain QtQuick, and the
// default style does not look like anything else here. The Shell has no shared
// button idiom yet — when a second plugin needs one, this is what should move
// into `qs.Common`.
Rectangle {
    id: root

    property string text: ""
    // The affirmative action, drawn as a filled accent slab; everything else
    // is an outline.
    property bool primary: false
    property bool enabled: true

    signal activated

    implicitWidth: label.implicitWidth + Theme.polkitPadding * 2
    implicitHeight: Theme.polkitButtonHeight

    radius: Theme.menuRowRadius
    opacity: root.enabled ? 1 : 0.5
    color: {
        if (!root.primary)
            return pointer.containsMouse && root.enabled ? Theme.polkitFieldBackground : "transparent";
        return pointer.containsMouse && root.enabled ? Qt.lighter(Theme.polkitAccent, 1.1) : Theme.polkitAccent;
    }
    border.width: root.primary ? 0 : 1
    border.color: Theme.polkitBorder

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.primary ? Theme.nord0 : Theme.polkitForeground
        font.pixelSize: Theme.polkitBodyFontSize
    }

    MouseArea {
        id: pointer

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
