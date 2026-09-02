import QtQuick
import Quickshell
import qs.Common

// One bar surface, for one monitor.
//
// A top layer-shell strip, 30px tall with a 5px top margin and 10px either
// side. The window itself is transparent, so only the module pills are painted.
//
// Order, left to right:
//   left    workspaces, window title
//   right   DWT, AI quota, bluetooth, audio, network, battery, clock, tray
//
// Two of those postdate the migration:
//
//   DndWidget      (issue 05) sits ahead of the right group and is invisible
//                  whenever DND is off, which is the resting state.
//   AiQuotaWidget  Claude quota, always visible once its collector returns a
//                  record.
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

        // Invisible unless DND is on — see DndWidget.
        DndWidget {}

        DwtWidget {}

        AiQuotaWidget {}

        BluetoothWidget {}

        AudioWidget {}

        NetworkWidget {}

        BatteryWidget {}

        ClockWidget {}

        TrayWidget {}
    }
}
