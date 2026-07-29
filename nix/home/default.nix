{ config, pkgs, lib, handy, ... }:

{
  imports = [
    ./common.nix
    ./linux.nix
    ./hyprland.nix
  ];

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
