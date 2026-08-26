# Spec: Quickshell shell + Hyprland-only sessions on Diogenes

**Status:** ready-for-agent
**Owner:** jon
**Last updated:** 2026-08-23
**Companion docs:** `docs/research/omarchy4-quickshell.md` (primary-source research), ADR 0001–0004

## Problem Statement

Diogenes currently boots into one of two SDDM sessions: a full Plasma/KWin desktop or a Hyprland session held together by a bar/launcher/notification pile of separate daemons (waybar, walker, mako). The Plasma session exists only as a fallback yet drags in an entire second desktop; the Hyprland session has no polkit agent at all (GUI auth prompts silently fail) and leaks user services across logout. The desktop experience jon actually lives in — Hyprland — deserves to be the only session, running a coherent shell instead of a daemon pile.

## Solution

Hyprland becomes the single SDDM session, launched under uwsm. A self-written minimal Quickshell shell ("The Shell") replaces waybar, mako, and walker-as-launcher with one process providing the bar, launcher menu, notifications, volume/brightness OSDs, and a polkit agent. KDE software continues to run app-level (Dolphin, kate, kdeconnect, kwallet, portal-kde) without any Plasma session. The Lock stack stays on hyprlock/hypridle.

## User Stories

1. As jon, when I power on Diogenes, I want SDDM to offer exactly one session entry (Hyprland), so that login is unambiguous.
2. As jon, I want my Hyprland session launched via uwsm, so that all session services stop cleanly on logout and nothing lingers into the next login.
3. As jon, I want a bar showing workspaces and the focused window title, so that orientation matches what I have today.
4. As jon, I want a DWT toggle widget in the bar, so that I can flip disable-while-typing without remembering keybind state.
5. As jon, I want bluetooth, audio, network, battery, clock (with calendar tooltip), and system tray widgets in the bar, so that Bar parity is preserved.
6. As jon, I want `$mod D` to open an application launcher menu, so that app launching is no slower than walker was.
7. As jon, I want `$mod SHIFT V` clipboard history unchanged, so that my paste-from-history muscle memory survives.
8. As jon, I want notifications rendered by The Shell, so that mako is gone and notification behavior is consistent with the rest of the UI.
9. As jon, I want volume and brightness OSDs when I press media keys, so that I get visual feedback for hardware keys.
10. As jon, I want a working GUI polkit authentication prompt, so that privilege elevation dialogs actually appear under Hyprland.
11. As jon, I want fingerprint-or-password unlock at the lock screen exactly as today, so that the Lock stack keeps its proven behavior.
12. As jon, I want idle → lock → dpms-off → suspend timers preserved, so that power behavior doesn't regress.
13. As jon, I want Dolphin's file chooser and Open With menus working, so that KDE apps behave without Plasma.
14. As jon, I want kwallet unlocked by my SDDM login password, so that Chrome/mpv secret access keeps working.
15. As jon, I want kdeconnect functional, so that phone integration doesn't depend on Plasma.
16. As jon, I want the screenshot keybind (`Print` → grim/slurp/wl-copy) untouched, so that capture workflow is stable.
17. As jon, I want baloo disabled and Dolphin's menu prefix correct, so that no orphaned Plasma indexing/menu services misbehave.
18. As jon, I want each risky step landable separately with a working fallback, so that a bad rebuild never strands me at a black screen.
19. As future-jon, I want the pinned quickshell version droppable once nixpkgs ships ≥ 0.3.1, so that flake hygiene is a one-line change.
20. As future-jon, I want every deviation from omarchy quattro recorded, so that nobody "fixes" deliberate choices later.

## Implementation Decisions

- **Own minimal Shell** (ADR 0001): QML tree written by us, HM-deployed as real files; omarchy quattro QML is read-only reference — no omarchy runtime, scripts, or vendored code.
- **Scope tier T3**: bar + menu launcher + notifications + vol/brightness OSDs + polkit agent. Lock/idle explicitly excluded (ADR 0004).
- **Bar parity** first release: same modules left/right, same Nord palette, calendar tooltip included.
- **Plasma out** (ADR 0002): drop plasma6 desktop manager and xserver; SDDM (wayland) remains with Hyprland-only entry. kwallet + kwallet-pam PAM wiring, portal-kde Secret routing, kdeconnect, kate all stay standalone. Re-check whether plasma-workspace is still needed in portal configPackages once Plasma is gone.
- **uwsm** (ADR 0003): system uwsm enabled, HM integration on; all Hyprland-scoped user services rebind hyprland-session.target → graphical-session.target. Landing order inside this work: add uwsm while Plasma still present and verify boot before removing Plasma.
- **Walker stack demotion** (CONTEXT.md): elephant + walker services remain solely for clipboard history; the launcher role moves to The Shell's menu via quickshell IPC.
- **Quickshell source**: upstream flake input pinned v0.3.1 with nixpkgs follows (nixpkgs unstable still at 0.3.0 which has a restart-kill race; PR #554917 pending). Drop the pin after nixpkgs bumps.
- **Known follow-ups folded in**: baloo disabled; XDG_MENU_PREFIX corrected at the systemd layer for Dolphin sycoca.

## Testing Decisions

Four seams, agreed with jon; a ticket is done when eval is clean AND its slice of the manual checklist passes:

1. **Eval seam** (agent-runnable): `nix flake check` / dry-build — module errors caught before any reboot.
2. **Boot seam** (human): SDDM lists one session; uwsm-launched Hyprland reaches a usable desktop.
3. **Session seam** (human, post-login): `systemctl --user` shows all expected services active under graphical-session.target; none lingering from retired targets.
4. **Shell seam** (human, interactive): keybind/menu/clipboard/notifications/OSD/polkit/bar-parity checklist per the user stories above.

Good tests here assert external behavior only (what boots, what appears, what responds) — never module internals. Prior art: the manual verification approach of the previous plan doc (`docs/plans/hyprland-as-alternate-to-kwin.md`).

## Out of Scope

- Any UI redesign beyond Bar parity (retheming comes later).
- Shell-provided lock screen or idle management (ADR 0004).
- Vendoring omarchy code or depending on omarchy binaries.
- Touching the chezmoi/macOS side of the repo.
- hyprlang→Lua config migration (existing v1.1 idea; unrelated).
- Autologin changes.

## Further Notes

- Working tree on master carries unrelated WIP; cut a fresh feature branch for this work.
- Research doc records open gaps worth watching during implementation: exact XDG_MENU_PREFIX value for NixOS, and whether quattro QML needs quickshell > 0.3.1 APIs (unlikely; validated rev predates it).
