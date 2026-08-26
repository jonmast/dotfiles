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

  # X11 + KDE Plasma
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
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
  # Plasma stays for now as the fallback session while uwsm is de-risked
  # (issue 01 adds/rewires only; issue 02 removes Plasma).
  #
  # NOTE: programs.uwsm.enable forces services.dbus.implementation = "broker"
  # system-wide, so the Plasma session gets dbus-broker too. Override with
  # `services.dbus.implementation = lib.mkForce "dbus"` if that regresses.
  services.desktopManager.plasma6.enable = true;

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
  security.pam.services.login.fprintAuth = true;
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
  # SDDM cannot run PAM modules in parallel — this is an open, known
  # architectural issue (https://github.com/sddm/sddm/issues/1840), not a
  # config problem. With fprintd enabled, SDDM waits for the fprintd prompt
  # (or its 30s timeout) before evaluating the typed password, so the user
  # effectively has to enter both. Disable fprintd here so SDDM is
  # password-only; the in-session hyprland lockscreen (above) still
  # supports fingerprint via hyprlock's native backend.
  security.pam.services.sddm.fprintAuth = false;

  # KWallet autounlock on SDDM login → kwallet-pam gets the session password
  # and hands it to ksecretd/kwalletd6, so the Secret Service portal
  # (org.freedesktop.impl.portal.Secret → KDE portal → kwalletd) is
  # available to libsecret-using apps (Chrome, mpv scripts, etc.) in the
  # Hyprland session. fprintd cannot unlock KWallet — the wallet password
  # is the same as the user password, so unlocking happens at the
  # post-fingerprint password step. The service entry is generated by
  # NixOS as /etc/pam.d/kwallet with control=optional, so a fprint-only
  # login still succeeds and the wallet just stays locked until the
  # password is entered.
  security.pam.services.sddm.kwallet.enable = true;

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
