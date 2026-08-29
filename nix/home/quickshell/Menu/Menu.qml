import Quickshell
import Quickshell.Io

// The launcher menu, and the reason walker no longer launches anything
// (CONTEXT.md, "Walker stack"). `$mod D` opens this; walker keeps clipboard
// history and nothing else.
//
// Opened over Quickshell's IPC socket rather than a Hyprland global shortcut:
//
//   bind = $mainMod, D, exec, qs -c shell ipc call menu toggle
//
// The keybind pays one ~35ms `qs` round trip, measured, which is well under
// what a launcher's first frame costs anyway. A GlobalShortcut would save that
// spawn, but the shortcuts protocol refuses duplicate appid+name pairs and
// CRASHES whichever client registers second — which is exactly what running a
// second shell instance against the live session (`quickshell -p
// ./nix/home/quickshell`) does, and that side-by-side run is how this shell is
// developed and diffed. Omarchy, the reference implementation, also drives its
// menu over `qs ipc call` and registers no global shortcuts at all.
//
// Open/close state lives here rather than in the panel so the IPC surface
// stays readable: three functions that set one boolean.
Scope {
    id: root

    property bool opened: false

    IpcHandler {
        target: "menu"

        // Return values are what `qs ipc call` prints, so they double as the
        // answer to "did that do anything" when poking at the shell by hand.
        function toggle(): string {
            root.opened = !root.opened;
            return root.opened ? "opened" : "closed";
        }

        function open(): string {
            root.opened = true;
            return "opened";
        }

        function close(): string {
            root.opened = false;
            return "closed";
        }
    }

    MenuPanel {
        opened: root.opened

        // The panel dismisses itself (ESC, click-off, a launch) by asking,
        // not by writing to its own `opened` — which would be overwritten by
        // the binding above the moment anything else touched the state.
        onDismissed: root.opened = false
    }
}
