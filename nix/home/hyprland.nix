{ config, pkgs, lib, inputs, ... }:

{
  # Hyprland ecosystem packages. These are only useful inside a Hyprland
  # session, so they live here instead of common.nix.
  home.packages = with pkgs; [
    hyprland
    phinger-cursors
    # mako removed by issue 05 — The Shell is the notification daemon now
    # (nix/home/quickshell/Notifications/NotificationService.qml). Only one
    # process may own org.freedesktop.Notifications, so the removal and the
    # NotificationServer have to land together.
    hyprlock
    hypridle
    # Clipboard history only, since issue 04 — The Shell's menu is the app
    # launcher (CONTEXT.md, "Walker stack"). Kept because Quickshell 0.3.1 has
    # no clipboard-history primitive and elephant's is already proven here.
    walker         # clipboard history frontend ($mod SHIFT V)
    elephant       # walker backend data service
    swaybg
    grim
    slurp
    wlr-randr
    wl-clipboard   # provides wl-copy for the screenshot keybind
    playerctl      # media key control
    brightnessctl  # brightness key control
    wireplumber    # provides wpctl for audio key control
    jq             # JSON parsing for the $mod T DWT keybind below
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    # KDE portal + kwallet so apps that use libsecret (Chrome, mpv scripts,
    # etc.) get a Secret Service backend. These used to also arrive via
    # services.desktopManager.plasma6.enable; since issue 02 removed Plasma,
    # these declarations are the ONLY thing installing them. kwallet ships
    # `kwallet.portal`, which is what actually registers the
    # org.freedesktop.impl.portal.Secret interface (NOT plasma-workspace — see
    # the xdg.portal.configPackages note below). kwallet-pam ships the
    # pam_kwallet_init autostart helper that launches the wallet daemon at
    # session start; its PAM wiring lives in nix/nixos/diogenes.nix
    # (security.pam.services.sddm.kwallet) and is independent of Plasma.
    #
    # NOTE: kwallet cannot be unlocked by fingerprint — the NixOS wiki is
    # explicit. We accept the password prompt on wallet open; the wallet
    # password matches the login password so the prompt is short.
    kdePackages.xdg-desktop-portal-kde
    kdePackages.kwallet
    kdePackages.kwallet-pam
    polkit
  ];

  # Leak-prevention (was a v1.1 TODO, fixed structurally by uwsm — ADR 0003):
  # HM starts hyprland-session.target but never stops it on logout, so the bar
  # and friends used to persist into the next login. Under uwsm, uwsm owns
  # graphical-session.target; hyprland-session.target declares
  # `BindsTo=graphical-session.target`, so when uwsm stops graphical-session on
  # logout the stop propagates down to hyprland-session.target and on to every
  # `PartOf=` service below. Verified experimentally with probe units.
  #
  # Issue 02 collapsed the target indirection. During the dual-session window
  # the five services had to stay on hyprland-session.target, because Plasma
  # also activates graphical-session.target and a literal rebind would have
  # started the bar/mako/hypridle under Plasma (hypridle crash-loops with no
  # Hyprland IPC). Plasma is gone, so they now bind directly to
  # graphical-session.target as ADR 0003 originally called for.
  #
  # Ordering is safe under uwsm: wayland-wm@.service is `Type=notify` and
  # declares `Before=graphical-session.target`, so the target is only reached
  # once the compositor has signalled ready via `uwsm finalize` — which is also
  # what exports HYPRLAND_INSTANCE_SIGNATURE into the systemd user environment.
  # So hypridle and The Shell always find a live Hyprland IPC socket. This
  # matters more for The Shell than it did for waybar: the Bar's workspace and
  # window-title widgets are pure Hyprland IPC consumers.
  #
  # hyprland-session.target still exists (HM defines it) and is still started by
  # the exec-once below, but nothing is bound to it any more. It retains exactly
  # one job: in the NON-uwsm escape-hatch session, nothing else would ever
  # activate graphical-session.target, and `BindsTo=` implies `Requires=`, so
  # starting hyprland-session.target pulls graphical-session.target up and the
  # services come with it. Drop that exec-once and the escape-hatch session
  # boots to a bare compositor with no bar or notifications.
  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
    # systemd.enable stays true: it emits the `dbus-update-activation-environment`
    # exec-once that plumbs WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE etc.
    # into the systemd + D-Bus activation environments, and defines
    # hyprland-session.target itself.
    #
    # extraCommands drops the leading `stop` under uwsm. The default is
    #   [ "systemctl --user stop hyprland-session.target"
    #     "systemctl --user start hyprland-session.target" ]
    # appended to that exec-once line. hyprland-session.target carries
    # `PropagatesStopTo=graphical-session.target`, and systemd propagates a
    # stop even when the target is currently INACTIVE (verified with probe
    # units). Under uwsm graphical-session.target is already active at that
    # point, so the default `stop` would tear down graphical-session →
    # wayland-session@Hyprland.target → the compositor itself, at login.
    # This is almost certainly the "naive attempt broke booting" in ADR 0003.
    #
    # The `start` MUST stay. BindsTo is directional — it makes
    # hyprland-session.target require graphical-session.target, but starting
    # graphical-session.target does NOT pull hyprland-session.target up. Drop
    # the start and quickshell/mako/hypridle/walker/elephant never launch.
    # Verified both directions with probe units.
    systemd.extraCommands = [ "systemctl --user start hyprland-session.target" ];
    # Lua, not hyprlang. hyprlang is deprecated upstream as of Hyprland 0.55
    # (we run 0.56.2), and home-manager flips this default at stateVersion
    # 26.05. Set explicitly so the format stays a decision rather than a side
    # effect of a version number.
    #
    # The config itself is hand-written Lua in nix/home/hypr/, NOT the module's
    # `settings` attrset. Two reasons, and the first is why the earlier attempt
    # at this landed in emergency mode:
    #
    #   - In Lua mode `settings` renders each attribute as an `hl.<name>(...)`
    #     call. The old hyprlang-shaped attrs would emit nonsense like
    #     `hl["exec-once"](...)`, `hl.monitor(",preferred,auto,1.5667")` and
    #     `hl.bind("$mainMod, RETURN, exec, ghostty")`. Flipping configType
    #     alone cannot work; the config has to be rewritten against the Lua
    #     API.
    #   - `settings` is typed `attrsOf settingValueType`, a freeform any-type.
    #     Nix validates no option name, no dispatcher and no bind syntax, so
    #     routing the config through Nix buys nothing that hand-written Lua
    #     does not — while costing the `_args`/`mkLuaInline` escaping dance on
    #     every one of ~50 binds.
    #
    # The authoritative API reference is the stub Hyprland ships at
    # /run/current-system/sw/share/hypr/stubs/hl.meta.lua, plus the Lua REPL in
    # `hyprctl`.
    configType = "lua";

    extraLuaFiles = {
      # Store paths that must be pinned rather than resolved from the session
      # PATH. This is the one thing the Nix layer still has to contribute, so
      # it is generated into the store; `autoLoad = false` because binds.lua
      # requires it explicitly rather than it running on its own.
      paths = {
        content = ''
          return {
            qs = "${lib.getExe' config.programs.quickshell.package "qs"}",
          }
        '';
        autoLoad = false;
      };

      # Deployed as out-of-store symlinks to the working tree — the same trick
      # programs.quickshell uses for the QML below. Hyprland reloads its config
      # when the file changes, so edits go live with no rebuild at all
      # (`hyprctl reload` forces it).
      #
      # Same trade as the QML, and taken deliberately: these files are in no
      # Nix generation, so a generation rollback will NOT roll them back, and
      # git is their only history. Safe for Hyprland specifically, which only
      # reads its config and never rewrites it — do not extend this to config
      # an application persists itself.
      core.content = config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/.dotfiles/nix/home/hypr/core.lua";
      binds.content = config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/.dotfiles/nix/home/hypr/binds.lua";
    };
  };

  # The Shell. `programs.quickshell.systemd.enable` already emits the unit with
  # `After=` and `WantedBy=` pointing at `config.wayland.systemd.target`, which
  # is graphical-session.target here — so those are left alone rather than
  # restated (restating them merges to a literally duplicated line in the unit
  # file).
  #
  # What the module does NOT emit is `PartOf=`, and without it the unit is
  # started by graphical-session.target but never stopped by it: the logout
  # leak ADR 0003 exists to close, reintroduced through a module default. Every
  # other Hyprland-scoped service in this file carries the same triple.
  systemd.user.services.quickshell.Unit.PartOf = [ "graphical-session.target" ];

  # Quickshell probes for a network backend exactly once, ~400ms into process
  # startup, and caches the result for the life of the process. The probe is a
  # D-Bus name lookup: if org.freedesktop.NetworkManager is not yet on the
  # system bus, it logs
  #
  #   ERROR quickshell.network: Network will not work. Could not find an
  #   available backend.
  #
  # and never retries. Quickshell.Networking.devices then stays permanently
  # empty, so Bar/NetworkWidget.qml renders its no-device fallback — the word
  # "disconnected" in red — on a machine whose wifi is up and routing fine.
  # Reloading the QML does not clear it; the probe is C++ singleton state, not
  # QML state, so only a process restart recovers.
  #
  # `nixos-rebuild switch` loses this race routinely: activation restarts
  # NetworkManager.service and this unit together, and quickshell wins by a few
  # hundred milliseconds. Observed 2026-09-05: NM starting at 13:18:45, the
  # backend probe failing at 13:18:45.863, and the bar reading "disconnected"
  # for the next nine hours.
  #
  # So gate startup on the name actually being claimed. Only the *name* is
  # waited for, not device enumeration — once quickshell finds the backend it
  # subscribes to NM's signals and fills the device list asynchronously, which
  # the widget's bindings already handle (it renders "disconnected" for the
  # first second of every cold start, then corrects itself).
  #
  # The wait is bounded and always succeeds. A machine with NetworkManager
  # genuinely absent or broken should still get a bar with a dead network pill,
  # which is the status quo — it must not get no bar at all, and it must not
  # wedge graphical-session.target for longer than it takes to notice.
  systemd.user.services.quickshell.Service.ExecStartPre =
    let
      waitForNetworkBackend = pkgs.writeShellScript "wait-for-network-backend" ''
        i=0
        while [ "$i" -lt 100 ]; do
          if ${pkgs.systemd}/bin/busctl --system status \
              org.freedesktop.NetworkManager >/dev/null 2>&1; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 0.1
          i=$((i + 1))
        done
        echo "org.freedesktop.NetworkManager did not appear on the system bus" \
             "within 10s; starting quickshell anyway (network pill will be dead" \
             "until the next restart)" >&2
        exit 0
      '';
    in
    "${waitForNetworkBackend}";

  programs.quickshell = {
    enable = true;
    # Pinned upstream v0.3.1, not pkgs.quickshell (still 0.3.0). See the
    # `quickshell` input in flake.nix for why the pin exists and what has to
    # be true before it can be dropped.
    package = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # The QML tree is deployed to ~/.config/quickshell/shell (ADR 0001: own
    # minimal shell, HM-deployed, nothing vendored from omarchy).
    # `activeConfig` makes the unit run `quickshell --config shell`.
    #
    # Deployed as an out-of-store symlink to the working tree, NOT copied into
    # the store. With a store copy, every QML edit changes the config's store
    # path, which changes the system derivation, which costs a full ~17s
    # `nixos-rebuild` — evaluation is 100% of a no-op rebuild here, and the
    # NixOS/home-manager module system is a fixpoint, so nothing partial can be
    # cached. Pointing at the working tree makes the store path depend only on
    # the target path string, so editing QML needs no rebuild at all: just
    # `systemctl --user restart quickshell`.
    #
    # What this trades away, deliberately:
    #   - The QML is no longer captured in the generation, so a generation
    #     rollback will NOT roll the shell back. Acceptable here only because
    #     this tree is in git, which is the real history for these files.
    #   - The config is no longer reproducible from the flake alone; another
    #     machine needs this repo cloned to this exact absolute path.
    #   - The files are writable. Safe for quickshell specifically, which only
    #     reads and hot-reloads QML. Do NOT extend this to config that its own
    #     application rewrites. An app that persists its own settings will
    #     happily overwrite a writable symlink target, silently undoing the
    #     declared config; read-only store deployment is the fix for those.
    configs.shell = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.dotfiles/nix/home/quickshell";
    activeConfig = "shell";
    systemd.enable = true;
  };

  # Needed for kdeconnect (app-org.kde.kdeconnect.daemon@autostart.service) and
  # the other XDG autostart entries.
  #
  # It does NOT unlock kwallet, which is what the comment here used to claim.
  # kwallet-pam's `pam_kwallet_init.desktop` sets `X-systemd-skip=true`, so
  # systemd's xdg-autostart generator deliberately ignores it — upstream ships
  # `plasma-kwallet-pam.service` for that job instead. Verified: no
  # `pam_kwallet*` unit is generated while three other autostart entries are.
  # See the kwallet unlock service below for the wiring that actually works.
  xdg.autostart.enable = true;

  # KWallet auto-unlock, session half. The login half lives in
  # nix/nixos/diogenes.nix (`security.pam.services.login.kwallet.enable`):
  # pam_kwallet5 takes the typed password, creates
  # $XDG_RUNTIME_DIR/kwallet5.socket, and forks `ksecretd --pam-login` which
  # then BLOCKS — it owns no D-Bus name and does nothing until someone pipes
  # the session environment into that socket. `pam_kwallet_init` is what pipes
  # it (literally `env | socat STDIN UNIX-CONNECT:$PAM_KWALLET5_LOGIN`).
  #
  # Upstream ships this as `plasma-kwallet-pam.service`, but that unit is
  # `static` — `PartOf=graphical-session.target` with no `[Install]` section —
  # so under Plasma it was plasma-workspace that pulled it in. With the Plasma
  # session gone (ADR 0002) nothing does, and the symptom is subtle: login
  # succeeds, the PAM daemon sits idle forever, and the first secret lookup
  # dbus-activates a SECOND, passwordless ksecretd which grabs
  # org.freedesktop.secrets and prompts. That second daemon logs
  # "Lacking a socket, pipe: 0 env: 0" — the tell that this service didn't run.
  #
  # We shadow the upstream unit name rather than symlinking it into
  # graphical-session.target.wants, so that `systemctl --user cat` shows what
  # actually runs, and so we can add the `After=` upstream omits: the piped env
  # is only useful once uwsm has populated the manager environment (that is
  # where PAM_KWALLET5_LOGIN comes from), which is done by the time
  # graphical-session.target is reached.
  #
  # Type=oneshot, not upstream's Type=simple: the helper is a short-lived pipe,
  # and oneshot means "started" implies the handshake actually completed, plus
  # RemainAfterExit leaves the unit legible as active (exited) afterwards
  # instead of dead. No-ops harmlessly (exit 0) in the non-uwsm escape-hatch
  # session, where PAM_KWALLET5_LOGIN is unset.
  systemd.user.services.plasma-kwallet-pam = {
    Unit = {
      Description = "Unlock kwallet from pam credentials";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init";
      Slice = "background.slice";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.portal = {
    enable = true;
    # HM module already adds xdg-desktop-portal-hyprland via
    # configPackages (mkDefault). We need the KDE portal on top so the
    # org.freedesktop.impl.portal.Secret interface is routable, and the
    # GTK portal as the catch-all fallback for OpenURI / Settings.
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      kdePackages.xdg-desktop-portal-kde
      xdg-desktop-portal-gtk
    ];
    # configPackages: RESOLVED for issue 02 — plasma-workspace stays, but not
    # for the reason the old comment here gave.
    #
    # The old comment claimed configPackages makes HM "scan packages for
    # *.portal files" so "the KDE portal's interfaces get registered". That is
    # wrong. HM's module (modules/misc/xdg/portal.nix) does exactly one thing
    # with this list:
    #     home.packages = packages ++ cfg.configPackages;
    # i.e. it just INSTALLS the package. Portal interfaces are registered by the
    # *.portal files in extraPortals' own outputs — the Secret interface we care
    # about comes from `kwallet.portal` (shipped by kdePackages.kwallet, already
    # in home.packages above), not from plasma-workspace.
    #
    # So plasma-workspace is NOT load-bearing for portals. It IS load-bearing
    # for the application menu, which is why it stays: it is the only package on
    # the system shipping
    #     etc/xdg/menus/plasma-applications.menu
    # plus the 40 share/desktop-directories/*.directory files that menu
    # references. XDG_MENU_PREFIX=plasma- (set below) resolves to exactly that
    # file. Drop plasma-workspace and Dolphin's "Open With → Other Application"
    # tree goes empty again regardless of the prefix.
    #
    # Keeping it in configPackages (rather than home.packages) is deliberate:
    # both routes install it identically, and this one keeps it adjacent to the
    # portal config it used to be justified by. Verified by building
    # home.path with and without Plasma — byte-identical store path, menu file
    # and .directory files present in both.
    #
    # Its Plasma autostart entries (plasmashell, xembedsniproxy, ...) are all
    # `OnlyShowIn=KDE` and XDG_CURRENT_DESKTOP is Hyprland, so installing the
    # package does not start any Plasma daemon.
    configPackages = with pkgs; [
      hyprland
      kdePackages.plasma-workspace
    ];
    # IMPORTANT: `preferred` is the INI section header written by the HM
    # module (modules/misc/xdg-portal.nix), not a key inside it. The old
    # form `preferred = [ ... ]` produced a malformed portals.conf
    # (`[preferred]\npreferred=...`). The actual keys are `default`
    # (catch-all) or a specific interface name.
    config.hyprland = {
      default = [ "hyprland" "gtk" "kde" ];
      # Route ONLY the Secret portal to KDE. Everything else (ScreenCast,
      # GlobalShortcuts, RemoteDesktop, FileChooser, etc.) stays on the
      # Hyprland/GTK backends. This is the single change that gives
      # libsecret-using apps a working Secret Service in Hyprland.
      "org.freedesktop.impl.portal.Secret" = [ "kde" ];
    };
  };

  # KDE menu prefix fix (Dolphin "Open With", sycoca).
  #
  # uwsm derives XDG_MENU_PREFIX from the compositor's desktop name:
  #   XDG_MENU_PREFIX="$(lowercase "${__WM_FIRST_DESKTOP_NAME__}")-"
  # (uwsm-0.26.6/libexec/uwsm/prepare-env.sh:177) which yields `hyprland-`.
  # KDE then looks for `${XDG_MENU_PREFIX}applications.menu` and finds nothing:
  # the only menu file on the system is `plasma-applications.menu`, shipped by
  # plasma-workspace into /run/current-system/sw/etc/xdg/menus/. There is no
  # hyprland-applications.menu anywhere, so the whole application menu tree
  # comes back empty and Dolphin's "Open With" is unpopulated.
  #
  # Measured with `kbuildsycoca6 --menutest`:
  #   XDG_MENU_PREFIX=hyprland-  ->  0 entries
  #   XDG_MENU_PREFIX=plasma-    -> 41 entries
  #
  # Set via uwsm's own env-file mechanism rather than home.sessionVariables or
  # hyprland `env =`, because uwsm force-exports XDG_MENU_PREFIX (it is in its
  # `always_export` set) when it prepares the environment. prepare-env.sh
  # assigns the prefix at line 177 and only THEN sources these env files
  # (load_wm_env, line 195), so this assignment wins.
  #
  # This is the "XDG_MENU_PREFIX corrected at the systemd layer" follow-up
  # folded into the plan; issue 02 verifies it end-to-end via Dolphin.
  #
  # NOTE (issue 02): this only works while plasma-workspace remains installed —
  # it is the sole provider of plasma-applications.menu and the .directory files
  # that menu references. See the xdg.portal.configPackages note above, which is
  # what keeps it in the profile. Caveat: uwsm env files are read by uwsm only,
  # so in the non-uwsm escape-hatch session the prefix reverts to the KDE
  # default and the "Open With" tree is empty there. Acceptable — that session
  # exists to get a shell up and rebuild, not for daily use.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export XDG_MENU_PREFIX=plasma-
  '';

  # hypridle requires a config file — without ~/.config/hypr/hypridle.conf it
  # aborts with "Could not find config...". Ship a default via xdg.configFile.
  # (Its unit definition and target binding are further down.)
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock        # avoid multiple hyprlock instances.
        before_sleep_cmd = loginctl lock-session      # lock before suspend.
        after_sleep_cmd = hyprctl dispatch dpms on    # wake the display cleanly.
    }

    listener {
        timeout = 300                                 # 5 min
        on-timeout = loginctl lock-session
    }

    listener {
        timeout = 480                                 # 8 min
        on-timeout = hyprctl dispatch dpms off
        on-resume = hyprctl dispatch dpms on
    }

    listener {
        timeout = 1800                                # 30 min
        on-timeout = systemctl suspend
    }
  '';

  # hyprlock needs ~/.config/hypr/hyprlock.conf or it silently runs with no
  # auth methods. Use the NATIVE fprintd backend (auth.fingerprint.enabled):
  # it talks to fprintd over DBus directly, so password input and the
  # fingerprint reader run in parallel — type a password OR scan a finger.
  # This works ONLY because pam_fprintd is disabled in /etc/pam.d/hyprlock
  # (see nix/nixos/diogenes.nix). With pam_fprintd in the PAM stack, the
  # typed password would block on the fprintd prompt/timeout.
  # Wallet: pam_kwallet5 is NOT in the hyprlock stack, so the kwallet
  # prompt still appears on first libsecret use post-unlock. The wallet
  # password == the login password, so the prompt is one keystroke.
  xdg.configFile."hypr/hyprlock.conf".text = ''
    auth {
        pam {
            enabled = true
            module  = hyprlock
        }
        fingerprint {
            enabled         = true
            ready_message   = (Scan fingerprint to unlock)
            present_message = Scanning...
            retry_delay     = 250
        }
    }

    general {
        hide_cursor = true
    }

    background {
        monitor =
        path = screenshot
        blur_passes = 3
    }

    input-field {
        monitor =
        size = 300, 50
        outline_thickness = 3
        inner_color = rgba(0, 0, 0, 0.0)
        outer_color = rgba(33ccffee) rgba(00ff99ee) 45deg
        check_color = rgba(00ff99ee) rgba(ff6633ee) 120deg
        fail_color = rgba(ff6633ee) rgba(ff0066ee) 40deg
        font_color = rgb(143, 143, 143)
        fade_on_empty = false
        rounding = 15
        placeholder_text = <i>Password or scan finger…</i>
        fail_text = $FAIL
        dots_spacing = 0.3
        position = 0, -20
        halign = center
        valign = center
    }

    label {
        monitor =
        text = $TIME
        font_size = 90
        font_family = monospace
        position = -30, 0
        halign = right
        valign = top
    }
  '';

  # hypridle talks to Hyprland's IPC socket. Safe on graphical-session.target
  # under uwsm: the compositor has already signalled ready (and exported
  # HYPRLAND_INSTANCE_SIGNATURE) before that target is reached.
  systemd.user.services.hypridle = {
    Unit = {
      Description = "Hyprland idle daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hypridle}/bin/hypridle";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # No mako.service here since issue 05. The Shell claims
  # org.freedesktop.Notifications itself, and two claimants means whichever
  # loses the race receives nothing — silently, with no error anywhere. If you
  # are re-adding a notification daemon, delete The Shell's NotificationServer
  # in the same change.
  #
  # Note for a rebuild that lands this: the old mako.service is not stopped by
  # `switch` (HM removes the unit, systemd keeps the running process), so the
  # bus name stays held until logout. `systemctl --user stop mako` before
  # testing, or check after a re-login.

  # Walker + Elephant, demoted to clipboard history by issue 04. Elephant is
  # the backend data service; walker is the frontend. Walker must run as a
  # service for clipboard history — the history lives in the running process,
  # so a one-shot invocation would show an empty list.
  #
  # The provider set is clipboard-only now. `desktopapplications` and `runner`
  # were what made a bare `walker` an app launcher and a command runner; that
  # role belongs to The Shell's menu (CONTEXT.md, "Walker stack"), and leaving
  # the providers configured would leave a second, divergent launcher one
  # keystroke away. `$mod SHIFT V` passes `-m clipboard` explicitly, so it does
  # not depend on this set — but a bare `walker` typed at a prompt now opens
  # the clipboard rather than a launcher, which is the point.
  xdg.configFile."walker/config.toml".text = ''
    [providers]
      [providers.sets.default]
      default = ["clipboard"]
      empty = ["clipboard"]
  '';

  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant data provider for Walker";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.walker = {
    Unit = {
      Description = "Walker clipboard history";
      After = [ "graphical-session.target" "elephant.service" ];
      PartOf = [ "graphical-session.target" ];
      Requires = [ "elephant.service" ];
    };
    Service = {
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
