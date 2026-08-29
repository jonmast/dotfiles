import QtQuick
import Quickshell.Hyprland
import qs.Common

// waybar's `hyprland/window` (default format `{title}`).
//
// Two deliberate deviations from waybar, both documented rather than silent:
//
//  1. waybar drew the pill even with an empty label, leaving a stub of
//     padding floating next to the workspaces whenever nothing was focused.
//     Here the pill collapses instead.
//  2. waybar let the title grow without bound and happily ran it under the
//     right-hand modules. Here it elides at `maximumWidth`.
Pill {
    id: root

    property int maximumWidth: 600

    // `Hyprland.activeToplevel` is not seeded at startup: Quickshell populates
    // it from `activewindow` IPC *events*, and the initial state query it runs
    // on connect (j/monitors, j/workspaces, j/clients) does not include one.
    // So it reads null — and every toplevel reads `activated: false` — until
    // the user first changes focus. Measured on 0.3.1 against a live session:
    // null through two poll ticks, correct from the first focus change onward.
    //
    // That null window is exactly "just logged in and looking at the bar", so
    // it needs a fallback. `j/clients` does carry focus information, as
    // `focusHistoryID`, where 0 is the focused window — and that IS seeded on
    // connect. Use it until the event-driven property comes alive, then defer
    // to it.
    readonly property string title: {
        if (Hyprland.activeToplevel)
            return Hyprland.activeToplevel.title;

        for (const toplevel of Hyprland.toplevels.values) {
            const ipc = toplevel.lastIpcObject;
            if (ipc && ipc.focusHistoryID === 0)
                return toplevel.title;
        }

        return "";
    }

    visible: title.length > 0

    Text {
        text: root.title
        color: Theme.foreground
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.maximumWidth)
    }
}
