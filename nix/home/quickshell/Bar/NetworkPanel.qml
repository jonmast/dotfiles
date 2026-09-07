import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Common

// The network pill's click-through panel: the wifi switch, the networks in
// range, and a passphrase prompt for the ones that need it.
//
// Native `Quickshell.Networking`, which is NetworkManager underneath — the
// same daemon `networking.networkmanager.enable` already runs on this host.
// `connectWithPsk` does the whole join (profile creation included), so unlike
// omarchy's equivalent panel there is no `nmcli` anywhere in here.
//
// ENTERPRISE NETWORKS ARE NOT SUPPORTED and say so rather than failing.
// 802.1X needs a full settings object through `connectWithSettings`, with an
// identity, an EAP method and usually a CA certificate — a form, not a
// passphrase field. omarchy shells out to `nmcli` for exactly this case. Until
// that form exists those rows are disabled, which is at least legible; a
// passphrase box that could never work would not be.
Column {
    id: root

    property bool active: false

    spacing: Theme.panelSpacing

    readonly property var wifiDevice: {
        for (const dev of Networking.devices.values) {
            if (dev.type === DeviceType.Wifi)
                return dev;
        }
        return null;
    }

    readonly property var wiredDevice: {
        for (const dev of Networking.devices.values) {
            if (dev.type === DeviceType.Wired)
                return dev;
        }
        return null;
    }

    // Strongest first, with whatever is connected pinned to the top. The
    // underlying model is in NetworkManager's own order, which is neither.
    readonly property var networks: {
        if (!root.wifiDevice)
            return [];

        const out = [];
        for (const net of root.wifiDevice.networks.values)
            out.push(net);

        out.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        return out;
    }

    // The network whose passphrase is being asked for, or null. Non-null is
    // what makes the prompt appear.
    property var pendingNetwork: null
    property string pendingError: ""

    // Scanning runs only while the panel is open. A wifi scan is disruptive to
    // the radio — on a single-antenna card it briefly interrupts the
    // association it is scanning from — so it is not something to leave on for
    // a bar that is visible all day.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.active
        when: root.wifiDevice !== null
    }

    // Dismissing the panel abandons a half-typed passphrase. Deliberate: the
    // alternative is plaintext sitting in a TextInput for the rest of the
    // session, and the polkit card next door clears its field for the same
    // reason.
    onActiveChanged: {
        if (!root.active) {
            root.pendingNetwork = null;
            root.pendingError = "";
        }
    }

    function isOpen(net) {
        return net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe;
    }

    function isEnterprise(net) {
        return net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap || net.security === WifiSecurityType.Leap || net.security === WifiSecurityType.DynamicWep || net.security === WifiSecurityType.Wpa3SuiteB192;
    }

    // A join is one of three things depending on what NetworkManager already
    // knows: nothing to ask (open), a saved profile to reuse (`known`), or a
    // passphrase we have to collect.
    function activate(net) {
        if (net.connected) {
            net.disconnect();
            return;
        }

        if (net.known || root.isOpen(net)) {
            net.connect();
            return;
        }

        root.pendingError = "";
        root.pendingNetwork = net;
    }

    function describe(net) {
        if (net.stateChanging)
            return net.connected ? "disconnecting…" : "connecting…";
        if (net.connected)
            return "connected";
        if (root.isEnterprise(net))
            return "enterprise";
        // `signalStrength` is 0-1, NOT 0-100. Worth stating because the
        // obvious reference says otherwise: omarchy's `wifiIconFor` buckets it
        // by dividing by 20, because their number comes from `nmcli`, which
        // reports whole percent. Read raw, every network in range renders as
        // "1%".
        return Math.round(net.signalStrength * 100) + "%";
    }

    // Reports why an association failed, on the network we asked about. Wrong
    // passphrases arrive here as `NoSecrets` — NetworkManager does not say
    // "wrong password", it says it asked for secrets and did not get usable
    // ones, which for a PSK network means one thing.
    Connections {
        target: root.pendingNetwork

        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets)
                root.pendingError = "Wrong passphrase";
            else if (reason === ConnectionFailReason.WifiAuthTimeout)
                root.pendingError = "Authentication timed out";
            else
                root.pendingError = "Could not connect";
        }
    }

    // ---- wifi radio ----------------------------------------------------

    Item {
        width: parent.width
        implicitHeight: Theme.panelRowHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            text: {
                if (!Networking.wifiHardwareEnabled)
                    return "Wi-Fi blocked";
                return Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off";
            }
            color: Theme.panelForeground
            font.pixelSize: Theme.panelRowFontSize
            renderType: Text.NativeRendering
        }

        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            checked: Networking.wifiEnabled
            // `wifiHardwareEnabled` false is a hardware rfkill — a switch or
            // an Fn key. Software cannot clear it, so the toggle refuses
            // rather than appearing to work.
            interactive: Networking.wifiHardwareEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    // ---- wired ---------------------------------------------------------
    //
    // Shown only when a cable is actually in. A permanently empty "Wired"
    // section on a laptop that is docked once a month is noise.
    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.wiredDevice !== null && root.wiredDevice.hasLink

        PanelSectionHeader {
            text: "Wired"
        }

        PanelRow {
            label: root.wiredDevice ? root.wiredDevice.name : ""
            detail: {
                if (!root.wiredDevice)
                    return "";
                if (root.wiredDevice.state === ConnectionState.Connected)
                    return root.wiredDevice.address || "connected";
                return ConnectionState.toString(root.wiredDevice.state);
            }
            selected: root.wiredDevice && root.wiredDevice.state === ConnectionState.Connected
            onClicked: {
                if (root.wiredDevice && root.wiredDevice.state === ConnectionState.Connected)
                    root.wiredDevice.disconnect();
            }
        }
    }

    // ---- networks ------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: Networking.wifiEnabled

        PanelSectionHeader {
            text: "Networks"
            detail: root.networks.length === 0 ? "scanning…" : ""
        }

        Repeater {
            model: root.networks

            PanelRow {
                required property var modelData

                label: modelData.name || "(hidden)"
                detail: root.describe(modelData)
                selected: modelData.connected
                enabled: !modelData.stateChanging && !root.isEnterprise(modelData)
                onClicked: root.activate(modelData)
            }
        }
    }

    // ---- passphrase ----------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.pendingNetwork !== null

        PanelSectionHeader {
            text: root.pendingNetwork ? "Passphrase for " + root.pendingNetwork.name : ""
        }

        Rectangle {
            width: parent.width
            implicitHeight: Theme.panelFieldHeight
            radius: Theme.panelRowRadius
            color: Theme.panelFieldBackground

            TextInput {
                id: psk

                anchors.fill: parent
                anchors.leftMargin: Theme.panelPadding / 2
                anchors.rightMargin: Theme.panelPadding / 2

                verticalAlignment: TextInput.AlignVCenter
                color: Theme.panelForeground
                font.pixelSize: Theme.panelRowFontSize
                selectionColor: Theme.panelAccent
                selectedTextColor: Theme.nord0
                echoMode: TextInput.Password
                clip: true

                // Focus follows the prompt appearing, not the panel opening —
                // the panel is mostly used without ever reaching this field.
                Connections {
                    target: root

                    function onPendingNetworkChanged() {
                        psk.text = "";
                        if (root.pendingNetwork)
                            psk.forceActiveFocus();
                    }
                }

                onAccepted: root.pendingNetwork.connectWithPsk(psk.text)
            }
        }

        Text {
            width: parent.width
            text: root.pendingError
            visible: root.pendingError !== ""
            color: Theme.panelError
            font.pixelSize: Theme.panelSectionFontSize
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Row {
            anchors.right: parent.right
            spacing: Theme.panelRowSpacing * 2
            topPadding: Theme.panelRowSpacing

            Button {
                text: "Cancel"
                onActivated: root.pendingNetwork = null
            }

            Button {
                text: "Connect"
                primary: true
                interactive: psk.text.length > 0
                onActivated: root.pendingNetwork.connectWithPsk(psk.text)
            }
        }
    }
}
