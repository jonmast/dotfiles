import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common

// The auth prompt surface: a scrim and a centred card, mapped only while an
// authentication flow is live.
//
// Keyboard focus is Exclusive while mapped, like the launcher — a password
// field that does not receive keystrokes is worse than no dialog at all. The
// "never grabs keyboard focus destructively" requirement is met by mapping,
// not by policy: an unmapped layer surface holds no focus, and this one is
// unmapped the instant `flow` goes null, which happens as soon as polkit
// finishes with the request either way.
PanelWindow {
    id: root

    // AuthFlow, or null when nothing is being authenticated.
    required property var flow

    visible: root.flow !== null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.namespace: "the-shell-polkit"
    // Overlay: a privilege prompt raised from a fullscreen window has to be
    // visible, and it is always the direct consequence of something the user
    // just did.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // A response is only wanted while PAM is actually asking for one. Between
    // stages (and during a fingerprint stage, which asks for a finger rather
    // than a string) the field is hidden and the card is just a message.
    readonly property bool wantsResponse: root.flow !== null && root.flow.isResponseRequired

    function submit() {
        if (!root.wantsResponse)
            return;

        root.flow.submit(response.text);
        // Cleared immediately, not on the next prompt: the plaintext should
        // not outlive the call that consumed it, and PAM's answer arrives
        // asynchronously.
        response.text = "";
    }

    function cancel() {
        if (root.flow !== null)
            root.flow.cancelAuthenticationRequest();
    }

    onVisibleChanged: {
        if (root.visible)
            response.forceActiveFocus();
        else
            response.text = "";
    }

    // Each new prompt is a new question — a wrong password left in the box
    // would otherwise be submitted verbatim against the retry.
    Connections {
        target: root.flow
        enabled: root.flow !== null

        function onInputPromptChanged() {
            response.text = "";
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.polkitScrim

        // No click-off-to-dismiss here, unlike the launcher. Cancelling an
        // auth request is a decision; a stray click on the desktop behind the
        // card is not. ESC and the Cancel button are the ways out.
        MouseArea {
            anchors.fill: parent
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
                    source: Quickshell.iconPath(root.flow ? root.flow.iconName : "", "dialog-password")
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
                        text: root.flow ? root.flow.message : ""
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
                visible: root.flow !== null && root.flow.inputPrompt !== ""
                text: root.flow ? root.flow.inputPrompt : ""
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
                    echoMode: (root.flow && root.flow.responseVisible) ? TextInput.Normal : TextInput.Password

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.cancel();
                            event.accepted = true;
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.submit();
                            event.accepted = true;
                            break;
                        }
                    }
                }
            }

            // Errors ("Authentication failure") and info alike; polkit says
            // which through `supplementaryIsError`.
            Text {
                width: parent.width
                visible: root.flow !== null && root.flow.supplementaryMessage !== ""
                text: root.flow ? root.flow.supplementaryMessage : ""
                color: (root.flow && root.flow.supplementaryIsError) ? Theme.polkitError : Theme.polkitForeground
                opacity: (root.flow && root.flow.supplementaryIsError) ? 1 : Theme.polkitMetaOpacity
                font.pixelSize: Theme.polkitBodyFontSize
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.polkitPadding / 2

                PolkitButton {
                    text: "Cancel"
                    onActivated: root.cancel()
                }

                PolkitButton {
                    text: "Authenticate"
                    primary: true
                    enabled: root.wantsResponse
                    onActivated: root.submit()
                }
            }
        }
    }

    // ESC has to work even when the field is hidden (a fingerprint stage takes
    // no keyboard input at all), so the shortcut lives on the window rather
    // than only in the TextInput's key handler.
    Shortcut {
        sequences: [StandardKey.Cancel]
        enabled: root.visible && !root.wantsResponse
        onActivated: root.cancel()
    }
}
