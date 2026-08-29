import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// The history panel — what "do not disturb does not lose notifications" is
// actually made of. Everything that arrived while DND was on is here, along
// with everything that expired while you were looking elsewhere.
//
// Built on the same bones as the launcher: full-screen scrim, one card,
// exclusive keyboard focus while mapped, unmapped when closed so there is no
// focus to leak. The differences from MenuPanel are that there is no text
// input and the rows are read-only.
PanelWindow {
    id: root

    property bool opened: false

    signal dismissed

    visible: root.opened

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "the-shell-notification-history"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // ---- geometry ------------------------------------------------------
    //
    // Every size here is derived from the WINDOW, never from the card. The
    // card is sized by its content, so anything inside it that measures the
    // card is a binding loop — and QML resolves a loop by leaving the value
    // at zero, which shows up as a panel with a header and no list rather
    // than as an error. (First draft did exactly that.)
    readonly property int cardTop: Math.round(root.height * Theme.notifHistoryTopFraction)

    // What is left for the scrolling list once the card's own padding, the
    // header, the divider and the gaps between them are taken out.
    readonly property int listAvailableHeight: root.height - root.cardTop - Theme.menuPadding // bottom breathing room
     - Theme.menuPadding * 2 // the card's own padding
     - header.implicitHeight - 1 // header and divider
     - Theme.menuPadding * 2 // the two gaps in the column
    ;

    onVisibleChanged: {
        if (root.visible)
            keys.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.menuScrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.cardTop

        width: Math.min(Theme.notifHistoryWidth, root.width - Theme.menuPadding * 2)
        implicitHeight: content.implicitHeight + Theme.menuPadding * 2

        radius: Theme.menuRadius
        color: Theme.menuBackground
        border.width: 1
        border.color: Theme.menuBorder

        // Swallows clicks that would otherwise dismiss via the scrim.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Escape:
                    root.dismissed();
                    event.accepted = true;
                    break;
                }
            }
        }

        Column {
            id: content

            anchors.fill: parent
            anchors.margins: Theme.menuPadding
            spacing: Theme.menuPadding

            // ---- header --------------------------------------------------

            Item {
                id: header

                width: parent.width
                implicitHeight: title.implicitHeight

                Text {
                    id: title

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.foreground
                    font.pixelSize: Theme.menuQueryFontSize
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.menuPadding

                    // The DND state is stated here as well as in the bar
                    // indicator, because this panel is where you land when
                    // wondering why nothing has popped up for an hour.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: NotificationService.dnd
                        text: "Do not disturb"
                        color: Theme.nord13
                        font.pixelSize: Theme.notifMetaFontSize
                    }

                    Text {
                        id: clear

                        anchors.verticalCenter: parent.verticalCenter
                        visible: NotificationService.history.length > 0
                        text: "Clear"
                        // notifForeground dimmed, not menuDetailForeground —
                        // see the Theme comment on why nord3 body text is a
                        // contrast failure.
                        color: clearPointer.containsMouse ? Theme.nord8 : Theme.notifForeground
                        opacity: clearPointer.containsMouse ? 1 : Theme.notifMetaOpacity
                        font.pixelSize: Theme.notifMetaFontSize

                        MouseArea {
                            id: clearPointer

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.clearHistory()
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.menuBorder
            }

            Text {
                width: parent.width
                visible: NotificationService.history.length === 0
                text: "Nothing yet"
                color: Theme.notifForeground
                opacity: Theme.notifMetaOpacity
                font.pixelSize: Theme.notifBodyFontSize
                height: visible ? Theme.menuRowHeight : 0
                verticalAlignment: Text.AlignVCenter
            }

            // ---- list ----------------------------------------------------
            //
            // Flickable + Column + Repeater rather than a ListView, because
            // every row is a different height (bodies wrap) and the card wants
            // to size itself to them. A ListView only knows the height of the
            // delegates it has realised, so `contentHeight` would be an
            // estimate that changes as you scroll — and the card would resize
            // under the pointer. The history is capped at
            // Theme.notifHistoryMax, so realising all of it is bounded work.

            Flickable {
                id: scroller

                width: parent.width
                height: Math.min(rows.implicitHeight, root.listAvailableHeight)
                visible: NotificationService.history.length > 0

                contentHeight: rows.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: rows

                    width: scroller.width
                    spacing: Theme.notifSpacing

                    Repeater {
                        // Newest first — see NotificationService.record.
                        model: NotificationService.history

                        NotificationCard {
                            required property var modelData

                            width: rows.width

                            summary: modelData.summary
                            body: modelData.body
                            appName: modelData.appName
                            image: modelData.image
                            appIcon: modelData.appIcon
                            urgency: modelData.urgency
                            timeText: Qt.formatDateTime(modelData.time, "HH:mm")

                            // No actions and no dismissal: these are snapshots
                            // of notifications that no longer exist. See
                            // NotificationService.history for why the live
                            // objects are not kept.
                            actions: []
                            // Read-back is the job here, so the body is not
                            // clamped the way a banner's is. The list scrolls
                            // instead.
                            bodyMaxLines: 0
                        }
                    }
                }
            }
        }
    }
}
