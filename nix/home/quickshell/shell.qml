//@ pragma UseQApplication

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
// Only the Bar has a body today (issue 03). The rest are instantiated stubs so
// that issues 04-06 each add a body to a slot that already exists, rather than
// re-litigating the layout. Each stub's own file says which issue owns it.
//
// `//@ pragma UseQApplication` above is required for platform menus, which the
// system tray's right-click DBus menus are.
ShellRoot {
    Bar {}

    Menu {}

    Notifications {}

    Osd {}

    PolkitAgent {}
}
