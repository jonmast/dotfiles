import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Common

// waybar's `custom/dwt`: the disable-while-typing toggle (CONTEXT.md: "DWT").
// Text "DWT on"/"DWT off", nord14/nord11, click to flip.
//
// hyprctl is the only option interface QML has (Quickshell 0.3.1 exposes no
// Hyprland option accessor). Reads accept `bool` or `int` because hyprctl's
// JSON shape has changed across versions; writes use `eval`, because `keyword`
// is rejected under `configType = "lua"`.
Item {
    id: root

    property bool dwtEnabled: false
    // Set by an unrecognized read shape; cleared by the next good read.
    property bool broken: false

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

            // Malformed/empty reply means IPC is not up yet; not a failure.
            let opt;
            try {
                opt = JSON.parse(readOut.text);
            } catch (e) {
                return;
            }

            // Well-formed object with neither shape is a changed contract.
            if (typeof opt.bool === "boolean") {
                root.dwtEnabled = opt.bool;
                root.broken = false;
            } else if (typeof opt.int === "number") {
                root.dwtEnabled = opt.int === 1;
                root.broken = false;
            } else {
                root.broken = true;
                BoundaryAlert.fail("dwt-read", "DWT toggle may be broken",
                    "hyprctl getoption returned an unrecognized value for input:touchpad:disable_while_typing.");
            }
        }
    }

    Process {
        id: writeState

        // Refresh immediately so the click feels instant.
        onExited: (code, status) => {
            if (code !== 0)
                BoundaryAlert.fail("dwt-write", "DWT toggle failed",
                    "hyprctl eval was rejected; disable-while-typing was not changed.");
            readState.running = true;
        }
    }

    // hyprctl has no change event, and the value also moves under us when the
    // `$mod T` bind or a config reload fires.
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
            text: root.broken ? "DWT ?" : (root.dwtEnabled ? "DWT on" : "DWT off")
            color: root.broken ? Theme.nord11 : (root.dwtEnabled ? Theme.nord14 : Theme.nord11)
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: {
            writeState.command = ["hyprctl", "eval",
                "hl.config({input={touchpad={disable_while_typing=" + (root.dwtEnabled ? "false" : "true") + "}}})"];
            writeState.running = true;
        }
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            text: root.broken
                ? "Disable-while-typing state unknown (click to try toggling)"
                : (root.dwtEnabled ? "Disable-while-typing ON (click to disable)" : "Disable-while-typing OFF (click to enable)")
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
