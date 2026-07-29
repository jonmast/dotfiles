# Plan: Add Hyprland as an alternate compositor (alongside KWin/Plasma)

**Status:** Draft — not yet started
**Branch target:** `nixos-overhaul` (current working branch)
**Owner:** jon
**Last updated:** 2026-07-26

## Goal

Add Hyprland as a **co-installable, user-selectable alternative** to the existing KWin/Plasma 6 session on `diogenes`. Both compositors must remain usable; the user picks at the SDDM login screen (per-boot). The flake remains the single source of truth.

**Non-goals (this iteration):**
- Replacing KWin as the default. Plasma 6 stays the default SDDM session.
- Removing `services.desktopManager.plasma6.enable` or any KDE service.
- Touching macOS / chezmoi templates (Hyprland is Linux-only).
- A polished Hyprland dotfile set — minimum viable: clean session, autostart the same tray apps that Plasma runs, fprintd unlock at the lock screen.

## Why

- Wayland-native: Hyprland is wayland-only; KWin/Plasma 6 here currently runs on X11 (`services.xserver.enable = true`). Going Hyprland gives a real wayland session and lets us retire X11 long-term if desired.
- Lightweight: useful for travel / low-battery scenarios, or when KDE bloat is undesirable.
- Tiling: keystroke-driven workflow that some work fits.
- Both worlds: keep Plasma for when KDE integration matters (kate, kdeconnect, fprintd GUI, sddm fingerprint).

## Current state (baseline)

From `nix/nixos/diogenes.nix`:

```nix
services.xserver.enable = true;                                  # X11 server
services.displayManager.sddm.enable = true;
services.displayManager = {
  autoLogin.enable = true;
  autoLogin.user = "jon";
};
services.desktopManager.plasma6.enable = true;                   # Plasma 6 + KWin
services.xserver.xkb = { layout = "us"; variant = ""; };
security.pam.services.sddm.fprintAuth = true;                    # fingerprint at login
```

Plasma 6 + KWin is the only session. KWin is started by `plasma6.service`. SDDM autologs in as `jon` straight into Plasma.

From `nix/home/common.nix`:

```nix
home.packages = [ ... wl-clipboard ... ghostty ... orca-slicer ... vlc ... ];
xdg.mime.enable = true;
xdg.systemDirs.data = [ "${config.home.homeDirectory}/.nix-profile/share" ];
systemd.user.services.handy = { After = [ "graphical-session.target" ]; ... };
```

`handy` already binds to `graphical-session.target`, which both Plasma and Hyprland provide, so it should keep working without changes.

## Design

### Decision 1 — session selection model: SDDM session picker

**Choice:** Keep `services.displayManager.autoLogin.enable = true`, but switch the autoLogin target from a hard-coded Plasma session to a *default* session that can be overridden from the SDDM session menu.

**Implementation:** NixOS `services.xserver.displayManager.autoLogin.session` is not a first-class option; the default autoLogin session is determined by the `defaultSession` set on the DM. For SDDM the cleanest path is:

1. Stop relying on `autoLogin` for the hyprland case.
2. Keep `autoLogin` for Plasma (current behavior).
3. Add a **second `sddm` configuration** is not possible (sddm is a single service), so instead provide both `.desktop` files and use SDDM's `default.desktop` symlink strategy.

**Revised approach (simpler, upstream-blessed):**

- In `diogenes.nix`, drop `displayManager.autoLogin` entirely for the experimental phase, OR keep autologin but point it at a wrapper that respects a per-user env var.
- Provide both session files in `/run/current-system/share/xsessions/` and `/share/wayland-sessions/`.
- In SDDM, set `services.displayManager.sddm.defaultSession = "hyprland.desktop"` or `"plasma.desktop"` via a small wrapper, OR let the user pick at the SDDM UI each boot.

**Final pick:** drop autologin for now (it is a convenience we can re-add via SDDM's `defaultSession` mechanism later). Authenticate with fprintd at the SDDM prompt; the user picks the session from the SDDM menu. This is also more secure.

### Decision 2 — Hyprland package + NixOS module

- Use `pkgs.hyprland` from `nixos-unstable` (already pinned in the flake). The home-manager module path is `wayland.windowManager.hyprland.enable` (NOT `programs.hyprland` — that path does not exist in the current home-manager). The module wires up a `hyprland.desktop` session file and starts Hyprland as a user systemd service when the user logs into the `hyprland` session.
- Add `hyprland` to `home.packages` in `nix/home/linux.nix` (linux-only; mac chezmoi branch unaffected).
- Enable `programs.hyprland.enable = true` in `nix/home/linux.nix` (home-manager module). This:
  - Drops a `hyprland.desktop` file into the user share.
  - Provides `hyprland.session = { ... }` for config.
  - Installs `xdg-desktop-portal-hyprland` and friends? No — portals are separate. We will install them explicitly.

### Decision 3 — X11 status

`services.xserver.enable = true` is required for Plasma and for SDDM itself. Keep it. Hyprland runs on Wayland but XWayland (provided by `xwayland` package, included in `hyprland`) is enough — it does not require `services.xserver.enable`. Verified: many NixOS setups run `services.xserver.enable = false` with Hyprland. We keep X11 enabled because Plasma still needs it; this is fine.

### Decision 4 — config storage

- Hyprland config lives at `~/.config/hypr/hyprland.conf`.
- **Option A:** `programs.hyprland.settings` (home-manager) — declarative, in `linux.nix`. Best for the source-of-truth principle.
- **Option B:** rcm/chezmoi-managed `dot_config/hypr/hyprland.conf`. Treated as a dotfile, not nix.

**Pick: Option A** for the system-shared skeleton (monitors, env vars, autostart hooks), and **leave the door open** for per-machine overrides. We will keep the file small and let per-app configs (waybar, mako, etc.) live in rcm/chezmoi since they are visual and benefit from per-user iteration. Initial skeleton:

```nix
programs.hyprland = {
  enable = true;
  package = pkgs.hyprland;
  settings = {
    monitor = [ ",preferred,auto,1" ];
    input = {
      kb_layout = "us";
      follow_mouse = 1;
    };
    general = {
      gaps_in = 5;
      gaps_out = 10;
      border_size = 2;
    };
    decoration = { rounding = 8; };
    exec-once = [
      "waybar"
      "mako"
      "/usr/lib/xdg-desktop-portal-hyprland"
    ];
  };
};
```

If `programs.hyprland.settings` ever becomes painful (deeply nested, type errors), fall back to `home.file.".config/hypr/hyprland.conf".text = ...`.

### Decision 5 — waybar, mako, portals, screenlocker

Install in `nix/home/linux.nix` under a `lib.optionals` / explicit list:

- `waybar` — top bar.
- `mako` — notification daemon (replace `plasma-workspace`'s notifications, but Plasma can still run; this is per-session, not per-system).
- `hyprlock` — Wayland-native lock screen.
- `hypridle` — idle daemon (suspend after N min).
- `xdg-desktop-portal-hyprland` — required for screen sharing / GTK portal dialogs.
- `xdg-desktop-portal-gtk` — fallback for non-Hyprland portals.
- `swaybg` — wallpaper (or just skip for v1; Hyprland can have a solid color).
- `grim` + `slurp` — screenshots.
- `wl-clipboard` — already in home.packages, good.
- `wlr-randr` — monitor config (optional).

`hyprlock` integrates with PAM the same way `kde-screenlocker` does; `security.pam.services.hyprlock.fprintAuth = true` may be needed but this should be tested. If Hyprland is the session, SDDM already handled fprintd; the lock-screen unlock is a separate problem we punt to "test it, add PAM service only if needed."

### Decision 6 — fingerprint at SDDM (the autologin change)

We currently autologin as `jon` without prompting. If we drop autologin (Decision 1), the user types password or scans finger at the SDDM prompt. `security.pam.services.sddm.fprintAuth = true` already covers this. No change needed.

If we keep autologin (alternative), the user never sees SDDM and the fprintd setup is unused. We are dropping autologin.

### Decision 7 — KDE integration under Hyprland

- `kdeconnect` works fine on Wayland (it's a background daemon + tray).
- `handy` is already `graphical-session.target`-bound, so it autostarts.
- `orca-slicer`, `kate`, `kdeconnect-kde` are Qt apps; they run under XWayland or natively on Wayland via QtWayland (provided by `pkgs.qt5.qtwayland` / `pkgs.qt6.qtwayland`, both in nixpkgs default).
- Plasma system settings will not run under Hyprland; that is fine.

### Decision 8 — env vars for Qt/Wayland

Add to `nix/home/linux.nix`:

```nix
home.sessionVariables = {
  ...
  NIX_LD_LIBRARY_PATH = ...;  # existing
  QT_QPA_PLATFORM = "wayland;xcb";   # prefer wayland, fall back to xcb (xwayland)
  GDK_BACKEND = "wayland,x11";
  SDL_VIDEODRIVER = "wayland";
  MOZ_ENABLE_WAYLAND = "1";
  XDG_CURRENT_DESKTOP = "Hyprland";   # or omit, to stay neutral
  XDG_SESSION_TYPE = "wayland";
};
```

Caveat: setting these globally can break the Plasma session (Plasma sets them itself). Solution: put them behind a check, e.g. in a Hyprland `exec-once` script that exports them, or use `programs.hyprland.settings.env` to set per-session values. Cleaner: use `programs.hyprland.settings.env` to set `QT_QPA_PLATFORM`, `GDK_BACKEND`, etc. only inside the Hyprland session.

This is the right call — env vars live in the Hyprland config, not in `home.sessionVariables`.

## File-by-file change set

### `nix/nixos/diogenes.nix`

1. **Remove** the `services.xserver.xkb` block (line 54–57). It is X-only; for Hyprland it must be set via `input.kb_layout` in `hyprland.conf`. **Actually keep it** because Plasma still uses X11, and SDDM's X setup needs it. Decision: keep.

2. **Add** a Hyprland session file. NixOS does this automatically when `programs.hyprland.enable = true` is set on a user with home-manager. No change needed here.

3. **Optional but recommended:** add explicit session-via-systemd target. Hyprland's NixOS module (in home-manager) creates `hyprland-session.target` and binds it to `graphical-session.target`. No change needed in `diogenes.nix` for v1.

4. **No change** to `services.xserver.enable`, `services.pipewire`, `services.fprintd`, `services.bluetooth`, `users.users.jon`, `programs.zsh.enable`, `programs.nix-ld.enable`, `programs.kdeconnect.enable`, `nixpkgs.config.*`, `boot.*`, `networking.*`.

### `nix/home/linux.nix`

1. Add `home.packages` entries (linux-only):
   - `waybar`
   - `mako`
   - `hyprlock`
   - `hypridle`
   - `swaybg`
   - `grim`
   - `slurp`
   - `wlr-randr`
   - `xdg-desktop-portal-hyprland`
   - `xdg-desktop-portal-gtk`
   - `hyprland` (the package; `programs.hyprland.package` defaults to it but being explicit is safer)
2. Add:
   ```nix
   programs.hyprland = {
     enable = true;
     package = pkgs.hyprland;
     settings = { ... };
   };
   ```
3. Optionally enable `programs.waybar.enable = true` with a minimal `settings`. **Decision: skip for v1** — let waybar config live in `~/.config/waybar/` managed by chezmoi. Reason: waybar is heavily visual/personal; declarative config is a pain. Keep `waybar` in `home.packages` only.

### `nix/home/common.nix`

No change. `wl-clipboard`, `ghostty`, `fractalPatched`, `handy` are all compatible with both compositors.

### `chezmoi/dot_zshrc.tmpl`, `chezmoi/dot_tmux.conf.tmpl`

No change. They are already os-conditional.

### New file: `chezmoi/dot_config/waybar/config.jsonc` (optional, v1.1)

Only if the user wants a custom waybar. Skipped for v1; ship a default waybar style if any.

## Verification plan

1. **Flake evaluates clean** — `nix flake check --no-build` from the repo root. This catches type errors in `programs.hyprland.settings` early.
2. **Build succeeds** — `sudo nixos-rebuild build --flake .#diogenes` (no switch). Wait for completion; check for build failures in the derivation list.
3. **Switch** — `sudo nixos-rebuild switch --flake .#diogenes`. After completion:
4. **Reboot** — required because SDDM session list is read at boot, and `services.xserver.displayManager.sddm.enable` was not changed so this should be optional, but the home-manager systemd units need a re-login.
5. **At SDDM:** confirm both `Plasma` and `Hyprland` appear in the session menu. Pick `Hyprland`.
6. **Hyprland session starts.** Check:
   - `echo $XDG_SESSION_TYPE` → `wayland`
   - `echo $XDG_CURRENT_DESKTOP` → `Hyprland` (or unset)
   - `hyprctl monitors` shows display
   - `waybar` is visible at the top
   - `mako` is in the system tray / notification list
7. **Autostart sanity:**
   - `systemctl --user status handy` → active
   - `kdeconnect-cli --list-devices` shows phone (if phone on LAN)
   - `pactl info` shows pipewire running
8. **Lock + unlock:**
   - Trigger lock (e.g. via `hyprlock` or `loginctl lock-session`)
   - Confirm `hyprlock` appears
   - Unlock with password; fprint unlock is best-effort, document if it doesn't work
9. **App sanity:**
   - Open `ghostty` — confirm wayland native
   - Open `firefox` — confirm `MOZ_ENABLE_WAYLAND=1` works
   - Open `orca-slicer` — confirm Wayland
   - Open `kate` — confirm Wayland or XWayland
10. **Re-login into Plasma** — pick `Plasma` at SDDM, confirm nothing regressed (KDE Connect still works, fprintd login still works, autologin if we kept it).
11. **Switch back and forth** twice to confirm session selection is stable.

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `programs.hyprland.settings` schema drift in nixpkgs | Med | Low | Pinned to nixos-unstable; flake update + re-check is one command. |
| fprintd unlock under hyprlock requires extra PAM setup | Med | Low | v1 ships with password unlock; revisit if fprint matters. |
| Qt apps (kate, orca-slicer) render poorly under XWayland | Low | Low | `QT_QPA_PLATFORM=wayland;xcb` in `hyprland.conf` env tries native first. |
| waybar config drift — nix vs chezmoi | Med | Low | v1 ships with no waybar config; defaults are usable. |
| Plasma regresses when env vars leak | Med | Med | All compositor-specific env vars go into `hyprland.conf` `env {}`, not `home.sessionVariables`. |
| Dropping autologin is annoying | Med | Low | Easy to re-enable per-session via SDDM's `defaultSession`; documented in the README addendum. |
| SDDM session list doesn't show Hyprland | Low | Med | `programs.hyprland.enable` is the documented path; if it doesn't surface, manually add a `.desktop` file in `environment.packages`. |

## Rollback plan

All changes are inside `nix/` and `flake.nix`. Reverting the commit returns to the previous system. Until the user reboots into Hyprland for the first time, no system state changes. Once a Hyprland session has been started, no system-level service has been touched — only the user session. A `nixos-rebuild switch` reverting the change plus a reboot is sufficient.

## Open questions (resolved)

1. **Keep autologin?** ✅ Drop it for v1 (security), restore later.
2. **Default session after first install?** ✅ Plasma stays default.
3. **waybar in nix or chezmoi?** ✅ **In nix** (override of rec). Add `programs.waybar.enable = true` + declarative `settings` block in `nix/home/linux.nix`. Waybar config becomes source-of-truth in the flake.
4. **Screenshots / screen recording priorities?** ✅ Confirmed: `grim`+`slurp` for screenshots in v1, no screen recorder (defer `wf-recorder` / `obs-studio` to v1.1).
5. **Fingerprint unlock at hyprlock — do we need it for v1, or accept password?** ✅ Password for v1.
6. **Should `hyprland` package live in `nix/home/linux.nix` or `nix/home/common.nix`?** ✅ `linux.nix` (Linux-only).

## Resolved design updates from Q3 / Q4

### waybar config (Q3: in nix)

Replace the v1 "ship the binary only" stance with declarative config:

```nix
programs.waybar = {
  enable = true;
  package = pkgs.waybar;
  settings = [
    {
      layer = "top";
      position = "top";
      modules-left = [ "hyprland/workspaces" "hyprland/window" ];
      modules-right = [ "pulseaudio" "network" "battery" "clock" "tray" ];
      clock = {
        format = "{:%a %b %d  %H:%M}";
        tooltip-format = "<tt><small>{calendar}</small></tt>";
      };
      tray = { spacing = 10; };
    }
  ];
  style = ''
    * { font-family: monospace; font-size: 12px; }
    #workspaces button.focused { background: #88c0d0; color: #2e3440; }
  '';
};
```

This is the minimum viable setup; v1.1 can add per-module styling, mako, custom workspace names, etc.

### Screen recording deferred (Q4)

Q4 asked whether to ship a screen recorder in v1. Confirmed: **no recorder in v1**. Add only `grim` + `slurp` for screenshots. Future v1.1 candidates: `wf-recorder` (small, CLI), `wl-screenrec` (GPU), or `obs-studio` (heavy).

## Implementation dispatch plan

- Lane A — `@fixer` on `nix/home/linux.nix`: add hyprland package, `programs.hyprland`, `programs.waybar`, plus the mako/hyprlock/hypridle/portals/grim/slurp/swaybg/wlr-randr package list, plus `xdg.portal.config.hyprland = { default = [ "hyprland" "gtk" ]; }` so portals pick the right backend. Bounded, single owner.
- Lane B — `@fixer` on `nix/nixos/diogenes.nix`: drop `services.displayManager.autoLogin` block. Touches ~5 lines, single owner.
- Lanes A and B are **independent file scopes** → run in parallel as two `@fixer` tasks.
- Verification — orchestrator: `nix flake check`, `nixos-rebuild build`, then user runs `nixos-rebuild switch` + manual SDDM boot test.
