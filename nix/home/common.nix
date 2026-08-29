{ config, pkgs, lib, handy, ... }:

let
  fractalPatched = pkgs.fractal.overrideAttrs (old: {
    patches = old.patches ++ [ ../patches/fractal-hover-reactions.patch ];
  });
in
{
  # Handy speech-to-text: started by XDG autostart, NOT by
  # handy.homeManagerModules.default and not by a unit of our own.
  #
  # The upstream module runs the GUI directly with Restart=on-failure, so any
  # close attempt respawns it 5s later ("cannot be closed" loop). We used to
  # replace it with our own `handy.service` running `handy --start-hidden`,
  # which fixed that but created a worse bug: Handy ALSO writes its own
  # ~/.config/autostart/Handy.desktop (its "launch at login" setting), whose
  # Exec carries no --start-hidden. That entry won the race at login, so the
  # unit's process ran into Tauri's single-instance plugin, which ignores the
  # arguments it was given, tells the LIVE instance to show its window, and
  # exits 0. The unit therefore never stayed active — and home-manager starts
  # enabled-but-inactive units on every activation, so every single rebuild
  # popped Handy's window. Two instances also meant
  # "register_tauri_shortcut duplicate error: Shortcut 'ctrl+space' is already
  # in use" in the logs.
  #
  # So there is exactly one start path now, and we own its arguments: the
  # autostart entry itself, with --start-hidden, deployed read-only from the
  # store. Read-only matters — it is what stops Handy rewriting the flag back
  # out from under us. `Terminal=false` and `StartupNotify=false` are Handy's
  # own values, kept.
  #
  # Consequences worth knowing:
  #   - systemd's xdg-autostart generator turns this into
  #     `app-Handy@autostart.service` (uwsm drops it into app-graphical.slice
  #     and makes it stoppable with the session). That is the unit to poke:
  #     `systemctl --user restart app-Handy@autostart.service`.
  #   - Nothing restarts it on a rebuild, which is the point. A new Handy
  #     version therefore only takes effect at the next login or an explicit
  #     restart of that unit.
  #   - Handy's in-app "launch at login" toggle can no longer write here. The
  #     toggle is this file.
  xdg.configFile."autostart/Handy.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=Handy
    Comment=Handy speech-to-text (background, tray)
    Exec=${handy.packages.${pkgs.system}.handy}/bin/handy --start-hidden
    StartupNotify=false
    Terminal=false
  '';

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
    nmap
    nodejs
    ocmonitor
    omniroute
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
  ] ++ [ handy.packages.${pkgs.system}.handy ];

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
