import QtQuick
import Quickshell

// Theme needs no import — same directory, implicit import.
//
// waybar's tooltip, rebuilt on a layer-shell popup.
//
// A bar pill is 22px tall inside a 30px surface, so tooltip content cannot be
// drawn inside the bar window — it needs its own surface. PopupWindow anchored
// to the hovered item is the equivalent of GTK's tooltip window.
//
// `grabFocus` stays false: waybar tooltips never took input focus, and a
// focus-grabbing popup under Hyprland would steal keyboard focus from the
// window the user is actually typing into just because the pointer crossed
// the clock.
PopupWindow {
    id: root

    // The bar item the tooltip hangs off. Must be an Item inside the bar
    // window — PopupWindow refuses to map until the anchor resolves to a
    // window, which is why this is required rather than optional.
    required property Item anchorItem

    default property alias content: container.data

    readonly property Item child: container.children.length > 0 ? container.children[0] : null

    // Opt-in, and off for every tooltip that is only ever read. A tooltip whose
    // content can be CLICKED cannot dismiss the moment the anchor loses hover:
    // the popup hangs 4px below the bar, so the pointer necessarily leaves the
    // anchor before it arrives, and the control would be unreachable.
    //
    // Interactive tooltips drive `requested` instead of `visible` — the popup
    // then also stays up while the pointer is over it, with a short grace to
    // cross the gap in either direction.
    property bool interactive: false
    property bool requested: false

    readonly property bool pointerOn: requested || (interactive && popupHover.hovered)

    onPointerOnChanged: {
        if (pointerOn)
            grace.stop();
        else if (interactive)
            grace.restart();
    }

    // Long enough to cross a 4px gap at a hand's speed, short enough that a
    // tooltip you walked away from does not linger.
    Timer {
        id: grace

        interval: 150
    }

    anchor.item: anchorItem
    // Hang below the bar, aligned to the item that owns the tooltip.
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    color: "transparent"
    grabFocus: false
    // Read-only tooltips override this outright with their own hover binding.
    visible: pointerOn || grace.running

    Rectangle {
        id: frame

        anchors.fill: parent
        implicitWidth: (root.child ? root.child.implicitWidth : 0) + Theme.tooltipPadding * 2
        implicitHeight: (root.child ? root.child.implicitHeight : 0) + Theme.tooltipPadding * 2
        color: Theme.tooltipBackground
        border.width: 1
        border.color: Theme.tooltipBorder
        radius: Theme.tooltipRadius

        HoverHandler {
            id: popupHover

            enabled: root.interactive
        }

        Item {
            id: container

            anchors.centerIn: parent
            implicitWidth: root.child ? root.child.implicitWidth : 0
            implicitHeight: root.child ? root.child.implicitHeight : 0
            width: implicitWidth
            height: implicitHeight
        }
    }
}
