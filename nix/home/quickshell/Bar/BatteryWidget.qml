import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common

// waybar's `battery` module, configured as:
//   format           "{icon} {capacity}%"
//   format-charging  "⚡ {capacity}%"
//   format-icons     [🪫, 🔋, 🔋]
//   states           warning 30, critical 15
// with `.full`/`.charging` green, `.warning` yellow, `.critical` red.
//
// Colour precedence is CSS source order, not severity: the stylesheet listed
// full/charging, then warning, then critical, and equal-specificity rules let
// the later one win. So a battery charging at 10% was red, not green. The
// ordering below is written to match that, in reverse.
Item {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property int capacity: device ? Math.round(device.percentage) : 0
    readonly property bool charging: device ? device.state === UPowerDeviceState.Charging : false
    readonly property bool full: device ? device.state === UPowerDeviceState.FullyCharged : false

    readonly property var icons: ["🪫", "🔋", "🔋"]

    // Only render on hosts that actually have a battery, like waybar did.
    visible: device !== null && device.isLaptopBattery

    implicitWidth: visible ? pill.implicitWidth : 0
    implicitHeight: pill.implicitHeight

    Pill {
        id: pill

        Text {
            text: {
                if (root.charging)
                    return "⚡ " + root.capacity + "%";
                const idx = Math.min(Math.floor(root.capacity / (100 / root.icons.length)), root.icons.length - 1);
                return root.icons[idx] + " " + root.capacity + "%";
            }
            color: {
                if (root.capacity <= 15)
                    return Theme.nord11;
                if (root.capacity <= 30)
                    return Theme.nord13;
                if (root.charging || root.full)
                    return Theme.nord14;
                return Theme.foreground;
            }
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }
}
