# Lock and idle stay on hyprlock/hypridle

## Status

accepted (2026-08-22)

## Decision

The consolidation into Quickshell deliberately excludes the lock screen and idle management. hyprlock (native fprintd backend, parallel password-or-fingerprint) and hypridle remain as separate daemons with their current configs and timings.

## Consequences

This is a deliberate deviation from omarchy quattro, which folds lock+idle into the shell via WlSessionLock and its own PAM services. Omarchy's fingerprint flow inside the shell lock is unverified on NixOS; our current setup is proven. Revisit only if a tested PAM story for a shell lock emerges.
