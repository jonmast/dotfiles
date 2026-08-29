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
- **Plasma out** (ADR 0002): drop plasma6 desktop manager and xserver; SDDM (wayland) remains with Hyprland-only entry. kwallet + kwallet-pam PAM wiring, portal-kde Secret routing, kdeconnect, kate all stay standalone. Re-check whether plasma-workspace is still needed in portal configPackages once Plasma is gone. **Amended during issue 02:** plasma-workspace is KEPT, but for the application menu (it is the sole provider of `plasma-applications.menu` + its `.directory` files), not for portals — the Secret interface comes from `kwallet.portal`. Also, the single-entry goal was deliberately relaxed to TWO entries: the plain `hyprland.desktop` is retained as an in-SDDM escape hatch with `defaultSession` preselecting the uwsm one. The X11 entry is gone. Dolphin, kbuildsycoca6 and KDE theming had to be declared explicitly — they were plasma6 side effects. See ADR 0002's amendments.
- **uwsm** (ADR 0003): system uwsm enabled, HM integration on; all Hyprland-scoped user services rebind hyprland-session.target → graphical-session.target. Landing order inside this work: add uwsm while Plasma still present and verify boot before removing Plasma. **Amended during issue 01:** the rebind is deferred to issue 02 — while Plasma still exists it would start waybar/mako/hypridle under Plasma, so services stay on hyprland-session.target, which `BindsTo=graphical-session.target` and so still stops cleanly on logout. **Done in issue 02:** the rebind has now happened; all five services bind directly to graphical-session.target. hyprland-session.target is retained solely to pull the graphical target up in the non-uwsm escape-hatch session. See ADR 0003's amendments.
- **Walker stack demotion** (CONTEXT.md): elephant + walker services remain solely for clipboard history; the launcher role moves to The Shell's menu via quickshell IPC.
- **Quickshell source**: upstream flake input pinned v0.3.1 with nixpkgs follows (nixpkgs unstable still at 0.3.0 which has a restart-kill race; PR #554917 pending). Drop the pin after nixpkgs bumps. **Done in issue 03:** the input resolves to rev `1a4716cde794a59928d9d9fc15f2afc7a95de360`, which is the v0.3.1 tag commit the research doc identified. nixpkgs was re-checked at lock time and is still on 0.3.0, so the pin is still earning its keep. Note the cost of the pin: nothing in it is cached, so every bump is a full local Qt-scale compile.
- **Bar parity, as actually built (issue 03)**: every waybar module maps onto a first-party Quickshell service, so no external polling survives except the DWT widget (see below). Three deliberate deviations from waybar, all commented at their call sites rather than left to be rediscovered:
  1. **Window title collapses when empty** instead of drawing a stub of padding, and elides at half the bar width instead of running underneath the right-hand modules.
  2. **Network module says "disconnected"** rather than waybar's default of repeating the interface name in red. The connected label is still the bare `{ifname}` waybar showed.
  3. **Tray collapses when empty**, same reasoning as the window title.
  4. **Bluetooth shows "BT" when the adapter is on with nothing connected**, matching waybar's actual output. `format-disconnected` is not a real waybar bluetooth key (`format-off`/`format-on`/`format-connected`/`format-disabled` are), so that config line never took effect and waybar fell through to `format` with an empty `{device_alias}`.
  Two waybar bugs were found in the parity diff and fixed rather than preserved: the audio icon ramp was inverted (waybar's shipped `format-icons` order put the loud icon at low volume — a bug in the config, not a deliberate choice), and battery colour followed CSS source order rather than severity (a battery charging at 10% was red). Both are severity-first in The Shell.
- **New system dependency: `services.upower.enable` (issue 03).** waybar's battery module read `/sys/class/power_supply` directly, so the bar has always shown a battery on a host with no UPower installed. Quickshell's battery service is UPower-only and fails quietly when the daemon is missing — `displayDevice` stays inert and the widget renders blank rather than erroring. Enabled in `nix/nixos/diogenes.nix`. Worth noting for the testing seams: this is invisible to `nix flake check`, and was only caught by running the shell against the live session before switching.
- **Two bars can run side by side, which makes the shell seam cheaper than the plan assumed.** `quickshell -p ./nix/home/quickshell` against the running session draws The Shell's bar directly under the live waybar, so parity can be diffed visually (`grim`) without switching the system or logging out. Config load errors are reported with file and line and the process exits non-zero, so this doubles as a QML typecheck. Recommended first step for issues 04-06 before any rebuild.
- **DWT widget shells out to `hyprctl`** and polls on waybar's old 5s interval. Not laziness: `Hyprland.dispatch()` only runs dispatchers, reading/writing a config option is `getoption`/`keyword`, and Quickshell 0.3.1 exposes no option accessor or change event for them. Using the same interface as the `$mod T` bind also makes the two paths impossible to drift apart. The JSON is parsed in QML, so the widget itself no longer needs `jq` — but `jq` stays installed because the keybind still uses it.
- **Known follow-ups folded in**: baloo disabled; XDG_MENU_PREFIX corrected at the systemd layer for Dolphin sycoca.

## Testing Decisions

Four seams, agreed with jon; a ticket is done when eval is clean AND its slice of the manual checklist passes:

1. **Eval seam** (agent-runnable): `nix flake check` / dry-build — module errors caught before any reboot.
2. **Boot seam** (human): SDDM lists one session; uwsm-launched Hyprland reaches a usable desktop.
3. **Session seam** (human, post-login): `systemctl --user` shows all expected services active under graphical-session.target; none lingering from retired targets. Until issue 02 collapses the indirection, they appear one level down under hyprland-session.target — check with `systemctl --user list-dependencies`. The leak test that matters is a logout→re-login cycle followed by `pgrep -a 'waybar|mako|hypridle|walker|elephant'` (want one of each), not a single-boot snapshot.
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
- Research doc records open gaps worth watching during implementation: ~~exact XDG_MENU_PREFIX value for NixOS~~ (resolved — see below), and whether quattro QML needs quickshell > 0.3.1 APIs (unlikely; validated rev predates it).
- **XDG_MENU_PREFIX resolved (2026-08-25):** the value is `plasma-`, because `plasma-applications.menu` from plasma-workspace is the only menu file on the system. uwsm otherwise derives `hyprland-` from the compositor name, which matches no file and empties the whole menu tree (`kbuildsycoca6 --menutest`: 0 entries vs 41). Fixed via `xdg.configFile."uwsm/env-hyprland"`, since uwsm force-exports the variable and would clobber `home.sessionVariables`. This was a live bug in the existing Hyprland session, independent of Plasma removal — and it means issue 02 must keep a menu file available once plasma-workspace's role is reconsidered.
