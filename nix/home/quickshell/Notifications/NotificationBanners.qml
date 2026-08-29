import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// The banner column: top-right, under the bar, one card per live
// notification.
//
// The window is sized to its content and mapped only while there is something
// in it, so the rest of the time it does not exist and cannot eat clicks
// destined for the desktop. `ExclusionMode.Ignore` because a banner must not
// reflow every tiled window on the monitor for the four seconds it is up.
//
// As with the launcher, no `screen:` binding: Diogenes has one output. If a
// second one ever appears, this and MenuPanel are the two lines to grow.
PanelWindow {
    id: root

    anchors {
        top: true
        right: true
    }

    margins {
        top: Theme.notifMarginTop
        right: Theme.notifMarginSide
    }

    implicitWidth: Theme.notifWidth
    // Never zero: a zero-height layer surface is a protocol error, and this
    // window is only visible when it has content anyway.
    implicitHeight: Math.max(1, column.implicitHeight)

    visible: NotificationService.banners.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "the-shell-notifications"
    // Top, not Overlay — unlike the launcher and the OSD, which are both
    // responses to something you just pressed. A fullscreen window is an
    // explicit "do not interrupt me", and a banner is by definition an
    // interruption from somewhere else. The cost is that a banner raised
    // behind a fullscreen window expires unseen; that is precisely what the
    // history panel is for.
    WlrLayershell.layer: WlrLayer.Top

    Column {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.notifSpacing

        Repeater {
            // Oldest at the top, newest appended below. The other order reads
            // better on paper but is worse to use: every arrival would shove
            // the banner you are mid-way through reading down the screen.
            model: NotificationService.banners

            NotificationCard {
                id: card

                required property var modelData

                width: column.width

                summary: card.modelData.summary
                body: card.modelData.body
                appName: card.modelData.appName
                image: card.modelData.image
                appIcon: card.modelData.appIcon
                urgency: card.modelData.urgency
                actions: card.modelData.actions

                // dismiss() tells the sender the user closed this, which is
                // what a click is. The timer below uses expire() instead, so
                // applications that care can tell the two apart.
                onDismissed: card.modelData.dismiss()

                onActionInvoked: action => {
                    action.invoke();
                    // `resident` senders keep the notification alive across an
                    // action on purpose (a music player's next/previous
                    // buttons). Everything else is finished with once you have
                    // acted on it, and Quickshell has already destroyed it —
                    // so there is nothing to close here either way.
                }

                Timer {
                    // 0 means "until dismissed": critical urgency, or a sender
                    // that explicitly asked for no timeout. See
                    // NotificationService.timeoutFor.
                    interval: NotificationService.timeoutFor(card.modelData)
                    running: interval > 0
                    onTriggered: card.modelData.expire()
                }
            }
        }
    }
}
