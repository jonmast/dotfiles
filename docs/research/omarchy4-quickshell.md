# Omarchy 4 "Quattro" — Quickshell Desktop Shell: Research for Adoption on NixOS + chezmoi

**Researcher:** @librarian (read-only investigation against primary sources)
**Date:** 2026-08-22
**Target:** User runs Hyprland via Nix flakes + chezmoi dotfiles. Wants to adopt the Omarchy 4 Quickshell shell while keeping KDE apps, and dropping the KWin/SDDM Plasma session option.
**Status:** Research only — no files modified except this document.

> **Method note.** All Omarchy claims below were verified by cloning the primary repo
> `github.com/basecamp/omarchy` (default branch `quattro`, version file `4.0.0.alpha`)
> to `/tmp/opencode/omarchy` and reading source. Quickshell packaging claims were verified
> against nixpkgs, the upstream Quickshell flake/BUILD.md, and the home-manager module.
> KDE-section claims are a mix of primary evidence and widely-reported community
> behaviour (marked where applicable).

---

## TL;DR

- Omarchy 4 ("Quattro") replaced the entire v3 desktop UI stack — **Waybar, Walker, Mako,
  SwayOSD, hyprlock, hypridle, swaybg, and polkit-gnome** — with **one long-lived
  Quickshell process** called `omarchy-shell`. The bar, launcher/menu, notifications,
  OSDs, panels, lock screen, and polkit agent are all now **Quickshell plugins inside a
  single `quickshell` instance**.
- The shell source lives in the repo at **`shell/`** (`shell/shell.qml` is the `ShellRoot`
  entrypoint), first-party plugins in **`shell/plugins/`**, services in `shell/services/`,
  and the user-configurable state in **`~/.config/omarchy/shell.json`**.
- Hyprland autostarts it via **`omarchy-launch-shell`** from `default/hypr/autostart.lua`
  (Hyprland `start` event → `exec_cmd("omarchy-launch-shell")`). There is **no separate
  hypridle/hyprlock/notification daemon** — all run in the shell.
- On Nix: **`pkgs.quickshell` exists in nixpkgs** (v0.3.0 on `nixos-unstable`), the upstream
  repo has an **embedded flake** (`quickshell.packages.<system>.default`), and **home-manager
  ships a `programs.quickshell` module** (with optional `systemd` service + `activeConfig`).
- Warning relevant to the user: **Quickshell is a whole desktop shell, not a config file.**
  Omarchy's shell is deeply coupled to Omarchy's own theme system, `OMARCHY_PATH`, PAM
  service names, and the `omarchy-*` CLI. You cannot drop "just the bar QML" in without the
  Omarchy machinery. Plan for either (a) shipping Omarchy's shell wholesale, or (b) writing
  your own Quickshell config against the same primitives (see §6).

---

## 1. Omarchy 4 vs Omarchy 3 — what changed, and what "Quickshell stuff" is

### 1a. The delta (primary source: the v4.0.0 release notes)

The official release notes at `github.com/basecamp/omarchy/releases/tag/v4.0.0` state
explicitly (Quattro's "Headline Features"):

> Reimagine the entire desktop shell in [Quickshell](https://quickshell.org/).
> ... Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle, swaybg, and polkit-gnome are all
> gone, replaced by one coherent, fully-themed, IPC-scriptable shell.

So **v3's stack was**: Waybar (bar) + Walker (launcher) + Mako (notifications) +
SwayOSD (OSDs) + hyprlock (lock) + hypridle (idle) + swaybg (wallpaper) +
polkit-gnome (auth agent). **v4 replaced every one of those with in-shell plugins.**

### 1b. Which components are Quickshell-based (verified in repo)

From `shell/plugins/README.md` (first-party plugin table) and `shell/README.md`, the
following are **all Quickshell plugins inside the single `omarchy-shell` process**:

| Plugin | id | kind | entry point |
|---|---|---|---|
| Bar | `omarchy.bar` | `bar` | `bar/Bar.qml` |
| Omarchy menu / launcher | `omarchy.menu` | `menu`, `bar-widget` | `menu/Menu.qml`, `menu/BarWidget.qml` |
| Notifications daemon | `omarchy.notifications` | `service` | `notifications/Service.qml` |
| Clipboard manager | `omarchy.clipboard` | `overlay` | `clipboard/Clipboard.qml` |
| Emoji picker | `omarchy.emojis` | `overlay` | `emojis/Emojis.qml` |
| Image picker | `omarchy.image-picker` | `overlay` | `image-picker/ImagePicker.qml` |
| Lock screen | `omarchy.lock` | `service` | `lock/Service.qml` |
| OSD (vol/brightness/media) | `omarchy.osd` | `panel` | `osd/Osd.qml` |
| Polkit agent | `omarchy.polkit` | `service` | `polkit/PolkitAgent.qml` |
| Reminders | `omarchy.reminders` | `overlay` | `reminders/ReminderFlow.qml` |
| Panels (Audio/Bluetooth/Monitor/Network/Power/Weather) | `omarchy.audio|bluetooth|monitor|network|power|weather` | `bar-widget` | `panels/*/Panel.qml` |
| Services (Media/Battery/Idle/Night light) | `omarchy.media|battery|idle|nightlight` | `service` | `services/*/Service.qml` |

`shell/README.md` summarises the architecture:

> `omarchy-shell` is a single long-running Quickshell instance that hosts the Omarchy
> desktop. Hyprland autostart launches one shell per graphical session; everything else —
> the bar, background switcher, panels, and overlays — runs **inside** the shell as a plugin.

The bar renders via **layer-shell** panels: `shell/plugins/bar/Bar.qml` uses
`PanelWindow { ... }` components (verified: `BarPanel`, `DragGhostPanel`,
`BarMoveGhostPanel` are all `PanelWindow`).

The PR that landed this is **#5856 "Omarchy goes Quickshell"**
(`github.com/basecamp/omarchy/pull/5856`, merged into the `quattro` branch):
">This PR migrates Omarchy's desktop UI stack from Waybar + Mako to a Quickshell-based
> 'omarchy-shell' (bar + notifications + menu + settings)... Remove legacy Waybar/Mako
> configs and migrations."

### 1c. Where quickshell configs live in the omarchy repo

```
shell/
  shell.qml                 entry point (ShellRoot), hosts plugins
  services/
    PluginRegistry.qml      discovers/validates plugins, enabled state from shell.json
    BarWidgetRegistry.qml   unified registry for bar widgets (1p + 3p)
  plugins/                  first-party plugins (table above)
  Commons/                  shared Qt Quick singletons (Color, Style, Util)
  Ui/                       shared UI components
config/omarchy/shell.json   shipped default shell state (fresh-install shell.json)
default/hypr/autostart.lua  Hyprland autostart that launches the shell
default/omarchy/omarchy-menu.jsonc  default menu definition (JSONC)
bin/omarchy-launch-shell    wrapper that starts quickshell -p $OMARCHY_PATH/shell
bin/omarchy-shell           IPC wrapper (qs ipc ...) — does NOT start the shell
install/omarchy-base.packages  lists `quickshell` and `uwsm` as base packages
```

---

## 2. How Omarchy structures the Quickshell config

Verified from `shell/` source:

- **Entry point** — `shell/shell.qml` is a `ShellRoot {}`. It imports
  `QtQuick`, `QtQml.Models`, `Quickshell`, `Quickshell.Io`, `qs.Commons`, and the plugin
  dirs. It instantiates shared services (`PluginRegistry`, `BarWidgetRegistry`,
  `AppLibrary`) and injects them into plugins (rather than relying on singleton imports,
  which do not share state across relative-path imports).
- **Plugin discovery / manifests** — every plugin ships a `manifest.json`
  (`schemaVersion`, `id`, `kinds` in `bar-widget|panel|overlay|menu|service|bar`,
  `entryPoints`, bar-widget metadata). Full schema documented in
  `shell/services/PluginRegistry.qml`; human summary in `shell/README.md`.
- **Configuration file** — Omarchy uses **`~/.config/omarchy/shell.json`** for all shell
  state: the bar `id`/`position`/`layout`, per-widget settings, and the enabled-plugin
  list. Defaults come from `config/omarchy/shell.json`; once the user customizes anything,
  the user file is authoritative (no deep-merge). Menus additionally take a JSONC
  definition (`default/omarchy/omarchy-menu.jsonc` + user extensions in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`). Theme/geometry overrides can live in
  `~/.config/omarchy/shell.toml` (merged over the active theme, watched live).
- **IPC** — the shell exposes a `shell` IPC target via Quickshell IPC
  (`bin/omarchy-shell` → `qs ipc -p $OMARCHY_PATH/shell call ...`). Methods:
  `ping`, `summon <id> <payloadJson>`, `hide`, `toggle`, `call`, `rescanPlugins`,
  `reloadConfig`, `setPluginEnabled`, `listPlugins`. Direct:
  `quickshell ipc -p $OMARCHY_PATH/shell call shell ping`.
- **Themes** — shell reads the live Omarchy palette at
  `~/.config/omarchy/current/theme/colors.toml` (also confirmed by the community config
  repo `github.com/bjarneo/quickshell`, which reads the same path). Hyprland enforces
  theme corners/colours via `default/hypr/looknfeel.lua`.
- **Process lifecycle** — Hypriand launches the shell with
  `quickshell -n -p "$OMARCHY_PATH/shell"` via `omarchy-launch-shell` (which wraps it in
  `systemd-cat -t omarchy-shell` and disables Quickshell's own file-watcher/reload so a
  package upgrade can't hot-reload against a half-written tree). 
  `bin/omarchy-shell` is only an IPC client; it does not start the shell.

**Key architectural takeaway for the user:** Omarchy's config is a *host process + plugin
directory*, not a single `config.qml`. `OMARCHY_PATH` is the repo checkout path (set by
the `uwsm` session env), and the shell is launched with `-p $OMARCHY_PATH/shell`.

---

## 3. Quickshell requirements + Nix/NixOS packaging

### 3a. Runtime/build dependencies (primary: upstream `BUILD.md`, nixpkgs `package.nix`)

From the upstream `quickshell/quickshell` `BUILD.md` (git.outfoxxed.me):
- Base: `cmake`, Qt 6 (`qt6base`, `qt6declarative`), `libdrm`, `qtshadertools` (build),
  `spirv-tools` (build), `pkg-config` (build), `cli11` (static).
- **At least Qt 6.6 is required.** Quickshell relies on **private Qt APIs** and must be
  rebuilt against the matching Qt release (ABI mismatch → crashes). Since Qt 6.10,
  QtWaylandClient moved into QtBase (the nixpkgs/quickshell flake reflects this: the
  qtwayland dependency drops when `qt >= 6.10`).
- Wayland: `qt6wayland` (≤ 6.9), `wayland`(libwayland-client), `wayland-scanner` (build),
  `wayland-protocols`. **Wlroots layer-shell** (`zwlr-layer-shell-v1`) is built in
  (needed for bars/overlays/backgrounds) and **Hyprland integration** (IPC, global
  shortcuts, toplevel export) is a compile option, both ON by default.
- Optional but enabled in nixpkgs: `pipewire` (audio mixer), `pam` (lock/PAM), `glib` +
  `polkit` (polkit agent), Vulkan headers (screencopy).

nixpkgs `pkgs/by-name/qu/quickshell/package.nix` (v0.3.0) confirms the concrete set:
`qt6.qtbase, qt6.qtdeclarative, qt6.qtwayland, qt6.qtsvg, cli11, wayland,
wayland-protocols, libdrm, libgbm, cpptrace, jemalloc, libxcb, pam, pipewire, glib,
polkit` (+ build inputs `cmake, ninja, qt6.qtshadertools, spirv-tools, vulkan-headers,
wayland-scanner, qt6.wrapQtAppsHook, pkg-config`).
License LGPL-3.0, `mainProgram = "quickshell"`, maintainer `outfoxxed`.

### 3b. Nix packaging (verified against primary sources)

- **nixpkgs package:** `pkgs.quickshell` exists (`pkgs/by-name/qu/quickshell/package.nix`),
  present on `nixos-unstable`, `nixpkgs-unstable`, and `release-26.05` branches at
  **v0.3.0** (as fetched). *Note:* upstream Quickshell released **0.3.1 on 2026-08-20**;
  verify whether nixpkgs has since bumped past 0.3.0 before pinning (for Omarchy you'll
  likely be on the upstream flake `master` anyway).
- **Upstream flake:** the Quickshell repo ships an embedded flake, usable from either
  mirror:
  - `git+https://git.outfoxxed.me/outfoxxed/quickshell` (canonical)
  - `github:quickshell-mirror/quickshell` (GitHub mirror)
  Docs (quickshell.org/docs/guide/install-setup) recommend:
  ```nix
  inputs.quickshell = {
    url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
    # IMPORTANT: follow nixpkgs to avoid mismatched system deps -> crashes.
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```
  Exposes `quickshell.packages.<system>.default` (and an overlay,
  `self.overlays.default`, per `flake.nix`). The flake also notes the Qt-version warning:
  even on Nix, keep quickshell and its Qt build inputs on the **same nixpkgs revision** as
  the rest of the system.
- **Home-Manager module:** home-manager ships **`programs.quickshell`**
  (`modules/programs/quickshell.nix`, e.g. `release-25.11` branch). Key options (verified
  from the module source):
  - `enable`, `package` (defaults `pkgs.quickshell`, nullable)
  - `configs` = attrsOf path → copied to `~/.config/quickshell/<name>`
  - `activeConfig` (default `null`) → when set, starts `quickshell --config <name>`;
    when `null`, uses `$XDG_CONFIG_HOME/quickshell`
  - `systemd.enable` + `systemd.target` (default
    `config.wayland.systemd.target`, example `hyprland-session.target`) → wires a
    `systemd.user.services.quickshell` unit.
  There is also a (currently open) upstream PR to add a home-manager module directly to
  the quickshell flake: `quickshell-mirror/quickshell#2` "nix: add home-manager module".
- The **Illogical-Impulse / end-4** Hyprland config (`github.com/end-4/dots-hyprland`)
  is the canonical community example of consuming `quickshell` via the flake inside a
  home-manager config (`sdata/dist-nix/home-manager/home.nix` imports
  `./quickshell.nix { inherit pkgs quickshell; }`). Helpful reference, not a primary
  source for quickshell itself.

> **Caveat for this repo:** nixpkgs `quickshell` 0.3.0 and Omarchy's `quattro` shell may
> target a newer commit of Quickshell master. Because Quickshell is pre-1.0 with a
> changing API (`Quickshell.shellRoot` → `Quickshell.shellDir`, Qt 6.10 private-module
> requirement, etc.), pin quickshell to whatever revision Omarchy's maintained against and
> follow its nixpkgs.

---

## 4. How Omarchy wires Quickshell into Hyprland

### 4a. Autostart (primary: `default/hypr/autostart.lua` + `bin/omarchy-launch-shell`)

Everything runs on the Hyprland `start` event. From `default/hypr/autostart.lua`:

```lua
hl.on("hyprland.start", function()
  -- systemd/dbus env propagation (needed for session services)
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("omarchy-launch-shell")          -- <-- starts the Quickshell host
  hl.exec_cmd("omarchy-provision-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))
  hl.exec_cmd(o.launch("udiskie --automount --no-notify --no-tray"))
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
```

`omarchy-launch-shell` execs
`QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 systemd-cat -t omarchy-shell --
quickshell -n -p "$OMARCHY_PATH/shell"` and supervises it (restart on compositor output
reconfig races). **Hyperland is expected to run under uwsm** (Omarchy installs `uwsm` as a
base package — `install/omarchy-base.packages`); `OMARCHY_PATH` comes from the session env,
and Hyprland's configs are Lua (`default/hypr/*.lua`, including `looknfeel.lua` which
enforces `allow_session_lock_restore = true` so a fresh shell can re-acquire the session
lock).

### 4b. hyprlock / hypridle / swaybg — all gone

- **No `hyprlock`** — the lock screen is the `omarchy.lock` plugin using Quickshell's
  native `WlSessionLock` + two PAM services (`omarchy-lock-password`,
  `omarchy-lock-fingerprint`) for password/fingerprint. `ShellReload` note in the plugin
  README: "Matches hyprlock" only for visual parity (fingerprint icon position).
- **No `hypridle`** — idle is the `omarchy.idle` service plugin; timings live top-level in
  `shell.json` (`idle.screensaver`, `idle.lock`, in seconds). The `SUPER + CTRL + I`
  binding toggles "locking on idle" (`default/hypr/bindings/utilities.lua`).
- **No `swaybg`** — the background is the `omarchy.background` plugin (layer-shell panel).
- Lock binding: `SUPER + CTRL + L` → `omarchy-system-lock`; lid switch →
  `omarchy-system-lid-close` / `omarchy-hyprland-monitor-clamshell`.

### 4c. Notification daemon (primary: `docs/notifications.md`)

The shell **is** the notification daemon:
> The shell is the notification daemon: `shell/plugins/notifications/Service.qml` hosts a
> Quickshell `NotificationServer` that claims `org.freedesktop.Notifications` on the
> session bus. **There is no dunst or mako** — anything that speaks the freedesktop
> notification protocol (notify-send, libnotify apps, Chromium web apps) lands in the shell.

Toast persistence: mirrored to `~/.local/state/omarchy/notifications/`, history trimmed to
newest ten, survive shell restarts. DND persisted in
`~/.local/state/omarchy/notifications.json`.

### 4d. App launcher (primary: `shell/plugins/README.md` + bindings)

**No fuzzel, no rofi, no walker.** The launcher is the `omarchy.menu` plugin, summoned via
IPC into the already-running shell (`omarchy-shell shell summon omarchy.menu ...`). The
menu definition is JSONC, it does fuzzy/acronym matching against a live app-index, and it
doubles as the unified command launcher:
- `SUPER + SPACE` — search apps + the Omarchy command palette
- `SUPER + ALT + SPACE` — apps-only menu
Menu bindings live in `default/hypr/bindings/utilities.lua` (e.g. `SUPER + CTRL + ALT + D`
toggles the clock panel, `XF86PowerOff` → power menu, media keys call `omarchy-shell media
...`).

### 4e. Native features replacing the removed tools — summary

| v3 tool | v4 replacement | verified in |
|---|---|---|
| Waybar | `omarchy.bar` (Quickshell bar plugin, layer-shell) | `shell/plugins/bar/Bar.qml`, `shell/README.md` |
| Walker | `omarchy.menu` (merged launcher + command palette) | `shell/plugins/menu/Menu.qml` |
| Mako | `omarchy.notifications` service | `docs/notifications.md` |
| SwayOSD | `omarchy.osd` (vol/brightness/media OSD) | `shell/plugins/osd/Osd.qml` |
| hyprlock | `omarchy.lock` (WlSessionLock + PAM) | `shell/plugins/lock/Service.qml` |
| hypridle | `omarchy.idle` service | `shell/plugins/services/...`, `shell.json` |
| swaybg | `omarchy.background` plugin | `shell/plugins/background/` |
| polkit-gnome agent | `omarchy.polkit` (Quickshell PolkitAgent) | `shell/plugins/polkit/PolkitAgent.qml` |

---

## 5. Removing a KWin/Plasma session from SDDM while keeping KDE apps

> **"Keep KDE apps under Hyprland" is the well-trodden part.** The apps you name —
> **Dolphin, Konsole, kdeconnect** — are Qt6/Frameworks apps that run fine under a
> Wayland compositor with `qtwayland` present. What they want is a *session* that provides:
> (a) the freedesktop notification + portal services, (b) a `kdeglobals`/`kde`-theme
> (colorschema), and (c) QML/font/icon paths. Under Omarchy those are provided by the shell
> (notifications), portals, and installed framework packages. What you do **not** need is
> the Plasma workspace (kwin, plasma-desktop, plasmashell) — those are what pull in the
> heavy KWin/SDDM session.

### 5a. KDE daemons / background services that matter (and which don't)

| Service | What it is | Under Hyprland |
|---|---|---|
| `kded6` | KDE "daemon for session services"; launches small background tasks on demand (from `libkdeinit`/`kded`) | Not strictly required for the named apps; expected to be started by `startplasma`/session — it is NOT started by a bare Hyprland session. Some KDE integration (e.g. some KRunner plugins, modemmanager) depends on it, but Dolphin/Konsole/kdeconnect do not. |
| `kactivitymanagerd` | Tracks user "activities"; used for recent-files / session restore | Optional; useful for Dolphin/Kate recent-files and "Open With" ordering. Runs as a standalone daemon — you can start it under Hyprland if you want activity tracking, but it is not required to run the apps. |
| `baloo` / `baloo_file_extractor` | File indexer/search (a dependency pulled in by Dolphin) | Commonly **disabled** under Hyprland (`balooctl6 disable`) to avoid background indexing of a desktopless filesystem. Optional. |
| `kwalletd6` | Password wallet (KWallet) | Needed if you rely on KWallet (e.g. dolphin sftp/ssh passphrase, KDE-integrated passwords, some konsole/KIO flows). Start under Hyprland if you use it with `kwallet-query`; it runs by D-Bus activation. |
| `xsdg-desktop-portal-kde` (kdePackages) | KDE file/dialog/portal backend | **Recommended keep** if you want Dolphin as the GTK/portal file picker and KDE dialogs. `kdePackages.xdg-desktop-portal-kde` works alongside `xdg-desktop-portal-hyprland`. (See `github.com/hyprwm/Hyprland/discussions/4988`: set `XDG_DESKTOP_PORTAL`/portal `[preferred]` `org.freedesktop.impl.portal.FileChooser=kde`.) |
| `kdeconnect` / `kdeconnect-kde` | Phone integration daemon | Runs standalone, Wayland-native, tray icon; requires no Plasma. Keep. |
| `kglobalaccel`, `kconfig`, `ksvg`, `ki18n`, `solid` | Frameworks libraries | These are **libraries**, pulled in as dependencies of the apps; installed via nixpkgs automatically. No daemon work needed. |
| `klaunch`/`kil`/kinit (kdeinit6) | KDE process-spawn infra | Optional; Qt apps often work fine without kdeinit. Ensure `QT_PLUGIN_PATH`/`QML2_IMPORT_PATH` and `KDEDIRS` point at the nix profile if file dialogs/icons are missing. |

**Canonical/evidence:**
- Lorenzo Bettini's widely-cited write-up ("Hyprland and KDE Applications",
  lorenzobettini.it, 2024) documents using Dolphin/Konsole/Kate/Gwenview/Okular under
  Hyprland: install the KDE apps + `breeze-icons`, and **`balooctl6 disable`** to avoid
  useless indexing. He also hit the Dolphin "empty Open With" sycoca problem and fixed it
  by rebuilding the KDE menu cache (`kbuildsycoca6`).
- The root cause of that Dolphin/sycoca issue is documented on
  `github.com/hyprwm/Hyprland/discussions/13984`: **`XDG_MENU_PREFIX`**. Under
  Systemd/uwsm-style sessions, `kactivitymanagerd`/Dolphin inherit `XDG_MENU_PREFIX`
  (e.g. `hyprland-` when set by the session manager) and can't find the matching
  `*-applications.menu`, corrupting the sycoca cache → empty Open With. **This is the
  single most important gotcha for keeping Dolphin usable under Hyprland.** Fix: set
  `XDG_MENU_PREFIX` (e.g. `arch-` or whatever your distro's menu file is) at the *systemd
  layer* via `~/.config/environment.d/`, *not* via `hyprland.conf` `env =` (which does not
  propagate to systemd user services). On NixOS this means an `environment.etc` or
  home-manager `xdg.configFile "environment.d/..."` entry, and/or ensuring a valid
  `applications.menu` exists (e.g. install the desktop menu / `xfce`-style menu or set the
  prefix to a present one). *Note: I verified this against the Hyprland discussion and the
  KDE/dolphin behaviour, but the exact accepted menu-prefix value is distro-specific and
  should be confirmed on this user's Coninux/NixOS setup.*
- `kded6` description: Debian packages page (`packages.debian.org/sid/kded6`): "Extensible
  daemon for providing session services... performs a number of small tasks... some started
  on demand." It is session-manager-driven; a bare Hyprland session won't auto-start it,
  which is generally fine for the named apps.

### 5b. Dropping the SDDM Plasma session option (issues for this repo)

The existing plan at `docs/plans/hyprland-as-alternate-to-kwin.md` already anticipates
coexistence (Plasma stays default, Hyprland as alternate; SDDM session picker). The
research-relevant extensions for "drop the KWin/Plasma option entirely":

- **KWin/Plasma is enabled by `services.desktopManager.plasma6.enable = true`** (that is
  what pulls in kwin, plasmashell, plasma-workspace, the `plasma6.service` and the
  `plasma` SDDM session file). Removing the Plasma *session option* means removing that
  module (and its SDDM session file), **not** removing individual KDE apps.
- **You can keep the individual KDE apps** (`kdePackages.dolphin`, `kdePackages.konsole`,
  `kdePackages.kdeconnect-kde`, etc.) in `home.packages` / `environment.systemPackages`
  **without** `desktopManager.plasma6`. Backing services can be started selectively under
  Hyprland: `kwalletd6` (by D-Bus activation when apps need it), optionally
  `kactivitymanagerd`, plus `kdePackages.xdg-desktop-portal-kde` for KDE portal/file-
  picker behaviour. Skip `baloo` (or disable it).
- **Watch for autostart leakage:** when Plasma is not selected as the SDDM session,
  Plasma's `.desktop` autostart entries are normally keyed to the `plasma` session or
  `XDG_CURRENT_DESKTOP=KDE`; a bare Hyprland session (`XDG_CURRENT_DESKTOP=Hyprland`)
  should not trigger them. Community reports (e.g. Arch BBS "Koi starts Plasma stuff when
  running Hyprland") show that third-party session managers can still spawn Plasma bits;
  the robust fix is `NotShowIn=Hyprland` / `Hidden=true` on offending autostart entries.
  Be deliberate about what `XDG_CURRENT_DESKTOP` you export so KDE apps pick the right
  portal/theme but Plasma isn't autostarted.
- **PAM for the in-shell lock:** Omarchy uses its own PAM services
  (`omarchy-lock-password` / `omarchy-lock-fingerprint`); on NixOS these need PAM entries
  in the system config (analogous to the existing `security.pam.services.sddm.fprintAuth`
  and the plan's mention of `hyprlock` PAM). If you keep fprintd, wire a PAM service for
  the shell lock.

---

## 6. Adoption guidance for /home/jon/.dotfiles (from the research)

These are synthesis recommendations; **verify each before acting** — reach out if you want
me to drill into any of them.

1. **Don't try to transplant "just the bar."** Omarchy's shell is a full desktop host with
   hard dependencies on `OMARCHY_PATH`, its `manifest.json` plugin registry, its
   `shell.json` state file, its theme pipeline, and the `omarchy-*` CLI. Two viable paths:
   - **(A) Ship Omarchy's shell wholesale** (vendored subdir or flake input of
     `basecamp/omarchy` at `quattro`), plus the `omarchy-*` bin wrappers it calls from
     `exec_cmd`, and set `OMARCHY_PATH`. Heaviest, most "just works", but drags in Omarchy
     opinion and its first-run/provisioning/menus.
   - **(B) Write your own minimal Quickshell config** using the same primitives Omarchy
     uses (`.qml` importing `Quickshell`, `PanelWindow` for layer-shell bar/OSD,
     `NotificationServer` for notifications, `WlSessionLock` + PAM for lock). Start from
     Omarchy's `shell/shell.qml` + plugin QML as *reference*, keeping only what you want.
     Lighter, but more work and you maintain it. This fits the chezmoi approach (QML as
     dotfiles) but Quickshell configs are code, not config data — chezmoi templating is
     fine, just don't expect declarative Nix options for every widget.
2. **Nix wiring (both paths):** add quickshell via the **upstream flake with
   `inputs.nixpkgs.follows`** (to lock Qt ABI) or `pkgs.quickshell` from a nixpkgs the
   rest of the system is pinned to — never mix. home-manager's `programs.quickshell`
   module can install the package and (optionally) run it as a systemd user service bound
   to `hyprland-session.target`. Note **Qt ABI coupling is the top failure mode**: keep
   quickshell, its Qt build inputs, and Hyprland on the same nixpkgs revision.
3. **Dropping the Plasma session:** remove `services.desktopManager.plasma6.enable` (and
   the SDDM Plasma session), keep KDE apps as packages, and start the minimal KDE support
   set under Hyprland: `kdePackages.xdg-desktop-portal-kde`, `kwalletd6` (only if you use
   KWallet), optionally `kactivitymanagerd`; **disable baloo** (`balooctl6 disable`) and
   **fix `XDG_MENU_PREFIX` at the systemd layer** so Dolphin's "Open With"/sycoca cache
   stays valid. Ensure `notify-send` works — under Omarchy the in-shell
   `NotificationServer` claims `org.freedesktop.Notifications`.
4. **Plan update:** the existing `docs/plans/hyprland-as-alternate-to-kwin.md` was written
   for a Waybar+Mako+hyprlock/hypridle v1. If you go Quickshell, that plan's
   `exec-once` list changes materially (no `waybar`, no `mako`, in-shell OSD/lock/idle).
   This research file can feed a revision.

---

## Source map (primary)

| Claim | Source |
|---|---|
| v4 replaces Waybar/Walker/Mako/SwayOSD/hyprlock/hypridle/swaybg/polkit-gnome | `github.com/basecamp/omarchy` → Releases → `v4.0.0` notes; PR #5856 "Omarchy goes Quickshell" |
| Shell plugin architecture, plugin table, IPC contract, shell.json | repo `shell/README.md`, `shell/plugins/README.md`, `shell/shell.qml`, `shell/services/PluginRegistry.qml` |
| Notification daemon = in-shell, no mako/dunst | repo `docs/notifications.md`, `shell/plugins/notifications/Service.qml` |
| Hyprland autostart (`exec_cmd("omarchy-launch-shell")`) | repo `default/hypr/autostart.lua`, `bin/omarchy-launch-shell` |
| Lock = in-shell `WlSessionLock` + PAM | repo `shell/plugins/lock/Service.qml`, `shell/plugins/lock/LockView.qml`, `plugins/README.md` |
| Polkit = in-shell Quickshell PolkitAgent | repo `shell/plugins/polkit/PolkitAgent.qml`, `plugins/README.md` |
| quickshell base packages list | repo `install/omarchy-base.packages` (lines ~112 `quickshell`, ~136 `uwsm`) |
| quickshell deps / Qt 6.6+ / private-Qt / layer-shell / Hyprland module | upstream `git.outfoxxed.me/quickshell/quickshell` → `BUILD.md`, `CMakeLists.txt`, flake.nix; `quickshell.org/docs/guide/install-setup` |
| nixpkgs `pkgs.quickshell` v0.3.0 (build deps, LGPL, mainProgram) | `NixOS/nixpkgs` → `pkgs/by-name/qu/quickshell/package.nix` (nixos-unstable / release-26.05) |
| home-manager `programs.quickshell` (configs/activeConfig/systemd) | `nix-community/home-manager` → `modules/programs/quickshell.nix` (release-25.11) |
| Quickshell upstream flake + overlay + home-manager PR | quickshell `flake.nix`; `quickshell-mirror/quickshell#2` |
| Dolphin/sycoca `XDG_MENU_PREFIX` gotcha | `github.com/hyprwm/Hyprland/discussions/13984` |
| Dolphin as KDE portal file-picker under Hyprland | `github.com/hyprwm/Hyprland/discussions/4988` |
| Dolphin+Konsole+Kate under Hyprland; `balooctl6 disable` | Lorenzo Bettini, "Hyprland and KDE Applications" (lorenzobettini.it) |
| kded6 role ("daemon for session services... on demand") | Debian package page `packages.debian.org/sid/kded6` |
| Plasma autostart-not-show-in (NotShowIn=Hyprland) | Arch BBS "Koi starts Plasma stuff when running Hyprland" (community workaround) |

**Not verified / gaps (say so):**
- Exact nixpkgs quickshell version *today* (0.3.1 released 2026-08-20 may or may not be in
  nixpkgs yet; nixpkgs had 0.3.0).
- Whether Omarchy's `quattro` shell pins a Quickshell commit newer than nixpkgs 0.3.0 (the
  repo only lists `quickshell` in its base packages — Arch, not a Nix pin).
- The exact `XDG_MENU_PREFIX` value suitable on the user's NixOS (distro-specific; matches
  whatever `*-applications.menu` file is present).
- Whether the user's fingerprint reader + the shell's `omarchy-lock-fingerprint` PAM flow
  works on NixOS without extra PAM configuration (planned, unverified).

---

# Addendum (2026-08-22) — fact-check of the two quickshell packaging gaps

> Fact-check task: verify (Q1) the quickshell version in nixos-unstable today, (Q2) what
> quickshell version Omarchy's `quattro` branch requires and how it consumes it, (Q3)
> whether Omarchy pins/builds quickshell itself and whether a NixOS user could reuse that
> build. All claims below were re-verified against primary sources on 2026-08-22: nixpkgs
> `package.nix` at the `master` and `nixos-unstable` branch tips, the full
> `basecamp/omarchy` tree at the `quattro` tip commit
> `2c247e390e357ae0fee3f8565b0c816adb705e6a` (fresh fetch), the `omacom-io/omarchy-pkgs`
> repo, the Arch package DB, and the `quickshell-mirror` tags API. The gaps listed at the
> end of §"Not verified / gaps" are now closed.

## Q1 — nixpkgs version today: **0.3.0; 0.3.1 NOT packaged**

- `pkgs/by-name/qu/quickshell/package.nix` fetched from **both** the nixpkgs `master` and
  `nixos-unstable` branch tips reads `version = "0.3.0";` with
  `src = fetchFromGitea { domain = "git.outfoxxed.me"; tag = "v${finalAttrs.version}";
  hash = "sha256-gU+VGpwGJ2vvg0mtYqVvj5u+2LteuHlpokH6JSAtueY="; }`. So **`nixos-unstable`
  ships quickshell 0.3.0 today** (identical package on both branches; only the bump PR
  differs).
- **0.3.1 is queued but not merged:** GitHub search finds a single open nixpkgs PR,
  **`NixOS/nixpkgs#554917` "quickshell: 0.3.0 -> 0.3.1"** (opened 2026-08-21, state `open`
  at check time). Until that merges, `pkgs.quickshell` on nixos-unstable == 0.3.0.
- Upstream tag date (for the record — the doc dated the release 2026-08-20):
  `quickshell-mirror/quickshell` tags API shows `v0.3.1` at commit
  `1a4716cde794a59928d9d9fc15f2afc7a95de360`, committer date **2026-08-21T02:28:55Z**.
  Arch's `extra` repo already carries **quickshell 0.3.1-1** (Arch package DB, checked
  2026-08-22).

## Q2 — Omarchy `quattro` requirement: packaged quickshell **≥ 0.3.1, explicitly not git/master**; no flake, no upstream-flake use

- **Omarchy has no Nix of any kind.** The full recursive tree of `basecamp/omarchy` at
  `quattro` (1,899 entries, `truncated: false`) contains **zero `.nix` files and no
  `flake.nix`**; the only packaging artifacts are Arch bash installers
  (`install/*.sh`, `install/omarchy-base.packages`). The repo's own docs point at
  `omacom-io/omarchy-pkgs` ("Omarchy itself is installed as regular pacman packages from
  the [Omarchy Package Repository](https://github.com/omacom-io/omarchy-pkgs)" —
  `manual/30-updates.md`). It does **not** use the upstream quickshell flake: there is no
  reference to `git.outfoxxed.me` or `quickshell-mirror` anywhere in the repo.
- The **distro-package dependency** is `quickshell` (plain, not `-git`) at
  `install/omarchy-base.packages` line 112 — an Arch `extra` package, currently
  **0.3.1-1**. This is a pacman package name, not a Nix pin, exactly as the doc suspected.
- **The real version policy is expressed as migrations**, which pin the *behaviour* rather
  than a floor version:
  - `migrations/1784672586.sh` (epoch → 2026-07-21): "Switch to the Omarchy quickshell-git
    build so shell restarts wait for instance exit" — installed `quickshell-git` because
    the then-packaged build's `kill` returned before instance exit.
  - `migrations/1787399318.sh` (epoch → 2026-08-22): "Switch back to the packaged
    quickshell now that 0.3.1 kills synchronously"; body: "0.3.1 fixes `kill` returning
    before the instance has exited, which is the only reason Omarchy shipped the git
    build." — runs `sudo pacman -S --noconfirm --ask 4 quickshell` to replace
    `quickshell-git`.
- Reading (primary evidence): Omarchy's current expectation is **the distro's packaged
  quickshell at ≥ 0.3.1** (Arch extra satisfies this today), and it actively migrates
  *away* from the git build now that 0.3.1 has the fix. By inference from the migration
  comments, the shell itself ran on the git build at `0.3.0.r20.g28771c7` with no other
  functional complaint — so nixpkgs' **0.3.0 is expected to run Omarchy's shell**, with the
  known caveat that `omarchy-restart-shell`'s kill-then-restart path has the race 0.3.1
  fixes (the only reason Omarchy ever left the packaged build). That inference is labelled;
  Omarchy states no formal minimum version anywhere.

## Q3 — No Omarchy derivation exists to reuse; but the exact rev they validated is known

- **There is no Omarchy Nix derivation.** The "Omarchy quickshell-git build" referenced by
  the 2026-07-21 migration is an **Arch PKGBUILD** in `omacom-io/omarchy-pkgs` →
  `pkgbuilds/quickshell-git/PKGBUILD` (maintainer Entailz; the repo's `sync-aur.yml`
  workflow keeps these PKGBUILDs in sync with the AUR). It is source-pinned:
  ```
  source=("$_pkgsrc"::"git+$url.git#commit=28771c7c74b42e20afca0b1b63980cb46515537c" ...)
  ```
  with `pkgver=0.3.0.r20.g28771c7` — i.e. **20 commits after v0.3.0, at upstream commit
  `28771c7c74b42e20afca0b1b63980cb46515537c`**. That upstream rev is the one Omarchy's
  shell was validated against in the git-build era. PKGBUILDs are of no use to NixOS.
- **Practical NixOS answer:** there is nothing to "reuse" from omarchy on Nix. Options
  remain (from §6): `pkgs.quickshell` (= 0.3.0 today → known restart-kill race with
  Omarchy's restart wrapper) **or** the upstream flake pinned to a rev Omarchy validated
  — `28771c7c74b42e20afca0b1b63980cb46515537c` is the safest known-good commit — or to
  `v0.3.1` (`1a4716cd...`) once nixpkgs PR #554917 merges. Either way
  `inputs.nixpkgs.follows` per the upstream docs, as §3b already says.

### Sources for this addendum (all fetched 2026-08-22)
| Claim | Source |
|---|---|
| nixpkgs quickshell == 0.3.0 on master and nixos-unstable | `raw.githubusercontent.com/NixOS/nixpkgs/{master,nixos-unstable}/pkgs/by-name/qu/quickshell/package.nix` (`version = "0.3.0"`) |
| 0.3.1 bump open, unmerged | `api.github.com/search/issues?q=repo:NixOS/nixpkgs+quickshell+0.3.1` → PR `NixOS/nixpkgs#554917` (state open, created 2026-08-21) |
| v0.3.1 tag commit/date; no v0.3.1 in nixpkgs | `api.github.com/repos/quickshell-mirror/quickshell/tags` and `/commits/v0.3.1` → `1a4716cd...`, 2026-08-21T02:28:55Z |
| Arch packaged quickshell 0.3.1-1 | `archlinux.org/packages/search/json/?name=quickshell` (repo `extra`, `pkgver 0.3.1`) |
| No flake / no .nix / no upstream-flake reference in omarchy | `api.github.com/repos/basecamp/omarchy/git/trees/quattro?recursive=1` (1,899 entries, 0 nix paths); grep of clone at `2c247e39...` |
| `quickshell` (package) in base list | `basecamp/omarchy` → `install/omarchy-base.packages` line 112 |
| Version policy via migrations | `basecamp/omarchy` → `migrations/1784672586.sh` (2026-07-21, to `quickshell-git`) & `migrations/1787399318.sh` (2026-08-22, back to packaged; "0.3.1 kills synchronously") |
| Omarchy's own quickshell-git PKGBUILD, rev pin `28771c7c...`, pkgver `0.3.0.r20.g28771c7` | `omacom-io/omarchy-pkgs` → `pkgbuilds/quickshell-git/PKGBUILD` (+ `.github/workflows/sync-aur.yml`) |
| Omarchy ships as pacman packages from omacom-io/omarchy-pkgs | `basecamp/omarchy` → `manual/30-updates.md`, `manual/48-security.md` |
