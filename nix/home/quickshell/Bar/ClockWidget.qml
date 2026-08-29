import QtQuick
import Quickshell
import qs.Common

// waybar's `clock` module:
//   format          "{:%a %b %d  %H:%M}"   (two spaces before the time)
//   tooltip-format  "<tt><small>{calendar}</small></tt>"
// with `#clock { color: #88c0d0; font-weight: bold }`.
//
// The strftime format maps onto Qt's date format one-for-one: %a→ddd, %b→MMM,
// %d→dd, %H→HH, %M→mm.
Item {
    id: root

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Minute precision: the format shows no seconds, so waking once a second
    // would only burn power.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Pill {
        id: pill

        Text {
            text: Qt.formatDateTime(clock.date, "ddd MMM dd  HH:mm")
            color: Theme.nord8
            font.pixelSize: Theme.fontSize
            font.bold: true
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hover
    }

    HoverTooltip {
        anchorItem: root
        visible: hover.hovered

        // waybar's `{calendar}` in month mode: a centred "Month Year" caption
        // over a Sunday-first grid with today emphasised. Built as real items
        // rather than a monospace text blob so the highlight does not depend
        // on rich-text parsing.
        Column {
            id: calendar

            readonly property int year: clock.date.getFullYear()
            readonly property int month: clock.date.getMonth()
            readonly property int todayDate: clock.date.getDate()

            // Leading nulls pad the first row out to the weekday the 1st
            // falls on; then one entry per day of the month.
            readonly property var cells: {
                const lead = new Date(year, month, 1).getDay();
                const days = new Date(year, month + 1, 0).getDate();
                const out = [];
                for (let i = 0; i < lead; i++)
                    out.push(null);
                for (let d = 1; d <= days; d++)
                    out.push(d);
                return out;
            }

            spacing: 6

            Text {
                // Width comes from the grid, never from the Column: binding it
                // to the parent's width while the parent sizes itself from its
                // children is a binding loop.
                width: grid.width
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDateTime(clock.date, "MMMM yyyy")
                color: Theme.foreground
                font.family: Theme.monoFamily
                font.pixelSize: Theme.tooltipFontSize
                font.bold: true
                renderType: Text.NativeRendering
            }

            Grid {
                id: grid

                columns: 7
                spacing: 4

                Repeater {
                    model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

                    delegate: Text {
                        required property string modelData

                        width: 20
                        horizontalAlignment: Text.AlignRight
                        text: modelData
                        color: Theme.nord3
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.tooltipFontSize
                        renderType: Text.NativeRendering
                    }
                }

                Repeater {
                    model: calendar.cells

                    delegate: Text {
                        required property var modelData

                        readonly property bool isToday: modelData !== null && modelData === calendar.todayDate

                        width: 20
                        horizontalAlignment: Text.AlignRight
                        text: modelData === null ? "" : String(modelData)
                        color: isToday ? Theme.nord8 : Theme.foreground
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.tooltipFontSize
                        font.bold: isToday
                        font.underline: isToday
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }
}
