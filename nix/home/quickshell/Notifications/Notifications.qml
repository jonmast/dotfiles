import Quickshell
import Quickshell.Io

// The notifications plugin, and the reason mako is gone (issue 05).
//
// This file is only the surfaces and the IPC handle. The daemon itself —
// the bus name, the tracked set, DND, the history — is NotificationService,
// a singleton, because the Bar's DND indicator needs to read the same state
// and QML's implicit directory import does not reach across directories.
//
// Driven over the IPC socket rather than a Hyprland GlobalShortcut, for the
// reason recorded in Menu.qml: the shortcuts protocol refuses duplicate
// appid+name pairs and CRASHES the second registrant, which is exactly the
// side-by-side dev instance this shell is developed with.
//
//   bind = $mainMod, N, exec, qs -c shell ipc call notifications toggleHistory
//   bind = $mainMod SHIFT, N, exec, qs -c shell ipc call notifications toggleDnd
Scope {
    id: root

    property bool historyOpened: false

    IpcHandler {
        target: "notifications"

        // Return values are what `qs ipc call` prints, so each of these
        // doubles as the answer to "what state is it in now" when poking at
        // the shell by hand.
        function toggleHistory(): string {
            root.historyOpened = !root.historyOpened;
            return root.historyOpened ? "opened" : "closed";
        }

        function toggleDnd(): string {
            return NotificationService.toggleDnd() ? "dnd on" : "dnd off";
        }

        function dnd(): string {
            return NotificationService.dnd ? "dnd on" : "dnd off";
        }

        // Clears the banners on screen without touching the history, for the
        // case of a burst arriving mid-sentence.
        function dismissAll(): string {
            NotificationService.dismissAllBanners();
            return "dismissed";
        }

        function clearHistory(): string {
            NotificationService.clearHistory();
            return "cleared";
        }
    }

    NotificationBanners {}

    NotificationHistory {
        opened: root.historyOpened

        // The panel asks to be closed rather than writing its own `opened`,
        // which the binding above would overwrite on the next state change.
        onDismissed: root.historyOpened = false
    }
}
