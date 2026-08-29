import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common

// waybar's `tray` module (`spacing: 10`).
//
// Left click activates, middle click is the secondary activation, right click
// opens the item's DBus menu — waybar's default bindings. Passive items are
// hidden, matching waybar's `show-passive-items: false` default.
//
// The right-click menu is a platform menu, which is why shell.qml carries
// `//@ pragma UseQApplication`.
Pill {
    id: root

    readonly property var shownItems: {
        const out = [];
        for (const item of SystemTray.items.values) {
            if (item.status === Status.Passive)
                continue;
            out.push(item);
        }
        return out;
    }

    // An empty tray collapses rather than leaving a stub of padding on the
    // bar.
    visible: shownItems.length > 0

    Row {
        spacing: 10

        Repeater {
            model: root.shownItems

            delegate: IconImage {
                id: icon

                required property var modelData

                implicitSize: 16
                source: modelData.icon

                QsMenuAnchor {
                    id: menuAnchor

                    menu: icon.modelData.menu
                    anchor.item: icon
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    // TapHandler hands the button through as the second
                    // argument; reading it off the event point instead is a
                    // Qt5-ism that silently yields NoButton here.
                    onSingleTapped: (eventPoint, button) => {
                        switch (button) {
                        case Qt.LeftButton:
                            // Items that only offer a menu have no meaningful
                            // activation; opening the menu is what a user
                            // clicking them expects.
                            if (icon.modelData.onlyMenu)
                                menuAnchor.open();
                            else
                                icon.modelData.activate();
                            break;
                        case Qt.MiddleButton:
                            icon.modelData.secondaryActivate();
                            break;
                        case Qt.RightButton:
                            if (icon.modelData.hasMenu)
                                menuAnchor.open();
                            break;
                        }
                    }
                }
            }
        }
    }
}
