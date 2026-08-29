import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Common

// waybar's `custom/dwt` — the disable-while-typing toggle (see CONTEXT.md:
// "DWT"). Reproduces the old shell script's contract exactly: text "DWT on" /
// "DWT off", nord14/nord11 foreground, click to flip, and the same tooltip
// wording.
//
// Why shell out to hyprctl instead of using the Hyprland module:
// `Hyprland.dispatch()` only runs *dispatchers*, and reading or writing a
// config option is `keyword`/`getoption`, not a dispatcher. Quickshell 0.3.1
// exposes no option accessor, so hyprctl stays the interface — the same one
// the `$mod T` bind in nix/home/hyprland.nix uses, which keeps the two paths
// impossible to drift apart.
//
// Unlike the waybar script this parses the JSON in QML, so the widget no
// longer needs jq on PATH. (jq stays installed: the `$mod T` bind still uses
// it.)
Item {
    id: root

    property bool dwtEnabled: false

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Process {
        id: readState

        command: ["hyprctl", "getoption", "input:touchpad:disable_while_typing", "-j"]
        stdout: StdioCollector {
            id: readOut
        }
        onExited: (code, status) => {
            if (code !== 0)
                return;
            try {
                // hyprctl returns {"int": 0|1, "set": true} for this option —
                // there is no `.bool` field. The old waybar script and the
                // $mod T bind both used `jq -r .bool`, which silently yielded
                // null/false and never toggled.
                root.dwtEnabled = JSON.parse(readOut.text).int === 1;
            } catch (e) {
                // A malformed or empty reply means Hyprland's IPC is not up
                // yet. Leave the last known value alone; the poll below will
                // pick the real one up.
            }
        }
    }

    Process {
        id: writeState

        // Refresh immediately rather than waiting up to a poll interval, so
        // the click feels instant.
        onExited: readState.running = true
    }

    // waybar polled this every 5s (`interval = 5`). Kept: hyprctl exposes no
    // change event for config options, and the value also moves under us when
    // the `$mod T` bind or a config reload fires.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: readState.running = true
    }

    Pill {
        id: pill

        Text {
            text: root.dwtEnabled ? "DWT on" : "DWT off"
            color: root.dwtEnabled ? Theme.nord14 : Theme.nord11
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: {
            writeState.command = ["hyprctl", "keyword", "input:touchpad:disable_while_typing", root.dwtEnabled ? "false" : "true"];
            writeState.running = true;
        }
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            text: root.dwtEnabled ? "Disable-while-typing ON (click to disable)" : "Disable-while-typing OFF (click to enable)"
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
