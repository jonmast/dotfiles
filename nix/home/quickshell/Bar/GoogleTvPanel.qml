import QtQuick
import Quickshell
import qs.Common

// The TV pill's click-through panel: a remote.
//
// Header row is the power switch — a Toggle rather than a button for the
// reason the bluetooth panel gives: the thing has a state you want to read at
// a glance. It reflects `GoogleTv.powered`, which the TV pushes to us, so it
// moves on its own when the TV is switched from the physical remote.
//
// Under that, the remote proper: a d-pad, Back/Home, volume. Every button is
// one `GoogleTv.key(...)`; the names are RemoteKeyCode entries from the
// protocol's remotemessage.proto, minus the `KEYCODE_` prefix the library
// strips for us.
//
// Below the remote, and only when relevant, the setup flow: an address field
// while unconfigured or unreachable, a Pair button while unpaired, and a PIN
// field while the TV is showing a code. Setup lives here rather than in a
// config file because pairing is inherently interactive — the TV puts six
// digits on the screen and waits.
Column {
    id: root

    spacing: Theme.panelSpacing

    readonly property bool live: GoogleTv.connected
    readonly property bool needsHost: GoogleTv.status === "unconfigured" || GoogleTv.status === "unreachable"
    readonly property bool needsPair: GoogleTv.status === "unpaired"
    readonly property bool needsPin: GoogleTv.status === "pairing"

    // Square keys for the d-pad so the grid is a grid; the rest take the
    // width their label needs, like every other Button in the shell.
    readonly property int padKey: Theme.panelRowHeight

    // This panel sizes the card, rather than being sized by it. Every other
    // panel holds names of unknown length — sink descriptions, SSIDs — so a
    // fixed width with elision is the only sane answer there. A remote is
    // buttons whose widths are known, so the card can hug them, and the side
    // gap ends up the same Theme.panelPadding as the top and bottom.
    //
    // Measured off the widest ROW rather than published as implicitWidth: a
    // Column's implicitWidth is read-only and comes from its children, and
    // the setup sections stretch to `parent.width`, so that number is both
    // unwritable and circular. Hence a property of our own.
    //
    // The header is in the list because it is visible in every state, remote
    // or not, and its summary text ("unreachable — retrying") is the longest
    // string the panel ever shows.
    readonly property int contentWidth: Math.max(padGrid.implicitWidth, navRow.implicitWidth, volumeRow.implicitWidth, headerText.implicitWidth + powerToggle.implicitWidth + Theme.panelSpacing)

    // The keyboard drives the d-pad, because reaching for the mouse to press
    // ▼ four times is the whole reason a physical remote is annoying. Popout
    // forwards keys here while nothing inside the panel has focus, so the
    // address and PIN fields keep their own arrow keys. ESC is deliberately
    // left alone — unhandled, it goes back to the Popout and closes it.
    //
    // A text field that has taken focus does not give it back on its own, so
    // once setup is done the d-pad would be dead until the panel was
    // reopened. Taking focus here revives it: this handler then fires
    // directly rather than by forwarding.
    onLiveChanged: if (root.live && !root.needsPin)
        root.forceActiveFocus()
    Keys.onPressed: event => {
        if (!root.live || !GoogleTv.isOn)
            return;
        switch (event.key) {
        case Qt.Key_Up:
            GoogleTv.key("DPAD_UP");
            break;
        case Qt.Key_Down:
            GoogleTv.key("DPAD_DOWN");
            break;
        case Qt.Key_Left:
            GoogleTv.key("DPAD_LEFT");
            break;
        case Qt.Key_Right:
            GoogleTv.key("DPAD_RIGHT");
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            GoogleTv.key("DPAD_CENTER");
            break;
        case Qt.Key_Backspace:
            GoogleTv.key("BACK");
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ---- power -----------------------------------------------------------

    Item {
        width: parent.width
        implicitHeight: Theme.panelRowHeight

        Column {
            id: headerText

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: "Google TV"
                color: Theme.panelForeground
                font.pixelSize: Theme.panelRowFontSize
                renderType: Text.NativeRendering
            }

            Text {
                text: GoogleTv.summary
                color: Theme.panelForeground
                opacity: Theme.panelMetaOpacity
                font.pixelSize: Theme.panelSectionFontSize
                renderType: Text.NativeRendering
            }
        }

        Toggle {
            id: powerToggle

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            checked: GoogleTv.isOn
            busy: GoogleTv.status === "connecting" || GoogleTv.status === "reconnecting"
            interactive: root.live
            onToggled: GoogleTv.key("POWER")
        }
    }

    // ---- remote ----------------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelSpacing
        visible: root.live
        // A TV in standby still accepts keys (that is how POWER wakes it),
        // but a d-pad for a dark screen is noise, so it dims rather than
        // disappears.
        opacity: GoogleTv.isOn ? 1 : 0.5

        Grid {
            id: padGrid

            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            spacing: Theme.panelRowSpacing * 2

            Item {
                width: root.padKey
                height: root.padKey
            }

            Button {
                width: root.padKey
                height: root.padKey
                text: "▲"
                onActivated: GoogleTv.key("DPAD_UP")
            }

            Item {
                width: root.padKey
                height: root.padKey
            }

            Button {
                width: root.padKey
                height: root.padKey
                text: "◀"
                onActivated: GoogleTv.key("DPAD_LEFT")
            }

            Button {
                width: root.padKey
                height: root.padKey
                text: "OK"
                primary: true
                onActivated: GoogleTv.key("DPAD_CENTER")
            }

            Button {
                width: root.padKey
                height: root.padKey
                text: "▶"
                onActivated: GoogleTv.key("DPAD_RIGHT")
            }

            Item {
                width: root.padKey
                height: root.padKey
            }

            Button {
                width: root.padKey
                height: root.padKey
                text: "▼"
                onActivated: GoogleTv.key("DPAD_DOWN")
            }

            Item {
                width: root.padKey
                height: root.padKey
            }
        }

        Row {
            id: navRow

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.panelRowSpacing * 2

            Button {
                text: "Back"
                onActivated: GoogleTv.key("BACK")
            }

            Button {
                text: "Home"
                onActivated: GoogleTv.key("HOME")
            }
        }

        Row {
            id: volumeRow

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.panelRowSpacing * 2

            Button {
                text: "Vol −"
                onActivated: GoogleTv.key("VOLUME_DOWN")
            }

            Button {
                text: GoogleTv.volume && GoogleTv.volume.muted ? "Unmute" : "Mute"
                onActivated: GoogleTv.key("VOLUME_MUTE")
            }

            Button {
                text: "Vol +"
                onActivated: GoogleTv.key("VOLUME_UP")
            }
        }
    }

    // ---- setup: address --------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.needsHost

        PanelSectionHeader {
            text: "TV address"
            detail: GoogleTv.status === "unreachable" ? "retrying…" : ""
        }

        Rectangle {
            width: parent.width
            implicitHeight: Theme.panelFieldHeight
            radius: Theme.panelRowRadius
            color: Theme.panelFieldBackground

            TextInput {
                id: hostField

                anchors.fill: parent
                anchors.leftMargin: Theme.panelPadding / 2
                anchors.rightMargin: Theme.panelPadding / 2

                verticalAlignment: TextInput.AlignVCenter
                color: Theme.panelForeground
                font.pixelSize: Theme.panelRowFontSize
                selectionColor: Theme.panelAccent
                selectedTextColor: Theme.nord0
                clip: true
                text: GoogleTv.host

                // Focus follows the field appearing, as the PIN field and the
                // network panel's passphrase do: the address prompt only
                // shows when there is nothing else useful to do here.
                Connections {
                    target: root

                    function onNeedsHostChanged() {
                        if (root.needsHost)
                            hostField.forceActiveFocus();
                    }
                }

                Component.onCompleted: if (root.needsHost)
                    hostField.forceActiveFocus()

                onAccepted: GoogleTv.setHost(hostField.text.trim())
            }

            // Click-to-focus, spelled out. TextInput.activeFocusOnPress does
            // nothing on these layer-shell surfaces — every text field in this
            // shell is focused by an explicit forceActiveFocus — so without
            // this, clicking the field puts a cursor in it that swallows no
            // keystrokes.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    hostField.forceActiveFocus();
                    mouse.accepted = false;
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Theme.panelRowSpacing * 2
            topPadding: Theme.panelRowSpacing

            Button {
                text: "Retry"
                visible: GoogleTv.status === "unreachable"
                onActivated: GoogleTv.retry()
            }

            Button {
                text: "Connect"
                primary: true
                interactive: hostField.text.trim().length > 0
                onActivated: GoogleTv.setHost(hostField.text.trim())
            }
        }
    }

    // ---- setup: pairing --------------------------------------------------

    Column {
        width: parent.width
        spacing: Theme.panelRowSpacing
        visible: root.needsPair || root.needsPin

        PanelSectionHeader {
            text: root.needsPin ? "Pairing code" : "Pairing"
            detail: root.needsPin ? "shown on the TV" : ""
        }

        Text {
            width: parent.width
            visible: root.needsPair
            text: "The TV has to approve this machine once. Pairing puts a six-digit code on the screen."
            color: Theme.panelForeground
            opacity: Theme.panelMetaOpacity
            font.pixelSize: Theme.panelSectionFontSize
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Rectangle {
            width: parent.width
            implicitHeight: Theme.panelFieldHeight
            radius: Theme.panelRowRadius
            color: Theme.panelFieldBackground
            visible: root.needsPin

            TextInput {
                id: pinField

                anchors.fill: parent
                anchors.leftMargin: Theme.panelPadding / 2
                anchors.rightMargin: Theme.panelPadding / 2

                verticalAlignment: TextInput.AlignVCenter
                color: Theme.panelForeground
                font.pixelSize: Theme.panelRowFontSize
                font.family: Theme.monoFamily
                selectionColor: Theme.panelAccent
                selectedTextColor: Theme.nord0
                clip: true
                maximumLength: 6
                inputMethodHints: Qt.ImhUppercaseOnly | Qt.ImhNoPredictiveText

                // Focus follows the prompt appearing, as in the network
                // panel's passphrase field.
                Connections {
                    target: root

                    function onNeedsPinChanged() {
                        pinField.text = "";
                        if (root.needsPin)
                            pinField.forceActiveFocus();
                    }
                }

                onAccepted: GoogleTv.finishPairing(pinField.text.trim().toUpperCase())
            }

            // See the address field: click-to-focus has to be explicit.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.IBeamCursor
                onPressed: mouse => {
                    pinField.forceActiveFocus();
                    mouse.accepted = false;
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Theme.panelRowSpacing * 2
            topPadding: Theme.panelRowSpacing

            Button {
                text: "Pair"
                primary: true
                visible: root.needsPair
                onActivated: GoogleTv.pair()
            }

            Button {
                text: "Confirm"
                primary: true
                visible: root.needsPin
                interactive: pinField.text.trim().length === 6
                onActivated: GoogleTv.finishPairing(pinField.text.trim().toUpperCase())
            }
        }
    }

    // ---- error -----------------------------------------------------------

    Text {
        width: parent.width
        text: GoogleTv.error
        visible: GoogleTv.error !== ""
        color: Theme.panelError
        font.pixelSize: Theme.panelSectionFontSize
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
    }
}
