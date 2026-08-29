import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common

// One notification, drawn. Shared by the banner column and the history panel,
// which is why it takes plain values rather than a Notification: the history
// holds JS snapshots of destroyed notifications (NotificationService), and a
// card that only understood live objects would need a second implementation
// for them — i.e. two places for the styling to drift.
//
// Sized by its content. The caller sets the width.
Rectangle {
    id: root

    property string summary: ""
    property string body: ""
    property string appName: ""
    // Raw values off the notification: `image` is already a path (the sender
    // either passed one or Quickshell wrote the image-data hint to a temp
    // file), `appIcon` is a themed icon name.
    property string image: ""
    property string appIcon: ""
    property int urgency: 0
    // Empty on a banner — "just now" is not information. The history sets it.
    property string timeText: ""
    // Live NotificationAction objects, or an empty list. Only banners have
    // these; see NotificationService.history for why.
    property var actions: []
    // Banners clamp the body; the history passes 0 for "no clamp".
    property int bodyMaxLines: Theme.notifBodyMaxLines

    signal dismissed
    signal actionInvoked(var action)

    implicitHeight: layout.implicitHeight + Theme.notifPadding * 2

    radius: Theme.notifRadius
    color: Theme.notifBackground
    border.width: 1
    border.color: Theme.notifBorder
    clip: true

    // Urgency as a stripe on the leading edge rather than a tinted card or a
    // coloured border: it survives being glanced at from across the desk, and
    // it does not fight the body text for contrast the way a tinted
    // background does.
    //
    // Inset by the card's corner radius top and bottom. A full-height stripe
    // is the obvious first draft and looks broken: `clip` is rectangular in
    // Qt, so a square-cornered child is NOT clipped to a rounded parent, and
    // the stripe's corners poke out past the card's rounding. Stopping short
    // of the corners sidesteps the geometry entirely.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.notifRadius
        anchors.bottomMargin: Theme.notifRadius
        width: Theme.notifAccentWidth
        color: NotificationService.accentFor(root.urgency)
    }

    // Click anywhere that is not an action button dismisses. Placed before the
    // content so the action buttons, declared later, sit above it and get the
    // click first.
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Row {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.notifPadding + Theme.notifAccentWidth
        anchors.rightMargin: Theme.notifPadding
        anchors.topMargin: Theme.notifPadding
        spacing: Theme.notifSpacing

        IconImage {
            id: icon

            implicitSize: Theme.notifIconSize
            // Sender-supplied image first (an avatar, an album cover), the
            // application's icon second. The generic fallback matters for the
            // same reason it did in the launcher: IconImage on an unresolvable
            // source draws nothing, and the text would then hang in space
            // where every other card has a column.
            source: {
                if (root.image !== "")
                    return root.image;
                if (root.appIcon !== "")
                    return Quickshell.iconPath(root.appIcon, "dialog-information");
                return Quickshell.iconPath("dialog-information", true);
            }
        }

        Column {
            width: layout.width - icon.width - layout.spacing
            spacing: Theme.notifLineSpacing

            Row {
                width: parent.width
                spacing: Theme.notifSpacing

                Text {
                    id: summaryText

                    width: parent.width - stamp.width - (stamp.width > 0 ? Theme.notifSpacing : 0)
                    text: root.summary
                    color: Theme.foreground
                    font.pixelSize: Theme.notifSummaryFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    id: stamp

                    width: root.timeText === "" ? 0 : implicitWidth
                    visible: root.timeText !== ""
                    text: root.timeText
                    color: Theme.notifForeground
                    opacity: Theme.notifMetaOpacity
                    font.pixelSize: Theme.notifMetaFontSize
                }
            }

            Text {
                width: parent.width
                visible: root.body !== ""
                // Plain text on purpose. The server does not claim
                // body-markup, body-hyperlinks or body-images
                // (NotificationService), so senders are told to give us plain
                // text — and rendering as StyledText anyway would mean any
                // sender that ignores the capability gets its markup honoured
                // while the well-behaved ones get their literal angle
                // brackets eaten.
                textFormat: Text.PlainText
                text: root.body
                // Full-contrast, not dimmed. This is the message.
                color: Theme.notifForeground
                font.pixelSize: Theme.notifBodyFontSize
                wrapMode: Text.Wrap
                // Qt rejects a maximumLineCount below 1, so "unclamped" is
                // spelled as Qt's own default rather than as zero.
                maximumLineCount: root.bodyMaxLines > 0 ? root.bodyMaxLines : 2147483647
                elide: root.bodyMaxLines > 0 ? Text.ElideRight : Text.ElideNone
            }

            Text {
                width: parent.width
                visible: root.appName !== ""
                text: root.appName
                color: Theme.notifForeground
                opacity: Theme.notifMetaOpacity
                font.pixelSize: Theme.notifMetaFontSize
                elide: Text.ElideRight
            }

            // Actions are text buttons. `actionIcons` is not claimed, so a
            // sender's icon names would be names we never asked for.
            Row {
                spacing: Theme.notifSpacing
                visible: root.actions.length > 0
                topPadding: root.actions.length > 0 ? Theme.notifSpacing : 0

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: button

                        required property var modelData

                        implicitWidth: label.implicitWidth + Theme.notifPadding
                        implicitHeight: label.implicitHeight + Theme.notifSpacing
                        radius: Theme.menuRowRadius
                        color: pointer.containsMouse ? Theme.menuSelectedBackground : Theme.nord2

                        Text {
                            id: label

                            anchors.centerIn: parent
                            text: button.modelData.text
                            color: pointer.containsMouse ? Theme.menuSelectedForeground : Theme.foreground
                            font.pixelSize: Theme.notifMetaFontSize
                        }

                        MouseArea {
                            id: pointer

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionInvoked(button.modelData)
                        }
                    }
                }
            }
        }
    }
}
