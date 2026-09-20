import QtQuick
import Quickshell
import qs.Common

// The Google TV pill: "TV", coloured by what the bridge knows.
//
//   nord14   connected and the TV set is on
//   fg       connected, set in standby (or streamer awake behind a dark set)
//   nord13   pairing / connecting / reconnecting — something is in flight
//   nord3    nothing to talk to (unconfigured, unpaired, unreachable, down)
//
// Same three-state palette the bluetooth pill uses, plus a warning colour for
// the transitional states because they are the ones worth noticing.
//
// Click opens GoogleTvPanel; hover shows the one-line summary.
Item {
    id: root

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    readonly property color tint: {
        // The set, not the streamer: green should mean "there is a picture".
        if (GoogleTv.isOn && GoogleTv.tvPowered !== false)
            return Theme.nord14;
        if (GoogleTv.connected)
            return Theme.foreground;
        switch (GoogleTv.status) {
        case "connecting":
        case "reconnecting":
        case "pairing":
            return Theme.nord13;
        }
        return Theme.nord3;
    }

    Pill {
        id: pill

        Text {
            text: "TV"
            color: root.tint
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }

    property bool panelOpen: false

    TapHandler {
        onTapped: root.panelOpen = !root.panelOpen
    }

    Popout {
        anchorItem: root
        opened: root.panelOpen
        onDismissed: root.panelOpen = false
        // A remote is buttons, not names: the default card leaves the d-pad
        // marooned in the middle of a lot of nothing. The panel knows how
        // wide its widest row is, so the card is that plus its padding.
        panelWidth: panel.contentWidth + Theme.panelPadding * 2

        GoogleTvPanel {
            id: panel
        }
    }

    HoverHandler {
        id: hover
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        Text {
            text: GoogleTv.host ? GoogleTv.summary + "\n" + GoogleTv.host : GoogleTv.summary
            color: Theme.foreground
            font.pixelSize: Theme.tooltipFontSize
            renderType: Text.NativeRendering
        }
    }
}
