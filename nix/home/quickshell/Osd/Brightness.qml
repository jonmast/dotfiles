pragma Singleton

import Quickshell
import Quickshell.Io
import qs.Common

// Backlight level, read through `brightnessctl` (issue 05).
//
// Quickshell 0.3.1 has no backlight service, so this is a shell-out — the
// same shape of decision as the Bar's DWT widget, and for the same reason:
// the `XF86MonBrightness*` binds in nix/home/hyprland.nix already drive
// `brightnessctl set`, so reading through the identical tool makes the two
// paths impossible to drift apart. It also keeps device discovery in
// brightnessctl rather than hardcoding a device name here.
//
// Reading sysfs directly with a FileView was the alternative and is a trap on
// this machine: amdgpu exposes both `brightness` and `actual_brightness`, and
// they disagree — 19661 vs 6682 at the same moment — because the driver
// applies a perceptual curve. `brightness` is what brightnessctl writes and
// reports a percentage of, so anything reading `actual_brightness` would show
// a number that does not match the key you just pressed. Using brightnessctl
// sidesteps the choice entirely.
//
// Polled only on demand — there is no change event for a backlight worth
// having (sysfs does not deliver reliable inotify), and a timer polling a
// value that changes only when a key is pressed is a process spawn per tick
// forever.
Singleton {
    id: root

    property int percent: 0
    // False until the first successful read, so the OSD can decline to draw a
    // bar at 0% that only means "we have not looked yet".
    property bool available: false

    function refresh() {
        read.running = true;
    }

    Process {
        id: read

        // `-m` is machine-readable: device,class,current,percent,max — e.g.
        // `amdgpu_bl1,backlight,19661,30%,65535`.
        //
        // `-c backlight` is not optional. Without it brightnessctl enumerates
        // the `leds` class too, and on this machine that means it tries to
        // read `chromeos:white:power` and `chromeos:multicolor:charging` and
        // fails on both — noise on stderr, and a real risk of a keyboard or
        // status LED turning up on stdout ahead of the panel on some other
        // machine. The class filter makes "which device" unambiguous rather
        // than relying on output order.
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            id: output
        }

        onExited: code => {
            if (code !== 0)
                return;

            const text = output.text.trim();

            // Empty output = no backlight device, not a failure.
            if (text === "")
                return;

            // Defense in depth: only accept an actual backlight line.
            for (const line of text.split("\n")) {
                const fields = line.split(",");
                if (fields.length < 4 || fields[1] !== "backlight")
                    continue;

                const parsed = parseInt(fields[3].replace("%", ""), 10);
                if (isNaN(parsed))
                    continue;

                root.percent = parsed;
                root.available = true;
                return;
            }

            // Exit 0 with output but nothing recognized: brightnessctl's `-m`
            // contract changed.
            root.available = false;
            BoundaryAlert.fail("brightnessctl", "Brightness OSD may be broken",
                "brightnessctl -m output was not recognized; the OSD cannot read the backlight.");
        }
    }
}
