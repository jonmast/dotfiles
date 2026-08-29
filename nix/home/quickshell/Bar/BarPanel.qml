import QtQuick
import Quickshell
import qs.Common

// One bar surface, for one monitor.
//
// Geometry is waybar's verbatim: `layer: top`, `position: top`, `height: 30`,
// `margin-top: 5`, `margin-left/right: 10`, with a transparent window so only
// the module pills are painted (waybar's `window#waybar { background:
// transparent }`).
//
// Module order is likewise waybar's:
//   modules-left   hyprland/workspaces, hyprland/window
//   modules-right  custom/dwt, bluetooth, pulseaudio, network, battery,
//                  clock, tray
//
// Issue 05 added one module waybar never had, DndWidget, ahead of the right
// group. It is invisible whenever DND is off, which is the resting state, so
// the parity contract still holds for the bar you actually look at.
PanelWindow {
    id: root

    required property var modelData

    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: Theme.barMarginTop
        left: Theme.barMarginSide
        right: Theme.barMarginSide
    }

    implicitHeight: Theme.barHeight
    color: "transparent"
    // exclusionMode is left at its default (Auto), which reserves the bar's
    // height plus its margin, so tiled windows start below the bar exactly as
    // they did under waybar.

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing

        Workspaces {
            screen: root.modelData
        }

        WindowTitle {
            // Leave room for the right-hand modules before eliding. The
            // divisor is a guess at the worst case, not a measurement — the
            // right group is only laid out after this is bound, so reading its
            // width here would be a binding loop.
            maximumWidth: Math.max(120, root.width / 2)
        }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.pillSpacing

        // Not a waybar module. Invisible unless DND is on, so the resting bar
        // is still parity — see DndWidget.
        DndWidget {}

        DwtWidget {}

        BluetoothWidget {}

        AudioWidget {}

        NetworkWidget {}

        BatteryWidget {}

        ClockWidget {}

        TrayWidget {}
    }
}
