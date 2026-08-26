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
