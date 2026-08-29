import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common

// waybar's `hyprland/workspaces`.
//
// Deliberately NOT built on Common/Pill: a workspace button needs pointer
// handlers covering the whole slab including its padding, and Pill reparents
// its children into a content Item sized to the text. Inlining the rectangle
// keeps the hit area honest.
Row {
    id: root

    // The screen this bar instance is on. Workspaces belonging to other
    // monitors are filtered out, matching waybar's `all-outputs: false`
    // default.
    required property var screen

    // `monitorFor` is an invokable, not a property, so this resolves once and
    // does not re-run. Two consequences, both acceptable on a single-monitor
    // host: if Hyprland's IPC has not populated yet this is null and the
    // filter below degrades to "show everything" (identical output here), and
    // a workspace later moved between monitors will not move between bars.
    readonly property var monitor: Hyprland.monitorFor(screen)

    spacing: Theme.pillSpacing

    // waybar switches workspaces on scroll unless `disable-scroll` is set, and
    // it was not set. `e+1`/`e-1` step through *existing* workspaces, which is
    // what waybar's cycle over its own button list amounted to.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y > 0)
                Hyprland.dispatch("workspace e-1");
            else if (event.angleDelta.y < 0)
                Hyprland.dispatch("workspace e+1");
        }
    }

    Repeater {
        // Recomputed whenever the workspace list changes. Per-workspace state
        // (focused/active) is bound directly in the delegate, so it updates
        // without rebuilding this array.
        model: {
            const out = [];
            for (const ws of Hyprland.workspaces.values) {
                // Negative ids are special workspaces (scratchpads). waybar
                // hid them by default (`show-special: false`).
                if (ws.id < 0)
                    continue;
                if (root.monitor && ws.monitor !== root.monitor)
                    continue;
                out.push(ws);
            }
            return out;
        }

        delegate: Rectangle {
            id: button

            required property var modelData

            // `.active` is the workspace visible on its monitor, `.focused`
            // the one with input focus. waybar styled both identically.
            readonly property bool highlighted: modelData.active || modelData.focused

            implicitHeight: Theme.pillHeight
            implicitWidth: label.implicitWidth + Theme.workspacePadding * 2
            radius: Theme.pillRadius

            // Hover last, because in the waybar stylesheet the `:hover` rule
            // came after the `.active` rule and equal specificity means the
            // later rule wins — a hovered active workspace showed hover
            // colours, not active ones.
            color: hover.hovered ? Theme.nord2 : (highlighted ? Theme.nord8 : Theme.pillBackground)

            Text {
                id: label

                anchors.centerIn: parent
                text: button.modelData.name
                color: hover.hovered ? Theme.nord6 : (button.highlighted ? Theme.nord0 : Theme.nord3)
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            HoverHandler {
                id: hover
            }

            TapHandler {
                onTapped: button.modelData.activate()
            }
        }
    }
}
