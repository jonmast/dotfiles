# Plasma session removed; KDE software stays app-level

## Status

accepted (2026-08-22)

## Decision

`services.desktopManager.plasma6.enable` and `services.xserver.enable` come out of diogenes.nix. SDDM (wayland) remains the display manager with Hyprland as its only session entry. KDE software is retained standalone: kwallet + kwallet-pam (unlocks at SDDM login — that PAM wiring is session-independent), xdg-desktop-portal-kde (Secret portal, Dolphin file chooser), kdeconnect, kate.

## Consequences

- There is no full-Plasma fallback session; `nixos-rebuild --rollback` / boot generations are the safety net.
- Anything plasma-workspace silently provided must now be explicit. Notably: a polkit agent (the Shell provides one — the old Hyprland session had none, GUI auth prompts were already broken there).
- `kdePackages.plasma-workspace` in xdg.portal configPackages needs re-checking once Plasma is gone.
- Known follow-ups from research: disable baloo, fix XDG_MENU_PREFIX at the systemd layer for Dolphin's sycoca.
