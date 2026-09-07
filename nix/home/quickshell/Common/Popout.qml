import QtQuick
import Quickshell
import Quickshell.Wayland

// Theme needs no import: singleton in this same directory.
//
// The chrome shared by every bar widget's click-through panel — the audio
// mixer, the bluetooth device list, the wifi picker. A widget supplies the
// contents and a `anchorItem`; this owns the surface, the placement, and the
// two ways out (ESC, click-off).
//
// WHY A FULL-SCREEN OVERLAY RATHER THAN A PopupWindow
//
// HoverTooltip next door is a PopupWindow anchored to its bar item, which is
// the obvious shape for something hanging off a pill — and it is the wrong one
// here. A tooltip is dismissed by moving the pointer away, which the hover
// handler already knows about. A panel is dismissed by clicking somewhere
// else, and a PopupWindow cannot see a click it does not contain.
//
// Quickshell's answer to that is HyprlandFocusGrab, which takes the pointer
// and keyboard for a set of windows and reports when the grab is broken.
// It is NOT in the pinned 0.3.1 build — `Quickshell/Hyprland` ships no
// FocusGrab type at all (checked against the qmltypes in the store path the
// flake resolves to). So the click-off has to be a surface we own.
//
// Which is exactly what MenuPanel already does: one transparent layer-shell
// surface over the whole output, mapped only while open, with the card drawn
// inside it. A click anywhere that is not the card lands on this window and
// closes it. That pattern is proven in this shell, so panels reuse it rather
// than inventing a second dismissal mechanism.
//
// KEYBOARD FOCUS is Exclusive, matching the launcher. It is the price of ESC
// working, and it is only held while a panel is open — an unmapped layer
// surface holds no focus, so there is no residue after dismissal.
PanelWindow {
    id: root

    // The bar pill this panel belongs to. Used only to place the card under
    // the widget that opened it; unlike PopupWindow's `anchor.item` this is
    // not a mapping constraint, so the panel still opens if the widget is
    // mid-relayout.
    required property Item anchorItem

    property bool opened: false

    // Card width. Overridable because not every panel holds a list of long
    // device names: a panel whose rows are all buttons of known width can
    // measure itself instead — see GoogleTvWidget.
    property int panelWidth: Theme.panelWidth

    signal dismissed

    default property alias content: holder.data

    readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

    // Where the anchoring pill sits in screen coordinates.
    //
    // Assigned, NOT bound. `mapToItem` is an ordinary function call: QML has no
    // way to know the answer changed, so a binding written around it is
    // evaluated once — at creation, before the bar's Row has laid out — and
    // then keeps returning that first answer forever. Written as a binding this
    // read 0 and every panel opened in the top-left corner.
    //
    // So it is recomputed at the three moments it can actually change: when the
    // panel opens, and when the pill moves or resizes underneath it (the
    // right-hand group is laid out right-to-left, so every widget shifts
    // whenever the clock's text or the AI quota widget changes width).
    property real anchorCentreX: 0

    function updateAnchor() {
        if (!root.anchorItem)
            return;
        // `mapToItem(null, ...)` gives coordinates in the BAR window's root
        // item, not the screen — the bar is inset by its own side margin, so
        // that margin has to be added back. The bar is anchored left+right, so
        // there is no horizontal offset beyond it.
        root.anchorCentreX = root.anchorItem.mapToItem(null, root.anchorItem.width / 2, 0).x + Theme.barMarginSide;
    }

    onOpenedChanged: if (root.opened)
        root.updateAnchor()

    Connections {
        target: root.anchorItem

        function onXChanged() {
            root.updateAnchor();
        }

        function onWidthChanged() {
            root.updateAnchor();
        }
    }

    visible: root.opened

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "the-shell-popout"
    // Overlay for the same reason the launcher is: a panel summoned from the
    // bar must draw over a fullscreen window, which is often what is focused.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // A full-screen surface that reserved space would push every tiled window
    // off the monitor.
    exclusionMode: ExclusionMode.Ignore

    // No scrim. The launcher dims the desktop because it is modal and holds
    // your whole attention; a volume slider is a glance, and dimming the
    // screen to change the volume of what you are watching is absurd.
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Item {
        // Focus lives on a plain Item rather than the card so the key handler
        // survives the card being rebuilt by a content change.
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.dismissed()

        // Panels that want keys of their own (the TV remote's d-pad) declare
        // Keys handlers on their root item and get them delivered here.
        // Forwarding rather than moving focus keeps ESC working, and means a
        // text field inside the panel still wins the keyboard the moment it
        // takes focus — forwarding only happens while THIS item has it.
        Keys.forwardTo: root.child ? [root.child] : []
    }

    Rectangle {
        id: card

        // Hung under the bar, horizontally centred on its pill but never
        // allowed off-screen — the tray and clock sit close enough to the
        // right edge that an uncorrected centre would overhang it.
        y: Theme.notifMarginTop
        x: Math.max(Theme.barMarginSide, Math.min(root.width - width - Theme.barMarginSide, root.anchorCentreX - width / 2))

        width: root.panelWidth
        // Capped, then scrolled. A wifi scan in a flat turns up twenty-odd
        // networks and a bluetooth scan sixteen devices — measured here, not
        // imagined — so an uncapped card is taller than the output it is drawn
        // on, and the rows at the bottom are unreachable.
        implicitHeight: Math.min((root.child ? root.child.implicitHeight : 0) + Theme.panelPadding * 2, root.height * Theme.panelMaxHeightFraction)

        radius: Theme.panelRadius
        color: Theme.panelBackground
        border.width: 1
        border.color: Theme.panelBorder

        // Swallows clicks that land on the card so they never reach the
        // dismissal MouseArea underneath. Without this every interaction with
        // the panel's own contents would also close it.
        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            id: container

            anchors.fill: parent
            anchors.margins: Theme.panelPadding

            contentHeight: holder.implicitHeight
            contentWidth: width
            // Nothing to fling when the content fits, which is the common case
            // — a panel that rubber-banded on a three-row device list would
            // feel broken.
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // An explicit holder rather than putting the panel straight into
            // the Flickable. A Flickable has TWO content properties: `data`
            // (its own children, which do not scroll) and the default
            // `flickableData` (reparented onto `contentItem`, which does).
            // Aliasing the wrong one is silent — the card simply measures as
            // empty and collapses to zero height. Naming the holder makes
            // which one this is unambiguous, and gives `child` somewhere
            // stable to look.
            Item {
                id: holder

                // ESC also handled here, not only on the focus item above: a
                // text field inside a panel holds focus while you type, and
                // key events travel up the parent chain, which reaches this
                // ancestor but never that sibling.
                Keys.onEscapePressed: root.dismissed()

                width: container.width
                implicitHeight: root.child ? root.child.implicitHeight : 0
            }
        }

        // The card is a fixed width, so the contents are told what that width
        // is rather than being asked. Done as a Binding rather than in the
        // content itself so that panels never have to know they live in a
        // Popout — they lay out against `width` like any other Item.
        Binding {
            target: root.child
            property: "width"
            value: holder.width
            when: root.child !== null
        }
    }
}
