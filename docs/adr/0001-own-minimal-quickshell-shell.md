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

## Amendment (2026-08-28, issue 03)

The Shell now exists at `nix/home/quickshell/`, deployed by `programs.quickshell.configs.shell` to `~/.config/quickshell/shell`. Layout as built:

- `shell.qml` — `ShellRoot`, instantiating one plugin per T3 scope item.
- `Common/` — `Theme` (singleton), `Pill`, `HoverTooltip`.
- `Bar/` — `Bar` (Variants over screens) → `BarPanel` → one file per widget.
- `Menu/`, `Notifications/`, `Osd/`, `Polkit/` — instantiated empty `Scope`s, one per remaining issue.

Two things the ADR did not anticipate, both confirmed while writing it:

- **Nothing was vendored, but nothing needed to be either.** Every waybar module maps onto a first-party Quickshell service (`Hyprland`, `Bluetooth`, `Networking`, `Pipewire`, `UPower`, `SystemTray`), so the Bar is roughly 500 lines of our QML with no omarchy code read beyond confirming the `Variants { model: Quickshell.screens }` idiom. Omarchy's own bar is ~1000 lines in `Bar.qml` alone because it carries a plugin registry, a theme pipeline and drag-to-reorder — none of which we want.
- **Quickshell synthesizes a `qmldir` per directory**, registering the config root as module `qs` and each subdirectory as `qs.<Dir>`, and auto-registers any file with `pragma Singleton`. So the directory layout *is* the module layout; there is no manifest to maintain. This is why plugins can be plain directories rather than omarchy's `manifest.json` scheme.

One deliberate hole: the stubs are instantiated but empty. In particular `Notifications/` must NOT construct a `NotificationServer` until issue 05 retires mako, because two processes claiming `org.freedesktop.Notifications` means one of them silently stops receiving notifications.
