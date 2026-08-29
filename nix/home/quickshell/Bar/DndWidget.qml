import QtQuick
import qs.Common
import qs.Notifications

// The do-not-disturb indicator (issue 05). Not a waybar module — waybar had
// none, because mako here ran on stock defaults with no DND at all.
//
// It does not break the Bar parity contract, for the same reason the tray and
// the window title do not: it collapses to nothing in its resting state, so a
// session with DND off draws exactly the bar issue 03 signed off on. It only
// exists to make the one dangerous state visible, since "DND is on" and "no
// application has said anything for an hour" look identical otherwise.
//
// nord13 (warning), not nord11 (critical): silenced notifications are a state
// worth noticing, not a fault.
Pill {
    id: root

    visible: NotificationService.dnd

    Text {
        text: "DND"
        color: Theme.nord13
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
    }

    HoverHandler {
        id: hover
    }

    // Click to turn it off. Deliberately one-way: this widget cannot turn DND
    // on, because it is not on the bar when DND is off. The keybind
    // ($mod SHIFT N) is the way in; this is the way out you can find without
    // remembering it.
    TapHandler {
        onTapped: NotificationService.toggleDnd()
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            text: "Do not disturb — notifications silenced (click to resume)"
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
