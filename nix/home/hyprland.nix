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
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    # KDE portal + kwallet so apps that use libsecret (Chrome, mpv scripts,
    # etc.) get a Secret Service backend in the Hyprland session. Under
    # Plasma these come from services.desktopManager.plasma6.enable; under
    # Hyprland we have to install them ourselves. kwallet-pam also ships
    # the pam_kwallet_init autostart helper that launches the wallet daemon
    # at session start.
    #
    # NOTE: kwallet cannot be unlocked by fingerprint — the NixOS wiki is
    # explicit. We accept the password prompt on wallet open; the wallet
    # password matches the login password so the prompt is short.
    kdePackages.xdg-desktop-portal-kde
    kdePackages.kwallet
    kdePackages.kwallet-pam
    polkit
  ];

  # Leak-prevention TODO (v1.1): HM's wayland.windowManager.hyprland starts
  # hyprland-session.target but never stops it on logout. For v1 we accept
  # that waybar/mako may persist into the next Plasma login (cosmetic —
  # `pkill waybar` clears it; hypridle is already on hyprland-session.target
  # so it won't start under Plasma).
  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
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
      # Compositor-specific env vars (NOT in home.sessionVariables — that
      # would leak into the Plasma session and break it).
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

  # Waybar is Hyprland-only. Bind its service to hyprland-session.target so it
  # never starts (or lingers) under Plasma. programs.waybar.systemd.enable
  # generates the unit; this override retargets its lifecycle.
  systemd.user.services.waybar = {
    Unit = {
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Install.WantedBy = [ "hyprland-session.target" ];
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
        modules-right = [ "mpris" "bluetooth" "pulseaudio" "network" "battery" "clock" "tray" ];
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
        mpris = {
          format = "{player_icon} {title}";
          format-paused = "{player_icon} {title}";
          player-icons = {
            default = "▶";
            chromium = "◉";
            mpv = "♫";
          };
          max-length = 40;
        };
        bluetooth = {
          format = "BT {device_alias}";
          format-connected = "BT {device_alias}";
          format-disconnected = "BT off";
          tooltip-format = "{device_enumerate}";
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

      #mpris,
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

      #mpris.playing {
        color: #88c0d0;
      }

      #mpris.paused {
        color: #4c566a;
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

  # kwallet-pam ships pam_kwallet_init.desktop; the systemd-xdg-autostart
  # generator (under graphical-session.target) only honors it when this is
  # on. Without it, the wallet never unlocks on Hyprland session start.
  xdg.autostart.enable = true;

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
    # configPackages tells HM which packages to scan for *.portal files
    # (the desktop files that describe portal interfaces). We add
    # plasma-workspace so the KDE portal's interfaces get registered.
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

  # hypridle talks to Hyprland's IPC socket — it must NOT start under Plasma
  # (or any non-Hyprland session) or it crashes immediately. Bind it to the
  # per-session target that the wayland.windowManager.hyprland module creates
  # only when a Hyprland session is active.
  # hypridle also requires a config file — without ~/.config/hypr/hypridle.conf
  # it aborts with "Could not find config...". Ship a default via xdg.configFile.
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

  systemd.user.services.hypridle = {
    Unit = {
      Description = "Hyprland idle daemon";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hypridle}/bin/hypridle";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  # Mako is Hyprland-only — Plasma has its own notification daemon
  # (kded6/plasma-workspace), so we don't want mako leaking into the
  # Plasma session. Bind it to hyprland-session.target like hypridle.
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon (Hyprland)";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  # Walker + Elephant — Hyprland-only (Plasma has its own launcher).
  # Elephant is the backend data service; Walker is the frontend launcher.
  # Walker must run as a service for clipboard history to work.
  xdg.configFile."walker/config.toml".text = ''
    [providers]
      [providers.sets.default]
      default = ["desktopapplications", "runner", "clipboard"]
      empty = ["desktopapplications"]
  '';

  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant data provider for Walker";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.walker = {
    Unit = {
      Description = "Walker application launcher";
      After = [ "hyprland-session.target" "elephant.service" ];
      PartOf = [ "hyprland-session.target" ];
      Requires = [ "elephant.service" ];
    };
    Service = {
      ExecStart = "${pkgs.walker}/bin/walker --gapplication-service";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
