//@ pragma UseQApplication
//@ pragma IconTheme breeze-dark

import Quickshell
import qs.Bar
import qs.Menu
import qs.Notifications
import qs.Osd
import qs.Polkit

// The Shell — one long-lived Quickshell process per Hyprland session, hosting
// the whole desktop UI as plugins (CONTEXT.md, "The Shell"). Written from
// scratch against Quickshell's primitives; omarchy's quattro tree is read-only
// reference material and none of it is vendored (ADR 0001).
//
// The plugin set is the T3 scope from the spec: bar, menu launcher,
// notifications, volume/brightness OSDs, polkit agent. Lock and idle stay
// outside the shell on hyprlock/hypridle (ADR 0004) — the fingerprint unlock
// path is proven and the shell-lock PAM path is unverified on NixOS.
//
// All five have bodies: Bar (issue 03), Menu (issue 04), Notifications + Osd
// (issue 05), PolkitAgent (issue 06). Nothing here is a stub any more.
//
// `//@ pragma UseQApplication` above is required for platform menus, which the
// system tray's right-click DBus menus are.
//
// `//@ pragma IconTheme` is required for icons to resolve AT ALL. Qt only
// consults an icon theme when one is named, and nothing names one here: the
// Plasma session that used to set it is gone (ADR 0002), no Qt platform theme
// is installed, and kdeglobals carries colours but no `[Icons] Theme`. Without
// this line QIcon::fromTheme returns null for every name — including the
// hicolor icons applications ship themselves — and the launcher draws a column
// of holes. breeze-dark rather than breeze because The Shell's surfaces are
// nord0-dark; it inherits breeze, so full-colour application icons still
// resolve through it. First needed by the Menu (issue 04); the tray dodged it
// by receiving pixmaps over DBus.
ShellRoot {
    Bar {}

    Menu {}

    Notifications {}

    Osd {}

    PolkitAgent {}
}
