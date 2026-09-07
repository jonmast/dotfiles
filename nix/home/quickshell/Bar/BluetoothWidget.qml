import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Common

// waybar's `bluetooth` module, configured as:
//   format               "BT {device_alias}"
//   format-connected     "BT {device_alias}"
//   format-disconnected  "BT off"
//   tooltip-format       "{device_enumerate}"
// with `.connected` green and `.off` grey.
//
// `format-disconnected` is not a real waybar bluetooth key (the module's
// states are `format-off`, `format-on`, `format-connected`, `format-disabled`),
// so that line never took effect. waybar fell through to plain `format` with
// an empty `{device_alias}` and rendered a bare "BT" when the adapter was on
// with nothing connected — confirmed by running both bars side by side.
//
// Parity with the actual output, not the config's intent.
Item {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool adapterOn: adapter ? adapter.state === BluetoothAdapterState.Enabled : false

    readonly property var connectedDevices: {
        const out = [];
        for (const dev of Bluetooth.devices.values) {
            if (dev.connected)
                out.push(dev);
        }
        return out;
    }

    // waybar's `{device_alias}` renders the first connected device's alias.
    readonly property string label: connectedDevices.length > 0 ? "BT " + connectedDevices[0].name : "BT"

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Pill {
        id: pill

        Text {
            text: root.label
            color: root.connectedDevices.length > 0 ? Theme.nord14 : (root.adapterOn ? Theme.foreground : Theme.nord3)
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    property bool panelOpen: false

    // TapHandler rather than a MouseArea, for the same reason the audio pill
    // uses one: handlers compose with the HoverHandler below, a MouseArea
    // filling the item would claim the pointer and kill the tooltip.
    TapHandler {
        onTapped: root.panelOpen = !root.panelOpen
    }

    Popout {
        anchorItem: root
        opened: root.panelOpen
        onDismissed: root.panelOpen = false

        BluetoothPanel {
            // Gates device discovery — see BluetoothPanel.
            active: root.panelOpen
        }
    }

    HoverHandler {
        id: hover
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            // waybar's `{device_enumerate}` is one line per *paired* device,
            // marking the connected ones.
            text: {
                const lines = [];
                for (const dev of Bluetooth.devices.values) {
                    if (!dev.paired)
                        continue;
                    lines.push(dev.name + (dev.connected ? " (connected)" : ""));
                }
                return lines.length > 0 ? lines.join("\n") : "No paired devices";
            }
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
