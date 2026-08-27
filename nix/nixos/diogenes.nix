# NixOS system configuration for diogenes.
# Migrated from /etc/nixos/configuration.nix.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.initrd.luks.devices."luks-00d634db-fbb3-4fc3-aa29-397b289e0526".device = "/dev/disk/by-uuid/00d634db-fbb3-4fc3-aa29-397b289e0526";

  # Hibernate to the LUKS swap partition (>= RAM size). The initrd opens the
  # device, so boot.resumeDevice adds resume= and resume_offset= to the kernel
  # cmdline and the resume happens before init.
  boot.resumeDevice = "/dev/mapper/luks-00d634db-fbb3-4fc3-aa29-397b289e0526";

  networking.hostName = "diogenes";
  networking.networkmanager.enable = true;

  # Automatic garbage collection: weekly, keep everything newer than 30 days
  # (conservative — 30d of rollback points, then prune).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.auto-optimise-store = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Display manager. SDDM on wayland; Hyprland is the only desktop (issue 02
  # removed the Plasma session — see ADR 0002).
  #
  # services.xserver.enable stays FALSE: nothing here needs an X server. Xwayland
  # comes from programs.hyprland.enable (its own `xwayland.enable`), not from
  # services.xserver, and SDDM asserts only `xserver.enable || wayland.enable`.
  # Dropping it also drops the `plasmax11.desktop` X session entry.
  #
  # NOTE: services.xserver.xkb (below) is still read — the weston greeter
  # generates its keymap from it — so that block must NOT be removed with this.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  # The greeter's own compositor. plasma6 used to set this to kwin via mkDefault
  # (nixos/modules/services/desktop-managers/plasma6.nix); with plasma6 gone the
  # module default `weston` applies. Left at the default deliberately — kwin is
  # otherwise a Plasma-only dependency and keeping it just for the greeter would
  # retain most of what this ticket set out to remove.
  #
  # If the greeter ever misbehaves, `services.displayManager.sddm.wayland.compositor
  # = "kwin"` restores the old behaviour (and pulls kdePackages.kwin back in).
  #
  # Two session entries are offered (see the sessionPackages note below), so
  # SDDM needs to know which to preselect; plasma6 used to set this to "plasma".
  services.displayManager.defaultSession = "hyprland-uwsm";
  # Use the canonical NixOS Hyprland module — it adds the desktop session
  # entry AND wires polkit, xdg-desktop-portal-hyprland, graphics, fonts,
  # dconf, and xwayland. The home-manager module on the user side is layered
  # on top of this for the user-level session target.
  programs.hyprland.enable = true;
  # Launch Hyprland under uwsm (ADR 0003). uwsm owns graphical-session.target
  # and the wayland-session@Hyprland.target tree, so logout tears the whole
  # session down instead of leaking user services into the next login.
  #
  # withUWSM alone is sufficient. It only sets `programs.uwsm.enable`, but the
  # uwsm session entry does NOT come from programs.uwsm.waylandCompositors —
  # the hyprland package itself ships both sessions
  # (`pkgs.hyprland.providedSessions == [ "hyprland" "hyprland-uwsm" ]`), and
  # the Hyprland module already registers them via
  # `services.displayManager.sessionPackages = [ cfg.package ]`.
  #
  # Do NOT re-add a waylandCompositors.hyprland entry here. It generates a
  # second `hyprland-uwsm.desktop` that shadows the package's own (same
  # basename, same SessionDir) with a worse Exec line:
  #   ours:     uwsm start -F -- /run/current-system/sw/bin/Hyprland
  #   upstream: uwsm start -e -D Hyprland hyprland.desktop
  # Upstream delegates to hyprland.desktop, whose Exec is `start-hyprland` —
  # the supervisor wrapper Hyprland now expects to be launched under.
  # Launching the raw binary instead cost us two things, both observed in the
  # session log: "Hyprland is being launched without start-hyprland. This is
  # highly advised against." and "Failed to change process scheduling
  # strategy" — the latter because security.wrappers.Hyprland holds
  # cap_sys_nice+ep at /run/wrappers/bin/Hyprland and the store path does not.
  # start-hyprland resolves the compositor with execvp (verified via `nm -D`),
  # so PATH decides: /run/wrappers/bin precedes /run/current-system/sw/bin in
  # both the login and systemd-user environments, hence the caps are picked up.
  # Note it does NOT auto-restart on crash — probed with stub binaries exiting
  # 0, exiting 1, and SIGSEGV; all three produced exactly one invocation and
  # logged "Hyprland exit cleanly". So there is no supervision conflict with
  # uwsm's wayland-wm@Hyprland.service, and no crash-loop risk either.
  programs.hyprland.withUWSM = true;

  # Two SDDM entries, deliberately (issue 02).
  #
  # pkgs.hyprland ships BOTH sessions (`providedSessions == [ "hyprland"
  # "hyprland-uwsm" ]`) and programs.hyprland registers the package via
  # services.displayManager.sessionPackages, so reducing SDDM to a single entry
  # would mean filtering that list. We deliberately do NOT: with Plasma gone,
  # the plain `hyprland.desktop` entry is the last in-SDDM fallback if uwsm
  # itself breaks. The remaining fallbacks below it are NixOS generation
  # rollback and `master` (55528b8).
  #
  # `hyprland.desktop` must stay resolvable for a second reason anyway: the
  # uwsm entry's Exec delegates to it BY NAME
  #   uwsm start -e -D Hyprland hyprland.desktop
  # which uwsm looks up in wayland-sessions across XDG_DATA_DIRS.
  #
  # defaultSession (above) preselects the uwsm entry, so the escape hatch costs
  # nothing at login time.
  #
  # NOTE: programs.uwsm.enable forces services.dbus.implementation = "broker"
  # system-wide (still "broker" after Plasma removal — verified by eval). If that
  # ever regresses something, override with
  # `services.dbus.implementation = lib.mkForce "dbus"`.

  # xkb config for the console and the SDDM greeter. NOT tied to
  # services.xserver.enable — the weston greeter reads these values to generate
  # its keymap (see compositorCmds.weston in the sddm module), so this stays
  # even though the X server itself is disabled.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Printing
  services.printing.enable = true;

  # Sound (pipewire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Fingerprint
  services.fprintd.enable = true;
  services.udev.packages = with pkgs; [
    libfprint
  ];
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
  # NOTHING set under `security.pam.services.sddm.*` has any effect. nixpkgs'
  # SDDM module declares that service with `useDefaultRules = false` and a
  # stack that is nothing but delegation (nixos/modules/services/
  # display-managers/sddm.nix:371) —
  #
  #     auth     substack login
  #     account  include  login
  #     password substack login
  #     session  include  login
  #
  # and every convenience flag (fprintAuth, kwallet, gnome-keyring, …) is
  # generated inside `lib.optionalAttrs cfg.useDefaultRules`
  # (nixos/modules/security/pam.nix:952). So SDDM's real auth stack is
  # /etc/pam.d/login, and anything SDDM needs must be configured on `login`.
  # `login` is substacked ONLY by sddm; sudo/polkit-1/su/hyprlock all carry
  # their own stacks, so changes here do not reach them.
  #
  # Consequence: fingerprint at the TTY and password-only at SDDM cannot both
  # be had from these booleans. SDDM cannot run PAM modules in parallel
  # (https://github.com/sddm/sddm/issues/1840), so a `sufficient` pam_fprintd
  # ordered ahead of pam_unix makes SDDM demand a finger before it will even
  # look at the typed password. Password-only login wins: fingerprint is still
  # available where it matters (sudo, polkit, and hyprlock's native fprintd
  # backend), and pam_kwallet5 below needs the typed password in PAM_AUTHTOK
  # anyway — a fingerprint cannot unlock the wallet.
  security.pam.services.login.fprintAuth = false;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.polkit-1.fprintAuth = true;
  # hyprlock has a NATIVE fprintd backend (auth.fingerprint.enabled, configured
  # in nix/home/hyprland.nix via xdg.configFile."hypr/hyprlock.conf") that
  # talks to fprintd over DBus independently of PAM. The password field and
  # the fingerprint reader run in parallel — type a password OR scan a finger.
  # We deliberately do NOT put pam_fprintd.so in /etc/pam.d/hyprlock: a
  # `sufficient` pam_fprintd in the stack makes the password path wait for
  # the fprintd prompt/timeout, so a typed password is followed by a forced
  # fingerprint scan (or a 30s stall). See:
  # https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/#authentication
  # hyprlock falls back to /etc/pam.d/su when /etc/pam.d/hyprlock is missing
  # (we saw `Pam module "/etc/pam.d/hyprlock" does not exist` in the journal
  # after every suspend). Declaring the service here generates the file —
  # this also escapes `su`'s pam_faillock, which can lock the account after
  # repeated failed hyprlock attempts.
  security.pam.services.hyprlock = { fprintAuth = false; };

  # KWallet autounlock at login → pam_kwallet5 takes the session password and
  # hands it to kwalletd6, so the Secret Service portal
  # (org.freedesktop.impl.portal.Secret → KDE portal → kwalletd) is available
  # to libsecret-using apps (Chrome, mpv scripts, etc.) in the Hyprland
  # session. This sits on `login`, not `sddm`, for the reason documented
  # above: `security.pam.services.sddm.kwallet.enable` is silently discarded.
  # Setting it makes the NixOS pam module also insert an early
  # `optional pam_unix` so PAM_AUTHTOK is populated before pam_kwallet5 runs
  # (pam.nix:1203); pam_kwallet5 itself is `optional`, so a failed unlock
  # never blocks login.
  #
  # No `forceRun`: pam_kwallet5 checks XDG_SESSION_TYPE and skips itself on a
  # TTY ("not a graphical session, skipping"), which is what we want — only
  # the SDDM path should start kwalletd.
  #
  # With Plasma gone this is the ONLY thing that opens the wallet; nothing
  # else in the Hyprland session does, so without it every secret lookup
  # raises a wallet-password dialog.
  security.pam.services.login.kwallet.enable = true;

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # Podman
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # User account. home-manager reads `config.users.users.jon.home` to
  # derive the home directory, so `home` must be set explicitly here.
  users.users.jon = {
    isNormalUser = true;
    description = "Jonathan Mast";
    home = "/home/jon";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" "audio" "podman" "dialout" ];
    packages = with pkgs; [
      kdePackages.kate
      # Everything below was previously installed as a side effect of
      # services.desktopManager.plasma6.enable (its `optionalPackages` /
      # `requiredPackages` lists). Plasma is gone as of issue 02, so the KDE
      # software we actually use has to be declared explicitly — ADR 0002
      # ("KDE software is retained standalone").
      #
      # dolphin: bound to $mainMod+E in nix/home/hyprland.nix. It was never
      # declared anywhere in this repo before — it came in purely via plasma6.
      kdePackages.dolphin
      # kservice: provides kbuildsycoca6, which builds the KDE service/menu
      # cache that Dolphin's "Open With → Other Application" tree renders from.
      # Also the tool the XDG_MENU_PREFIX work is verified with
      # (`kbuildsycoca6 --menutest`).
      kdePackages.kservice
      # Theming. plasma6 pulled in breeze-icons + the Qt style; without them
      # KDE apps fall back to the bare `hicolor` theme and render with missing
      # icons. Not a Plasma session dependency — just app-level presentation.
      kdePackages.breeze-icons
      kdePackages.qqc2-desktop-style
    ];
  };

  # NixOS-level zsh support so users.users.jon.shell = pkgs.zsh gets
  # the proper PATH set up (without this, login via zsh can fail).
  programs.zsh.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Silence the x86_64-darwin deprecation error emitted transitively by a
  # flake input (Handy → bun2nix) that enumerates darwin systems. This Linux
  # host never builds darwin, so it is pure noise.
  # nixpkgs 26.11 turned the old warning into a hard throw; `true` (the
  # 26.05 warning-silencer) no longer works — only the string "force" does.
  nixpkgs.config.allowDeprecatedx86_64Darwin = "force";

  environment.systemPackages = with pkgs; [
  ];

  programs.nix-ld.enable = true;
  programs.kdeconnect.enable = true;

  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  system.stateVersion = "25.11";
}
