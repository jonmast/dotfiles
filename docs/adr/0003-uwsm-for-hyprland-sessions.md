# Hyprland runs under uwsm; user services bind to graphical-session.target

## Status

accepted (2026-08-22)

## Decision

Hyprland sessions launch via uwsm (`programs.uwsm.enable` + HM `withUwsm`). All Hyprland-scoped user services rebind from `hyprland-session.target` to `graphical-session.target`, which uwsm now owns and stops cleanly on logout.

## Considered Options

- Keep hand-bound `hyprland-session.target` services — rejected: HM never stops that target on logout (documented leak-prevention TODO v1.1); uwsm fixes it structurally.

## Consequences

- A previous naive attempt at parallel uwsm opt-in broke booting. De-risk: land uwsm while the Plasma session still exists, verify the uwsm-launched Hyprland boots, and only then remove Plasma — a fallback session is present at every risky step.
- SDDM shows exactly one session entry after Plasma removal; no parallel-entry ambiguity.

## Implementation amendments (2026-08-25, issue 01)

The decision stands; two details differ from the text above.

1. **The rebind is deferred, not done.** Services stay on `hyprland-session.target`
   during the dual-session window, because Plasma also activates
   `graphical-session.target` — a literal rebind would start waybar/mako/hypridle
   under Plasma (hypridle crash-loops without Hyprland IPC). The leak is fixed
   transitively: `hyprland-session.target` has `BindsTo=graphical-session.target`,
   which uwsm owns and stops on logout. Issue 02 collapses this once Plasma is gone.

2. **The "naive attempt broke booting" is very likely explained.** HM's default
   `systemd.extraCommands` appends `systemctl --user stop hyprland-session.target`
   to `exec-once`. That target carries `PropagatesStopTo=graphical-session.target`,
   and systemd propagates a stop even when the target is inactive — under uwsm that
   tears down graphical-session → wayland-session@Hyprland.target → the compositor,
   at login. Verified with probe units. Fixed by keeping only the `start` command.

Also note `programs.hyprland.withUWSM = true` is sufficient on its own; do NOT add
a `programs.uwsm.waylandCompositors` entry for Hyprland. See issue 01 for why
(it shadows the package's own session entry and loses `start-hyprland` +
`cap_sys_nice`).
