import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Polkit
import qs.Common

// The card itself: what polkit is asking, the response field, and the two
// buttons.
//
// Created by `PolkitDialog`'s Loader only while a flow exists and destroyed
// when it ends, so `flow` is non-null for this component's entire lifetime and
// nothing below guards it. The same lifetime is why there is no "clear the
// field when the dialog closes" code — the field goes away with the card, and
// with it the plaintext.
Item {
    id: root

    required property AuthFlow flow

    // A response is only wanted while PAM is actually asking for one. Between
    // stages (and during a fingerprint stage, which asks for a finger rather
    // than a string) the field is hidden and the card is just a message.
    readonly property bool wantsResponse: root.flow.isResponseRequired

    function submit() {
        if (!root.wantsResponse)
            return;

        root.flow.submit(response.text);
        // Cleared immediately, not on the next prompt: the plaintext should
        // not outlive the call that consumed it, and PAM's answer arrives
        // asynchronously.
        response.text = "";
    }

    // ESC lives here and nowhere else. Putting it in the field's key handler
    // instead would lose it exactly when it is most needed — during a
    // fingerprint stage there is no field to receive the key.
    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.flow.cancelAuthenticationRequest()
    }

    // Each new prompt is a new question — a wrong password left in the box
    // would otherwise be submitted verbatim against the retry.
    Connections {
        target: root.flow

        function onInputPromptChanged() {
            response.text = "";
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * Theme.polkitTopFraction)

        width: Math.min(Theme.polkitWidth, root.width - Theme.polkitPadding * 2)
        implicitHeight: content.implicitHeight + Theme.polkitPadding * 2

        radius: Theme.polkitRadius
        color: Theme.polkitBackground
        border.width: 1
        border.color: Theme.polkitBorder

        Column {
            id: content

            anchors.fill: parent
            anchors.margins: Theme.polkitPadding
            spacing: Theme.polkitPadding

            Row {
                width: parent.width
                spacing: Theme.polkitPadding

                IconImage {
                    id: icon

                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Theme.polkitIconSize
                    // polkit actions name an icon far less often than desktop
                    // entries do, so the fallback is the common case rather
                    // than the exception.
                    source: Quickshell.iconPath(root.flow.iconName, "dialog-password")
                }

                Column {
                    width: parent.width - icon.width - Theme.polkitPadding
                    spacing: Theme.notifLineSpacing

                    Text {
                        width: parent.width
                        text: "Authentication required"
                        color: Theme.polkitForeground
                        font.pixelSize: Theme.polkitTitleFontSize
                        elide: Text.ElideRight
                    }

                    // polkit's own description of the action ("Authentication
                    // is required to run a program as another user"). Shown
                    // verbatim: rewording it would be lying about what is
                    // being authorised.
                    Text {
                        width: parent.width
                        text: root.flow.message
                        color: Theme.polkitForeground
                        opacity: Theme.polkitMetaOpacity
                        font.pixelSize: Theme.polkitBodyFontSize
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // PAM's prompt — "Password:", "Place your finger on the reader",
            // whatever the polkit-1 stack is asking for at this stage. Since
            // fprintAuth is on for polkit-1, this is the line that tells the
            // two apart, so it is shown rather than replaced with a fixed
            // "Password" label.
            Text {
                width: parent.width
                visible: root.flow.inputPrompt !== ""
                text: root.flow.inputPrompt
                color: Theme.polkitForeground
                font.pixelSize: Theme.polkitBodyFontSize
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: Theme.polkitFieldHeight
                visible: root.wantsResponse
                radius: Theme.menuRowRadius
                color: Theme.polkitFieldBackground
                border.width: 1
                border.color: response.activeFocus ? Theme.polkitAccent : Theme.polkitBorder

                TextInput {
                    id: response

                    anchors.fill: parent
                    anchors.leftMargin: Theme.polkitPadding / 2
                    anchors.rightMargin: Theme.polkitPadding / 2

                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.polkitForeground
                    font.pixelSize: Theme.polkitBodyFontSize
                    selectionColor: Theme.polkitAccent
                    selectedTextColor: Theme.nord0
                    clip: true
                    focus: true
                    // `responseVisible` is polkit's own answer to "is this a
                    // secret" — false for passwords. Not assumed here, because
                    // some stages legitimately want an echoed answer.
                    echoMode: root.flow.responseVisible ? TextInput.Normal : TextInput.Password

                    Component.onCompleted: response.forceActiveFocus()

                    onAccepted: root.submit()
                }
            }

            // Errors ("Authentication failure") and info alike; polkit says
            // which through `supplementaryIsError`.
            Text {
                width: parent.width
                visible: root.flow.supplementaryMessage !== ""
                text: root.flow.supplementaryMessage
                color: root.flow.supplementaryIsError ? Theme.polkitError : Theme.polkitForeground
                opacity: root.flow.supplementaryIsError ? 1 : Theme.polkitMetaOpacity
                font.pixelSize: Theme.polkitBodyFontSize
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.polkitPadding / 2

                Button {
                    text: "Cancel"
                    onActivated: root.flow.cancelAuthenticationRequest()
                }

                Button {
                    text: "Authenticate"
                    primary: true
                    interactive: root.wantsResponse
                    onActivated: root.submit()
                }
            }
        }
    }
}
