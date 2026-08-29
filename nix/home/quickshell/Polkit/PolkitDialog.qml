import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.Common

// The auth prompt surface: a scrim, and a card that exists only while an
// authentication flow does.
//
// This file owns the window; `PolkitCard` owns everything that needs a live
// flow. That split is the point — the card is created by a Loader gated on
// `flow !== null`, so nothing inside it has to null-guard, and there is
// exactly one place (here) that knows a flow can be absent.
//
// Keyboard focus is Exclusive while mapped, like the launcher — a password
// field that does not receive keystrokes is worse than no dialog at all. The
// "never grabs keyboard focus destructively" requirement is met by mapping,
// not by policy: an unmapped layer surface holds no focus, and this one is
// unmapped the instant `flow` goes null, which happens as soon as polkit
// finishes with the request either way.
PanelWindow {
    id: root

    // Null whenever no request is in progress.
    required property AuthFlow flow

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

    Loader {
        anchors.fill: parent
        active: root.flow !== null

        sourceComponent: PolkitCard {
            flow: root.flow
        }
    }
}
