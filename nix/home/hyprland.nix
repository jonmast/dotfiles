{ config, pkgs, lib, ... }:

{
  # Hyprland ecosystem packages. These are only useful inside a Hyprland
  # session, so they live here instead of common.nix.
  home.packages = with pkgs; [
    hyprland
    waybar
    mako
    hyprlock
    hypridle
    walker         # app launcher + clipboard history
    elephant       # walker backend data service
    swaybg
    grim
    slurp
    wlr-randr
    wl-clipboard   # provides wl-copy for the screenshot keybind
    playerctl      # media key control
    brightnessctl  # brightness key control
    wireplumber    # provides wpctl for audio key control
    jq             # JSON parsing for waybar custom scripts
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
  # HM starts hyprland-session.target but never stops it on logout, so waybar
  # and friends used to persist into the next login. Under uwsm, uwsm owns
  # graphical-session.target; hyprland-session.target declares
  # `BindsTo=graphical-session.target`, so when uwsm stops graphical-session on
  # logout the stop propagates down to hyprland-session.target and on to every
  # `PartOf=` service below. Verified experimentally with probe units.
  #
  # Issue 02 collapsed the target indirection. During the dual-session window
  # the five services had to stay on hyprland-session.target, because Plasma
  # also activates graphical-session.target and a literal rebind would have
  # started waybar/mako/hypridle under Plasma (hypridle crash-loops with no
  # Hyprland IPC). Plasma is gone, so they now bind directly to
  # graphical-session.target as ADR 0003 originally called for.
  #
  # Ordering is safe under uwsm: wayland-wm@.service is `Type=notify` and
  # declares `Before=graphical-session.target`, so the target is only reached
  # once the compositor has signalled ready via `uwsm finalize` — which is also
  # what exports HYPRLAND_INSTANCE_SIGNATURE into the systemd user environment.
  # So hypridle/waybar always find a live Hyprland IPC socket.
  #
  # hyprland-session.target still exists (HM defines it) and is still started by
  # the exec-once below, but nothing is bound to it any more. It retains exactly
  # one job: in the NON-uwsm escape-hatch session, nothing else would ever
  # activate graphical-session.target, and `BindsTo=` implies `Requires=`, so
  # starting hyprland-session.target pulls graphical-session.target up and the
  # five services come with it. Drop that exec-once and the escape-hatch session
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
    # the start and waybar/mako/hypridle/walker/elephant never launch.
    # Verified both directions with probe units.
    systemd.extraCommands = [ "systemctl --user start hyprland-session.target" ];
    # hyprlang (legacy default) — our config is written in hyprlang syntax.
    # Lua mode is a v1.1+ option; switching now broke the config parse
    # ("emergency mode" on the bare session attempt). Set explicitly to
    # silence the eval warning until we bump stateVersion to >= "26.05".
    configType = "hyprlang";
    settings = {
      # Framework 13 eDP-1 panel (2256x1504, ~200 DPI). Hyprland quantizes
      # scale to multiples of 1/120 and requires both dimensions to divide
      # cleanly. 1.5x fails because 1504/1.5 = 1002.67 (not integer). The
      # closest valid scale is 1.5667 (188/120) → effective 1440x960.
      monitor = [ ",preferred,auto,1.5667" ];
      input = {
        kb_layout = "us";
        follow_mouse = 1;
        # Remap Caps Lock to Escape (holds-as-escape too — great for vim).
        kb_options = [ "caps:escape" ];
        # natural_scroll on a Framework 13 touchpad only takes effect when
        # nested under `input.touchpad` — putting it in the global `input`
        # block silently no-ops on the touchpad (Hyprland issue #2458).
        # disable_while_typing = false is the default but set explicitly
        # so the touchpad stays active when typing into Moonlight's
        # streamed window — the kernel's i2c-hid palm-rejection can
        # otherwise leave the pad unresponsive for ~1s after every key.
        # Toggle with $mainMod+T or the waybar DWT button to enable
        # disable_while_typing for apps like Ghostty (phantom clicks).
        touchpad = {
          natural_scroll = true;
          disable_while_typing = false;
          # 1/2/3-finger physical click = left/right/middle (libinput default,
          # set explicitly so it survives any future libinput default flip).
          clickfinger_behavior = true;
        };
      };
      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
      };
      decoration = { rounding = 8; };
      # Compositor-specific env vars. Kept here rather than in
      # home.sessionVariables so they stay scoped to a Hyprland session (the
      # original reason was to avoid leaking into Plasma; Plasma is gone, but
      # scoping them to the compositor is still the right shape — they are
      # wrong for a TTY or a non-Hyprland login).
      env = [
        "QT_QPA_PLATFORM,wayland;xcb"
        "GDK_BACKEND,wayland,x11"
        "SDL_VIDEODRIVER,wayland"
        "MOZ_ENABLE_WAYLAND,1"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
      ];
      # waybar is started by the HM-managed systemd user service
      # (programs.waybar.systemd.enable below) — do NOT also exec-once it,
      # or you'll get two instances fighting over the bar slot.
      exec-once = [ "swaybg -i ~/.config/hypr/wallpaper.jpg -m fill" ];
      # $mod = SUPER (Hyprland's default $mainMod; explicit for clarity)
      "$mainMod" = "SUPER";
      bind = [
        "$mainMod, RETURN, exec, ghostty"
        "$mainMod, D, exec, walker"
        "$mainMod, Q, killactive"
        "$mainMod, E, exec, dolphin"
        "$mainMod, V, togglefloating"
        "$mainMod SHIFT, V, exec, walker -m clipboard"
        "$mainMod, F, fullscreen"
        "$mainMod, P, pseudo"
        "$mainMod, J, layoutmsg, togglesplit"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, E, exit"
        "$mainMod, T, exec, hyprctl keyword input:touchpad:disable_while_typing $(if [ \"$(hyprctl getoption input:touchpad:disable_while_typing -j | jq -r .bool)\" = 'false' ]; then echo true; else echo false; fi)"
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      ];
      bindl = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
        ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];
      # Touchpad gestures: 3-finger horizontal swipe to change workspace.
      # Hyprland gesture syntax is `fingers, direction, action` (not
      # `swipe, fingers, ...`). `horizontal` is a direction that means
      # "any horizontal swipe", and `workspace` automatically steps in
      # the swipe direction — no `e+1` / `e-1` needed.
      gesture = [
        "3, horizontal, workspace"
      ];
    };
  };

  # programs.waybar.systemd.enable generates the unit; this override retargets
  # its lifecycle onto graphical-session.target (see the note at the top of this
  # file — Hyprland is now the only session, so the extra indirection through
  # hyprland-session.target is gone).
  systemd.user.services.waybar = {
    Unit = {
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  programs.waybar = {
    enable = true;
    package = pkgs.waybar;
    systemd.enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 30;
        margin-top = 5;
        margin-left = 10;
        margin-right = 10;
        modules-left = [ "hyprland/workspaces" "hyprland/window" ];
        modules-right = [ "custom/dwt" "bluetooth" "pulseaudio" "network" "battery" "clock" "tray" ];
        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
        };
        tray = { spacing = 10; };
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "muted";
          format-icons = {
            default = [ "🔊" "🔉" "🔈" ];
          };
        };
        battery = {
          format = "{icon} {capacity}%";
          format-icons = [ "🪫" "🔋" "🔋" ];
          format-charging = "⚡ {capacity}%";
          states = {
            warning = 30;
            critical = 15;
          };
        };
        bluetooth = {
          format = "BT {device_alias}";
          format-connected = "BT {device_alias}";
          format-disconnected = "BT off";
          tooltip-format = "{device_enumerate}";
        };
        "custom/dwt" = {
          return-type = "json";
          exec = pkgs.writeShellScript "dwt-status" ''
            val=$(hyprctl getoption input:touchpad:disable_while_typing -j | jq -r .bool)
            if [ "$val" = "true" ]; then
              echo '{"text":"DWT on","class":"dwt-on","tooltip":"Disable-while-typing ON (click to disable)"}'
            else
              echo '{"text":"DWT off","class":"dwt-off","tooltip":"Disable-while-typing OFF (click to enable)"}'
            fi
          '';
          interval = 5;
        };
      }
    ];
    style = ''
      * {
        font-family: "Sans", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: transparent;
        box-shadow: none;
      }

      tooltip {
        background: #2e3440;
        border: 1px solid #4c566a;
        border-radius: 6px;
        color: #d8dee9;
      }

      #workspaces button {
        padding: 0 10px;
        color: #4c566a;
        background: rgba(46, 52, 64, 0.65);
        border-radius: 6px;
        margin: 4px 2px;
        border: none;
      }

      #workspaces button.active,
      #workspaces button.focused {
        color: #2e3440;
        background: #88c0d0;
        border-radius: 6px;
      }

      #workspaces button:hover {
        background: #434c5e;
        color: #eceff4;
      }

      #window {
        padding: 0 12px;
        color: #d8dee9;
        background: rgba(46, 52, 64, 0.65);
        border-radius: 6px;
        margin: 4px 2px;
      }

      #custom-dwt,
      #bluetooth,
      #pulseaudio,
      #network,
      #battery,
      #clock,
      #tray {
        padding: 0 12px;
        color: #d8dee9;
        background: rgba(46, 52, 64, 0.65);
        border-radius: 6px;
        margin: 4px 2px;
      }

      #custom-dwt.dwt-on {
        color: #a3be8c;
      }

      #custom-dwt.dwt-off {
        color: #bf616a;
      }

      #bluetooth.connected {
        color: #a3be8c;
      }

      #bluetooth.off {
        color: #4c566a;
      }

      #pulseaudio.muted {
        color: #bf616a;
      }

      #network.disconnected {
        color: #bf616a;
      }

      #battery.full,
      #battery.charging {
        color: #a3be8c;
      }

      #battery.warning {
        color: #ebcb8b;
      }

      #battery.critical {
        color: #bf616a;
      }

      #clock {
        color: #88c0d0;
        font-weight: bold;
      }
    '';
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

  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon (Hyprland)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Walker + Elephant. Elephant is the backend data service; Walker is the
  # frontend launcher. Walker must run as a service for clipboard history.
  xdg.configFile."walker/config.toml".text = ''
    [providers]
      [providers.sets.default]
      default = ["desktopapplications", "runner", "clipboard"]
      empty = ["desktopapplications"]
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
      Description = "Walker application launcher";
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
