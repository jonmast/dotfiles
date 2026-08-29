import QtQuick

// Theme needs no import: it is a singleton in this same directory, which QML's
// implicit directory import already covers.
//
// A single bar module's chrome: the rounded translucent slab that every
// waybar module drew via `#module { padding: 0 12px; background: ...;
// border-radius: 6px; margin: 4px 2px }`.
//
// Holds exactly one child, which is centred and drives the pill's width. Bar
// widgets supply that child (usually a Text) and never draw their own
// background, so the slab stays identical across every module — which is what
// "same gaps/rounding feel" in the parity contract actually means.
Rectangle {
    id: root

    default property alias content: container.data

    // Workspace buttons use 10px instead of 12px; everything else keeps the
    // module default.
    property int hPadding: Theme.pillPadding

    // The single content child. Read defensively: during incubation the
    // container is briefly empty and unguarded access would spam type errors.
    readonly property Item child: container.children.length > 0 ? container.children[0] : null

    implicitHeight: Theme.pillHeight
    // Sized from the child's *actual* width, not its implicit width, so a
    // widget that caps itself (the window title elides at a maximum width)
    // shrinks the pill with it. For an unconstrained Text the two are equal.
    implicitWidth: (child ? child.width : 0) + hPadding * 2
    radius: Theme.pillRadius
    color: Theme.pillBackground

    Item {
        id: container

        anchors.centerIn: parent
        width: root.child ? root.child.width : 0
        height: root.child ? root.child.height : 0
    }
}
