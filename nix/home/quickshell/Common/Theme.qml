pragma Singleton

import Quickshell
import QtQuick

// The Shell's single source of visual truth.
//
// Every value here is lifted verbatim from the waybar stylesheet that this
// shell replaces (see `programs.waybar.style` in git history, removed by
// issue 03). Bar parity is the contract for the first release: the numbers
// are not "roughly the same feel", they are the same numbers. Retheming is
// deliberately a later piece of work — do not tune these to taste here.
Singleton {
    id: root

    // ---- Nord palette --------------------------------------------------
    // Named after the upstream Nord slots so the mapping back to the old
    // stylesheet's raw hex is checkable at a glance.
    readonly property color nord0: "#2e3440"   // pill base, tooltip bg, active-workspace fg
    readonly property color nord2: "#434c5e"   // workspace hover bg
    readonly property color nord3: "#4c566a"   // idle workspace fg, tooltip border, BT-off fg
    readonly property color nord4: "#d8dee9"   // default foreground
    readonly property color nord6: "#eceff4"   // workspace hover fg
    readonly property color nord8: "#88c0d0"   // active workspace bg, clock fg
    readonly property color nord11: "#bf616a"  // critical / muted / disconnected
    readonly property color nord13: "#ebcb8b"  // warning
    readonly property color nord14: "#a3be8c"  // good / connected / charging

    // ---- Bar geometry --------------------------------------------------
    // waybar: height 30, margin-top 5, margin-left/right 10.
    readonly property int barHeight: 30
    readonly property int barMarginTop: 5
    readonly property int barMarginSide: 10

    // waybar: every module carried `margin: 4px 2px` inside a 30px bar, so a
    // pill is 22px tall and neighbouring pills sit 4px apart (2px each side).
    readonly property int pillHeight: barHeight - 8
    readonly property int pillSpacing: 4
    readonly property int pillRadius: 6
    // waybar: `padding: 0 12px` on modules, `padding: 0 10px` on workspace
    // buttons.
    readonly property int pillPadding: 12
    readonly property int workspacePadding: 10

    // waybar: `background: rgba(46, 52, 64, 0.65)` — nord0 at 65%. Written as
    // an explicit rgba rather than Qt.alpha() so the constant matches the
    // stylesheet it came from.
    readonly property color pillBackground: Qt.rgba(46 / 255, 52 / 255, 64 / 255, 0.65)
    readonly property color foreground: nord4

    // ---- Typography ----------------------------------------------------
    // waybar: `font-family: "Sans", sans-serif; font-size: 13px`. The family
    // is left unset so Qt resolves the fontconfig default sans, which is what
    // GTK's "Sans" resolved to as well.
    readonly property int fontSize: 13
    // The calendar tooltip was `<tt>` in waybar, i.e. the fontconfig monospace
    // alias. Qt understands "monospace" through the same fontconfig mapping.
    readonly property string monoFamily: "monospace"
    // waybar wrapped the calendar in `<small>`, which is GTK's ~0.83x scale.
    readonly property int tooltipFontSize: 11

    // ---- Tooltips ------------------------------------------------------
    // waybar: bg nord0 (opaque), 1px nord3 border, 6px radius, nord4 text.
    readonly property color tooltipBackground: nord0
    readonly property color tooltipBorder: nord3
    readonly property int tooltipRadius: 6
    readonly property int tooltipPadding: 8

    // Band thickness of the AI-quota ring glyph. Settled by eye against the
    // real tooltip: thinner and the three marks stop being separable, thicker
    // and the glyph outweighs the numbers it is annotating.
    readonly property int quotaRingThickness: 11

    // ---- Launcher menu (issue 04) --------------------------------------
    // These are NOT parity values: waybar had no launcher, and walker's look
    // is not something we are reproducing. They are derived from what is
    // already here — the tooltip's card treatment (nord0 on a nord3 hairline)
    // and the workspace button's active state (nord8 slab, nord0 text) — so
    // the menu reads as part of the same shell rather than a second theme.
    // The one borrowed-from-elsewhere number is the radius: Hyprland's
    // `decoration.rounding` is 8, and the menu is window-sized, not pill-sized.
    readonly property int menuWidth: 520
    readonly property int menuRadius: 8
    readonly property int menuPadding: 12
    readonly property int menuRowHeight: 36
    readonly property int menuRowRadius: 6
    readonly property int menuIconSize: 22
    // Rows past this scroll. Eight is roughly a third of the 960pt-tall panel
    // this runs on, which keeps the card a menu rather than a page.
    readonly property int menuMaxRows: 8
    // Vertical placement: the card's top edge sits this far down the screen.
    // Above centre, because the list grows downward and a centred card walks
    // up the screen as you type.
    readonly property real menuTopFraction: 0.18

    readonly property int menuQueryFontSize: 16
    readonly property int menuDetailFontSize: 11

    readonly property color menuBackground: nord0
    readonly property color menuBorder: nord3
    readonly property color menuSelectedBackground: nord8
    readonly property color menuSelectedForeground: nord0
    readonly property color menuDetailForeground: nord3
    // A scrim dark enough to say "this is modal", light enough to keep the
    // desktop legible behind it. nord0 at 45%.
    readonly property color menuScrim: Qt.rgba(46 / 255, 52 / 255, 64 / 255, 0.45)

    // ---- Notifications (issue 05) --------------------------------------
    // Also not parity values. mako ran here on stock defaults — no config file
    // ever existed (`git log` has none, and nothing in hyprland.nix wrote
    // one), so there is no previous look to reproduce. These reuse the menu's
    // card treatment for the same reason the menu did: one card idiom across
    // the shell rather than a second theme.
    // Wider than the first draft, to hold the larger type below without
    // wrapping every second summary.
    readonly property int notifWidth: 420
    readonly property int notifRadius: menuRadius
    readonly property int notifPadding: menuPadding
    readonly property int notifSpacing: 8
    readonly property int notifIconSize: 32
    // Gap between the summary, the body and the app name inside one card.
    readonly property int notifLineSpacing: 4
    // The banner column hangs off the top-right corner, clear of the bar:
    // the bar's own top margin, plus its height, plus the gap that separates
    // two pills. Derived rather than hardcoded so moving the bar moves these.
    readonly property int notifMarginTop: barMarginTop + barHeight + pillSpacing
    readonly property int notifMarginSide: barMarginSide

    // Past this many on screen at once the column runs off the bottom of a
    // 960pt panel. Older banners keep their own timers and leave on schedule;
    // nothing is dropped, since everything is in the history either way.
    readonly property int notifMaxBanners: 5
    // The history is a ring, not an archive. Fifty is far more than the ten
    // omarchy keeps, and still bounded — an unbounded list is a leak that only
    // shows up after a week of uptime.
    readonly property int notifHistoryMax: 50

    // Default lifetimes, used only when the sending application does not
    // specify one. Seconds are the wire unit; milliseconds are Timer's.
    readonly property int notifTimeoutLow: 3000
    readonly property int notifTimeoutNormal: 5000

    readonly property color notifBackground: menuBackground
    readonly property color notifBorder: menuBorder

    // Notification text does NOT reuse the menu's `menuDetailForeground`.
    //
    // That token is nord3 on a nord0 card — a contrast ratio of about 1.6:1,
    // which fails every accessibility threshold there is. It gets away with it
    // in the launcher because it is only ever the trailing hint beside a
    // full-contrast application name, on a surface you look at for a second
    // while typing. A notification body is the actual message, read at a
    // glance from wherever you happen to be sitting.
    //
    // So secondary text here is nord4 dimmed by opacity, not a Polar Night
    // grey. Nord's dark slots (nord0-nord3) are surfaces; its light slots
    // (nord4-nord6) are text. Dimming a text colour keeps the hierarchy
    // without dropping under the floor: nord4 at 70% over nord0 lands around
    // 5:1, against 1.6:1 for nord3.
    readonly property color notifForeground: nord4
    readonly property real notifMetaOpacity: 0.7
    // The urgency stripe down the leading edge. Low is the same grey as
    // secondary text (i.e. reads as "no stripe"), normal takes the accent the
    // active workspace uses, critical the red every other widget uses for bad
    // news.
    readonly property int notifAccentWidth: 3
    readonly property color notifAccentLow: nord3
    readonly property color notifAccentNormal: nord8
    readonly property color notifAccentCritical: nord11

    // Larger than the bar's 13px, and deliberately not aliased to it. The bar
    // is a reference you scan on purpose; a notification has to be legible
    // from wherever you were already looking when it appeared. The old values
    // (13 summary / 11 body, inherited from the bar and the tooltip) read as
    // fine print.
    readonly property int notifSummaryFontSize: 15
    readonly property int notifBodyFontSize: 13
    // The app name and the history timestamp — genuinely secondary, and the
    // one place small is correct.
    readonly property int notifMetaFontSize: 12
    // Long bodies (a mail preview, a build log tail) are clamped rather than
    // allowed to grow a banner into a panel. The full text is still in the
    // history, which scrolls.
    readonly property int notifBodyMaxLines: 4

    readonly property int notifHistoryWidth: 460
    readonly property real notifHistoryTopFraction: menuTopFraction

    // ---- Polkit dialog (issue 06) --------------------------------------
    // Same card idiom again — nord0 slab, nord3 hairline, menu radius — so an
    // auth prompt reads as part of this shell and not as a stray GTK dialog.
    // Narrower than the launcher: it holds one sentence and one field.
    readonly property int polkitWidth: 420
    readonly property int polkitRadius: menuRadius
    readonly property int polkitPadding: menuPadding
    readonly property int polkitIconSize: 32
    // Above centre for the same reason the launcher is: it appears while you
    // are looking at whatever asked for it, not at the middle of the screen.
    readonly property real polkitTopFraction: 0.28
    readonly property int polkitFieldHeight: 32
    readonly property int polkitButtonHeight: 30

    readonly property color polkitBackground: menuBackground
    readonly property color polkitBorder: menuBorder
    readonly property color polkitScrim: menuScrim
    // Text tokens follow the notification rules, not the menu's: this is prose
    // you have to read under mild pressure, so secondary text is dimmed nord4
    // rather than nord3-on-nord0 (see the notification note above).
    readonly property color polkitForeground: nord4
    readonly property real polkitMetaOpacity: notifMetaOpacity
    readonly property color polkitError: nord11
    readonly property color polkitFieldBackground: nord2
    readonly property color polkitAccent: nord8
    readonly property int polkitTitleFontSize: notifSummaryFontSize
    readonly property int polkitBodyFontSize: notifBodyFontSize

    // ---- Bar popout panels ---------------------------------------------
    // The click-through panels behind the audio, bluetooth and network pills
    // (Common/Popout.qml). Same card idiom as everything else in this shell —
    // nord0 slab, nord3 hairline, menu radius — so a panel reads as the pill
    // it came from getting bigger, rather than as a separate application.
    //
    // Narrower than the launcher's 520: a panel holds a slider and a short
    // list of device names, not a search result page. Wide enough that a
    // typical sink description ("Family 17h/19h HD Audio Controller Analog
    // Stereo") elides late rather than immediately.
    readonly property int panelWidth: 340
    readonly property int panelRadius: menuRadius
    readonly property int panelPadding: menuPadding
    // Between stacked groups (slider, outputs, inputs). Wider than the gap
    // between rows inside a group, which is what makes the groups read as
    // groups without needing a rule between them.
    readonly property int panelSpacing: 12
    readonly property int panelRowSpacing: 2
    // Past this share of the output's height the panel scrolls instead of
    // growing. Two thirds leaves the desktop underneath legible and keeps the
    // card clear of the bottom edge; a wifi list is routinely long enough to
    // need it.
    readonly property real panelMaxHeightFraction: 0.66
    readonly property int panelRowHeight: menuRowHeight
    readonly property int panelRowRadius: menuRowRadius

    readonly property color panelBackground: menuBackground
    readonly property color panelBorder: menuBorder
    // Text follows the notification rules rather than the launcher's: a panel
    // is read and acted on, not skimmed while typing, so secondary text is
    // dimmed nord4 rather than nord3-on-nord0 (see the notification note).
    readonly property color panelForeground: nord4
    readonly property real panelMetaOpacity: notifMetaOpacity
    // The selected row — the active sink, the connected device. Reuses the
    // active-workspace treatment, which is already this shell's way of saying
    // "this is the current one".
    readonly property color panelRowHover: nord2
    readonly property color panelAccent: nord8

    // Section labels ("Output", "Input"). The one place small type is right:
    // they are signposts, never content.
    readonly property int panelSectionFontSize: 11
    readonly property int panelRowFontSize: fontSize

    // Bad news inside a panel: a failed wifi association, a bluetooth pairing
    // that was rejected. Same red as every other "this went wrong" in the bar.
    readonly property color panelError: nord11

    // Buttons (Common/Button.qml). Equal to the polkit dialog's values, which
    // is what made promoting PolkitButton a rename rather than a retheme.
    readonly property int buttonHeight: 30

    // The radio switches at the head of the bluetooth and network panels.
    // 2:1 is the usual switch proportion; the height is a hair under the row
    // height so a header row is no taller than a device row.
    readonly property int toggleHeight: 18
    readonly property int toggleWidth: 36

    // The passphrase field in the network panel. Sized like the polkit
    // dialog's response field, which is the shell's other secret input.
    readonly property int panelFieldHeight: polkitFieldHeight
    readonly property color panelFieldBackground: polkitFieldBackground

    // The volume slider. Taller track than the OSD's 6px because this one is
    // a drag target, not a readout — 6px is a fiddly thing to hit with a
    // pointer, and Fitts' law does not care how tidy it looks.
    readonly property int panelSliderHeight: 10
    readonly property color panelSliderTrack: osdTrack
    readonly property color panelSliderFill: osdFill
    readonly property color panelSliderMuted: osdMuted

    // ---- OSD (issue 05) ------------------------------------------------
    readonly property int osdWidth: 260
    readonly property int osdRadius: menuRadius
    readonly property int osdPadding: menuPadding
    // Bottom-centre, out of the way of both the bar and the launcher card.
    readonly property int osdMarginBottom: 96
    readonly property int osdVisibleMs: 1500
    readonly property int osdIconSize: 20
    readonly property int osdTrackHeight: 6
    readonly property color osdBackground: menuBackground
    readonly property color osdBorder: menuBorder
    readonly property color osdTrack: nord3
    readonly property color osdFill: nord8
    // Muted borrows the same red as the bar's audio widget.
    readonly property color osdMuted: nord11
}
