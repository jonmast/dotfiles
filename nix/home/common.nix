{ config, pkgs, lib, ... }:

let
  fractalPatched = pkgs.fractal.overrideAttrs (old: {
    patches = old.patches ++ [ ../patches/fractal-hover-reactions.patch ];
  });
in
{
  home.packages = with pkgs; [
    atool
    anki
    bat
    # bitwarden-desktop
    bun
    cargo
    chezmoi
    clippy
    delta
    dig
    ffmpeg
    file
    fluxcd
    fractalPatched  # patch enabled — see top of file
    freecad-wayland
    fzf
    gdu
    ghostty
    gh
    git
    herdr
    htop
    jq
    k9s
    kdePackages.kdeconnect-kde
    lazyskills
    kubeconform
    kubectl
    kubectl-cnpg
    kubernetes-helm
    kustomize
    libhdhomerun
    gcc
    gnumake
    moonlight-qt
    neovim
    nixd
    nix-ld
    nix-search
    nmap
    nodejs
    nub
    ocmonitor
    opencode2
    orca-slicer
    pi-coding-agent
    pv-migrate
    python3
    restic
    ripgrep
    rustfmt
    rustc
    sops
    starship
    strace
    tmux
    tmuxai
    unzip
    usbutils
    uv
    vlc
    wl-clipboard
    yq
    zoxide
    zsh
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # ".screenrc".source = dotfiles/screenrc;
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #   ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  # or
  #   ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  # or
  #   /etc/profiles/per-user/jon/etc/profile.d/hm-session-vars.sh
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  programs.firefox = {
    enable = true;
    # nativeMessagingHosts = [ pkgs.bitwarden-desktop ];
    configPath = ".mozilla/firefox";
  };

  programs.gpg.enable = true;

  # direnv: auto-load per-project flake dev shells (e.g. k8s-conf .envrc).
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  xdg.mime.enable = true;
  xdg.systemDirs.data = [
    "${config.home.homeDirectory}/.nix-profile/share"
  ];
}
