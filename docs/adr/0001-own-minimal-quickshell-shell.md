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

## Amendment (2026-08-29, issue 05)

`Notifications/` and `Osd/` have bodies; only `Polkit/` is still a stub. The hole above is closed: mako's package and its systemd unit were deleted in the same commit that added the `NotificationServer`, and `nix/home/hyprland.nix` now carries a comment at the site of the deleted unit saying why nothing may take its place.

Confirmed while writing it, worth keeping:

- **The bus hand-off is live, not boot-scoped.** Quickshell logs `Could not register notification server at org.freedesktop.Notifications, presumably because one is already registered` and then *retries when the holder unregisters*. So `systemctl --user stop mako` hands the name over to a running shell with no restart. That is what makes issue 05 testable against the live session at all — but it is also the trap in the other direction: `nixos-rebuild switch` removes mako's unit without stopping the running process, so the name stays held until logout. Stop mako by hand when landing this.
- **The reference-only rule held again, and the deviation is deliberate.** Omarchy persists notifications and DND to `~/.local/state/`; The Shell keeps both in memory. Persisted DND is a silent, open-ended failure — DND left on from last week, no banners, and no reason to suspect the shell. Restarting into "notifications work" is the safer default and matches what a stateless mako did.
- **A singleton is the seam between a service and its surfaces.** `NotificationService.qml` owns the bus name, the tracked set, DND and the history; `Notifications.qml` owns only the surfaces and the IPC handle. The split is forced rather than stylistic: the Bar's DND indicator needs the same state, and per the amendment above, `qs.<Dir>` module registration means a singleton is the only way state crosses a directory boundary.

## Amendment (2026-08-29, issue 06)

`Polkit/` has a body, so no stub remains: every plugin `shell.qml` instantiates now does something. The agent is `Quickshell.Services.Polkit.PolkitAgent` (a first-party service in the pinned v0.3.1, so again nothing was vendored and no omarchy plugin was read), plus `PolkitDialog.qml` and a local `PolkitButton.qml`.

Confirmed while writing it:

- **`pkexec` is not a usable test on this host, and never was.** NixOS does not install a setuid wrapper for it — `/run/wrappers/bin/pkexec` does not exist and `/run/current-system/sw/bin/pkexec` is mode 555, so it exits with "pkexec must be setuid root" before polkit is ever consulted. Issue 06's acceptance criterion named it anyway. The working equivalent is any privileged systemd action as an unprivileged user (`systemctl restart bluetooth.service`): systemd asks polkit with interaction allowed, which is exactly the same agent path. Verified both outcomes — authenticated, service restarted; cancelled, `Access denied` returned immediately with no hang.
- **The prompt here is a fingerprint prompt, not a password prompt.** `security.pam.services.polkit-1.fprintAuth = true` (nix/nixos/diogenes.nix) means the first PAM stage asks for a finger, and `AuthFlow.isResponseRequired` is false for it. A dialog written as "label, password box, OK" would have shown an inert password box that nothing could dismiss. The dialog is written against `inputPrompt`/`isResponseRequired`/`responseVisible` instead, which is why it works unmodified for both stages — and why ESC is bound as a window `Shortcut` rather than only in the field's key handler, since during a fingerprint stage there is no field to receive the key.
- **Agent lifetime = session lifetime, for free.** Polkit registers the agent against the session subject, and quickshell.service is already `PartOf=graphical-session.target`, so there is nothing to add in nix. A side instance (`qs -p ./nix/home/quickshell`) registers its own agent and can be tested against the live session — but only while the packaged shell's agent is absent or losing the race, so once this lands, test side instances by stopping the service first.
