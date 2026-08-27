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

## Implementation amendments (2026-08-26, issue 02)

1. **Amendment 1 above is now discharged — the rebind happened.** With Plasma
   gone, waybar/mako/hypridle/walker/elephant bind directly to
   `graphical-session.target` as the original decision called for. Ordering is
   safe because `wayland-wm@.service` is `Type=notify` and declares
   `Before=graphical-session.target`, so the target is only reached after the
   compositor signals ready via `uwsm finalize` — which is also what exports
   `HYPRLAND_INSTANCE_SIGNATURE`. hypridle therefore always finds a live IPC socket.

2. **`hyprland-session.target` is retained but nothing binds to it.** It keeps one
   job: in the non-uwsm escape-hatch session nothing else activates
   `graphical-session.target`, and `BindsTo=` implies `Requires=`, so the
   `exec-once` start of `hyprland-session.target` pulls `graphical-session.target`
   up and the five services with it. Verified with probe units in both directions:
   starting only the hypr target activates graphical + its bound service; stopping
   the graphical target tears all three down.

3. **Consequence line above corrected.** "SDDM shows exactly one session entry
   after Plasma removal" is no longer accurate — issue 02 deliberately kept the
   plain `hyprland.desktop` entry as an in-SDDM escape hatch, so there are two.
   `services.displayManager.defaultSession = "hyprland-uwsm"` preselects the right
   one. See ADR 0002's amendment.
