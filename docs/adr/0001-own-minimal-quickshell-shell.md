# Own minimal Quickshell shell, Omarchy as reference only

## Status

accepted (2026-08-22)

## Decision

We write our own minimal Quickshell QML tree ("The Shell") rather than shipping basecamp/omarchy's quattro shell. Omarchy's `shell/plugins/*.qml` is the reference we read while writing each piece; nothing is vendored and no omarchy runtime dependency (its bash scripts, `OMARCHY_PATH`, `shell.json`) crosses into this repo.

## Considered Options

- **Ship omarchy's shell wholesale (flake input)** — rejected: it assumes the Arch/omarchy runtime everywhere; coupling a NixOS host to a distro's scripts.
- **Vendor-and-strip omarchy's tree** — rejected: still drags along panels/features we don't want and makes upstream churn our problem.
- **Own minimal config, omarchy QML as reference** — chosen.

## Consequences

We pay QML-writing effort up front; in exchange every line in the repo is ours and the omarchy dependency is purely documentation.
