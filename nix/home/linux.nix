{ config, pkgs, lib, ... }:

{
  # nix-ld lets you run precompiled linux binaries that need glibc.
  home.sessionVariables = {
    NIX_LD_LIBRARY_PATH = with pkgs; lib.makeLibraryPath [
      stdenv.cc.cc.lib
    ];
    NIX_LD = lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker";
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  # Restic backup to sftp server on the LAN.
  services.restic.enable = true;
  services.restic.backups = {
    homebackup = {
      repository      = "sftp:root@192.168.1.155:/mnt/spinners/diogenes-backup";
      passwordFile    = "/etc/nixos/secrets/restic-password";
      paths           = [ "/home/jon" "/etc/nixos/configuration.nix" ];
      exclude         = [ "/home/jon/.cache" ".cache" ".local/share/Trash" ];
      timerConfig     = { OnCalendar = "daily"; Persistent = true; };
      pruneOpts       = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
      runCheck        = true;
      checkOpts       = [ "--with-cache" ];
      createWrapper   = true;   # adds `restic-homebackup` helper to your PATH
      extraOptions    = [
        "sftp.command='ssh root@192.168.1.155 -F none -s sftp'"
      ];
    };
  };
  systemd.user.services."restic-backups-homebackup".Unit = {
    ConditionACPower = true;
  };

  # OmniRoute AI router server
  systemd.user.services.omniroute = {
    Unit = {
      Description = "OmniRoute AI router server";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${config.home.homeDirectory}/.nix-profile/bin/omniroute serve --no-open --no-tray";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
