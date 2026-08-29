import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Common

// waybar's `network` module. It carried no config block at all, so it ran on
// waybar's default `format` of `{ifname}` — the bar showed a raw interface
// name like `wlp1s0`, with `.disconnected` styled red.
//
// One deviation: waybar's default disconnected label is still `{ifname}` of
// whichever interface it latched onto, which is indistinguishable from the
// connected label apart from colour. This shows the word "disconnected"
// instead. Everything else, including the deliberately unhelpful interface
// name, is kept — a friendlier label belongs to the retheme, not the
// migration.
Item {
    id: root

    // Which interface waybar would have named: the one carrying the default
    // route. Wired wins when both are up, matching NetworkManager's default
    // route metrics on this host.
    readonly property var activeDevice: {
        let wifi = null;
        for (const dev of Networking.devices.values) {
            if (dev.state !== ConnectionState.Connected)
                continue;
            if (dev.type === DeviceType.Wired)
                return dev;
            if (dev.type === DeviceType.Wifi && !wifi)
                wifi = dev;
        }
        return wifi;
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    Pill {
        id: pill

        Text {
            text: root.activeDevice ? root.activeDevice.name : "disconnected"
            color: root.activeDevice ? Theme.foreground : Theme.nord11
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hover
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            text: {
                if (!root.activeDevice)
                    return "No network connection";
                const dev = root.activeDevice;
                const lines = [dev.name];
                if (dev.address)
                    lines.push(dev.address);
                for (const net of dev.networks.values) {
                    if (net.connected) {
                        lines.push(net.name);
                        break;
                    }
                }
                return lines.join("\n");
            }
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
