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

## Implementation amendments (2026-08-26, issue 02)

The decision stands. Five things the original text got wrong or did not anticipate,
all found by building the post-removal system and diffing it against the live one.

1. **plasma-workspace stays — but for the menu, not for portals.** The
   configPackages re-check is resolved: **keep it**. The old justification (that
   configPackages makes HM scan for `*.portal` files and register the KDE portal's
   interfaces) is simply false — HM's module does only
   `home.packages = packages ++ cfg.configPackages`, i.e. it installs the package.
   The Secret interface is registered by `kwallet.portal` from `kdePackages.kwallet`.
   plasma-workspace is nonetheless load-bearing as the **sole** provider of
   `etc/xdg/menus/plasma-applications.menu` and the 40 `share/desktop-directories/*.directory`
   files it references — exactly what `XDG_MENU_PREFIX=plasma-` resolves to. Its
   Plasma autostart entries are all `OnlyShowIn=KDE`, so nothing Plasma starts.

2. **Removing plasma6 silently changes the SDDM greeter's compositor.** plasma6 set
   `sddm.wayland.compositor = "kwin"` via `mkDefault`; without it the module default
   `weston` applies. Accepted deliberately — retaining kwin purely for the greeter
   would keep most of what this ADR set out to remove. `compositor = "kwin"` restores
   the old behaviour if the greeter misbehaves.

3. **`defaultSession` must be set explicitly.** plasma6 set it to `plasma`; with
   plasma6 gone it becomes `null` and SDDM preselects nothing. Now
   `hyprland-uwsm`.

4. **Dolphin was never actually declared in this repo.** It — along with
   `kbuildsycoca6` (kservice), breeze-icons and qqc2-desktop-style — arrived purely
   as plasma6 `optionalPackages`/`requiredPackages`. "KDE software is retained
   standalone" therefore required *adding* these explicitly, or `$mod+E` would exec a
   missing binary and KDE apps would render with only the bare `hicolor` icon theme.

5. **`services.xserver.xkb` outlives `services.xserver.enable`.** The weston greeter
   generates its keymap from those values, so that block stays even though the X
   server is disabled. Disabling `services.xserver` is what removes the
   `plasmax11.desktop` entry; the built `sddm.conf` now has no `[X11]` section.
