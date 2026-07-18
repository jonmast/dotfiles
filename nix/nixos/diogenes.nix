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

  networking.hostName = "diogenes";
  networking.networkmanager.enable = true;

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
  services.displayManager = {
    autoLogin.enable = true;
    autoLogin.user = "jon";
  };
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
  security.pam.services.sddm.fprintAuth = true;

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

  # Silence the x86_64-darwin deprecation warning emitted transitively by a
  # flake input (Handy → bun2nix) that enumerates darwin systems. Official
  # opt-in knob; propagates through the nixpkgs `follows` chain. This Linux
  # host never builds darwin, so the warning is pure noise.
  nixpkgs.config.allowDeprecatedx86_64Darwin = true;

  environment.systemPackages = with pkgs; [
  ];

  programs.nix-ld.enable = true;
  programs.kdeconnect.enable = true;

  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  system.stateVersion = "25.11";
}
