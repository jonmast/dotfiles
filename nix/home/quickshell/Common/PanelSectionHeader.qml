import QtQuick

// Theme needs no import: singleton in this same directory.
//
// The small dimmed label above a group of rows — "Output", "Paired", "Nearby".
// A signpost, never content, which is the one place small type is right.
//
// Carries an optional trailing `detail` for the state of the group as a whole:
// "scanning…" beside nearby networks, "no adapter" beside a bluetooth list.
// That belongs on the header rather than in a row, because a row would look
// like something you can click.
Item {
    id: root

    property string text: ""
    property string detail: ""

    implicitWidth: parent ? parent.width : 0
    implicitHeight: label.implicitHeight + Theme.panelRowSpacing * 2

    Text {
        id: label

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        text: root.text
        color: Theme.panelForeground
        opacity: Theme.panelMetaOpacity
        font.pixelSize: Theme.panelSectionFontSize
        renderType: Text.NativeRendering
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter

        text: root.detail
        color: Theme.panelForeground
        opacity: Theme.panelMetaOpacity
        font.pixelSize: Theme.panelSectionFontSize
        renderType: Text.NativeRendering
        visible: root.detail !== ""
    }
}
