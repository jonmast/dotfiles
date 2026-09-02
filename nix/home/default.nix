{ config, pkgs, lib, handy, inputs, ... }:

{
  imports = [
    ./common.nix
    ./linux.nix
    ./hyprland.nix
    ./aiquota.nix
    # Hermes Agent + Hermes Desktop (Electron app). The upstream module adds
    # `hermes` and `hermes-desktop` to home.packages, wires the launcher to
    # the Nix runtime via HERMES_DESKTOP_HERMES, and exports HERMES_HOME.
    # Gateway/daemon options live under services.hermes-agent if ever needed
    # (they require `users.users.jon.linger = true` at the system level).
    inputs.hermes-agent.homeManagerModules.default
  ];

  programs.hermes-agent = {
    enable = true; # hermes CLI on PATH, sharing ~/.hermes with the desktop
    desktop.enable = true; # Hermes Desktop app + XDG launcher entry
  };

  # Home Manager needs basic identity info.
  home.username = "jon";
  home.homeDirectory = "/home/jon";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  home.stateVersion = "25.11";

  # Allow standalone `home-manager` CLI to manage itself.
  programs.home-manager.enable = true;
}
