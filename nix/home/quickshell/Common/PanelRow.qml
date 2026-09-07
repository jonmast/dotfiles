import QtQuick

// Theme needs no import: singleton in this same directory.
//
// One selectable line inside a bar popout panel — an output device, a paired
// headset, a wifi network. Every panel is at heart a list of things you can
// pick, so the row is shared rather than rewritten three times.
//
// The current one is marked with a leading accent dot rather than a filled
// background. A full-width highlight would collide with the hover state, and
// then "which one is selected" and "which one is my pointer over" would be the
// same signal — which is precisely the question a device list has to answer.
Item {
    id: root

    property string label: ""
    // Trailing text: a signal strength, a battery percentage, "connecting…".
    // Dimmed, and dropped entirely when empty.
    property string detail: ""
    property bool selected: false
    property bool enabled: true

    signal clicked

    implicitWidth: parent ? parent.width : 0
    implicitHeight: Theme.panelRowHeight

    Rectangle {
        anchors.fill: parent
        radius: Theme.panelRowRadius
        color: hover.hovered && root.enabled ? Theme.panelRowHover : "transparent"
    }

    Rectangle {
        id: marker

        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter

        width: 6
        height: 6
        radius: 3
        color: Theme.panelAccent
        visible: root.selected
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: detailText.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter

        text: root.label
        // Long device descriptions are the norm, not the exception, so the
        // row elides rather than growing the panel.
        elide: Text.ElideRight
        color: Theme.panelForeground
        opacity: root.enabled ? 1 : Theme.panelMetaOpacity
        font.pixelSize: Theme.panelRowFontSize
        renderType: Text.NativeRendering
    }

    Text {
        id: detailText

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

    HoverHandler {
        id: hover

        enabled: root.enabled
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
