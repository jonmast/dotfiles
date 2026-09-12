pragma Singleton

import Quickshell
import Quickshell.Io

// Reports a runtime contract failure in an external CLI as a desktop
// notification plus a journal line — the gap `hyprland-config` in flake.nix
// cannot cover. The Shell owns org.freedesktop.Notifications, so notify-send
// lands in our own banners.
Singleton {
    id: root

    // id -> alerted. Per-process, so a polling caller fires at most once.
    property var alerted: ({})

    Process {
        id: send
    }

    function fail(id, summary, body) {
        console.warn("boundary failure [" + id + "]: " + summary + " — " + body);
        if (root.alerted[id])
            return;
        root.alerted[id] = true;
        send.command = ["notify-send", "--app-name=The Shell",
                        "--urgency=critical", "--expire-time=0", summary, body];
        send.running = true;
    }
}
