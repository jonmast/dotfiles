import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Common

// The bluetooth pill's click-through panel: the adapter switch, the paired
// devices, and whatever discovery has turned up.
//
// Native `Quickshell.Bluetooth` throughout — `connect`, `disconnect`, `pair`,
// `forget` and `cancelPair` are methods on the device, and `battery` comes
// over the same bluez interface. No `bluetoothctl`, and no `rfkill unblock`
// either: omarchy's launcher script had to shell out to rfkill before opening
// its TUI, but `adapter.enabled` goes through bluez, which unblocks a soft
// rfkill on its own.
//
// WHAT THIS DELIBERATELY WILL NOT DO is pairing that needs a PIN confirmation.
// `pair()` is here for devices that pair silently (most headsets), but bluez
// asks for passkey confirmation through an agent, and this shell registers
// none. A keyboard that wants a six-digit code typed into it will start
// pairing and then sit in `pairing` until it times out. That is why the button
// says "Pair" only for devices already in range and why `bluetoothctl` remains
// the answer for a first-time keyboard.
Column {
    id: root

    property bool active: false

    spacing: Theme.panelSpacing

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool adapterOn: adapter ? adapter.state === BluetoothAdapterState.Enabled : false
    readonly property bool adapterBusy: adapter ? (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling) : false

    readonly property var pairedDevices: {
        const out = [];
        if (!root.adapter)
            return out;
        for (const dev of Bluetooth.devices.values) {
            if (dev.paired || dev.bonded)
                out.push(dev);
        }
        return out;
    }

    // Everything discovery has seen that is not already paired. Unnamed
    // devices are dropped: a scan in a populated building turns up a long tail
    // of bare MAC addresses that nobody can identify, and listing them makes
    // the panel useless exactly when it is busiest.
    readonly property var nearbyDevices: {
        const out = [];
        if (!root.adapter)
            return out;
        for (const dev of Bluetooth.devices.values) {
            if (dev.paired || dev.bonded)
                continue;
            if (!dev.name || dev.name === dev.address)
                continue;
            out.push(dev);
        }
        return out;
    }

    // Discovery runs only while the panel is open, and stops when it closes.
    // A permanent scan is a genuine battery cost on a laptop and keeps the
    // radio busy enough to hurt an active A2DP connection.
    //
    // A Binding rather than an `onActiveChanged` handler. The handler version
    // silently did nothing in two cases: a panel whose `active` was already
    // true at construction never emits the change signal, and turning the
    // adapter on from the switch below had to re-poke `discovering` by hand.
    // Binding covers both, and drops discovery back to false on close.
    Binding {
        target: root.adapter
        property: "discovering"
        value: root.active && root.adapterOn
        when: root.adapter !== null
    }

    function describe(dev) {
        if (dev.pairing)
            return "pairing…";
        if (dev.state === BluetoothDeviceState.Connecting)
            return "connecting…";
        if (dev.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting…";
        if (dev.connected)
            return dev.batteryAvailable ? Math.round(dev.battery * 100) + "%" : "connected";
        return "";
    }

    // ---- adapter -------------------------------------------------------

    Item {
        width: parent.width
        implicitHeight: Theme.panelRowHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            text: {
                if (!root.adapter)
                    return "No adapter";
                if (root.adapter.state === BluetoothAdapterState.Blocked)
                    return "Blocked";
                return root.adapterOn ? "Bluetooth on" : "Bluetooth off";
            }
            color: Theme.panelForeground
            font.pixelSize: Theme.panelRowFontSize
            renderType: Text.NativeRendering
        }

        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            checked: root.adapterOn
            busy: root.adapterBusy
            // A Blocked adapter is rfkill'd at the hardware level (the laptop
            // has a key for it). bluez cannot clear that, so the switch says
            // so by refusing rather than by failing silently.
            interactive: root.adapter !== null && root.adapter.state !== BluetoothAdapterState.Blocked
            // Discovery is not touched here: the Binding above follows
            // `adapterOn`, so turning the radio on from this switch starts the
            // scan on its own.
            onToggled: root.adapter.enabled = !root.adapter.enabled
        }
    }

    // ---- paired --------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.adapterOn

        PanelSectionHeader {
            text: "Paired"
            detail: root.pairedDevices.length === 0 ? "none" : ""
        }

        Repeater {
            model: root.pairedDevices

            PanelRow {
                required property var modelData

                label: modelData.name || modelData.address
                detail: root.describe(modelData)
                selected: modelData.connected
                // A device mid-transition is not a thing to click again;
                // bluez will reject the second call anyway.
                enabled: !modelData.pairing && modelData.state !== BluetoothDeviceState.Connecting && modelData.state !== BluetoothDeviceState.Disconnecting

                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect();
                    else
                        modelData.connect();
                }
            }
        }
    }

    // ---- nearby --------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.adapterOn && root.nearbyDevices.length > 0

        PanelSectionHeader {
            text: "Nearby"
            detail: root.adapter && root.adapter.discovering ? "scanning…" : ""
        }

        Repeater {
            model: root.nearbyDevices

            PanelRow {
                required property var modelData

                label: modelData.name || modelData.address
                detail: modelData.pairing ? "pairing…" : ""
                enabled: !modelData.pairing

                // Pairs rather than connects: an unpaired device cannot be
                // connected to. See the header for the PIN caveat.
                onClicked: modelData.pair()
            }
        }
    }
}
