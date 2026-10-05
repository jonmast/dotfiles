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
      exclude         = [
        "/home/jon/.cache" ".cache" ".local/share/Trash"
        # Rootless podman storage is owned by subuids and unreadable to restic.
        # Image layers are re-pullable; volumes are exported below instead.
        "/home/jon/.local/share/containers/storage"
      ];
      backupPrepareCommand = ''
        export PATH=/run/wrappers/bin:/run/current-system/sw/bin:$PATH
        out="$HOME/.local/share/podman-volume-exports"
        rm -rf "$out"
        mkdir -p "$out"
        for v in $(podman volume ls -q); do
          podman volume export -o "$out/$v.tar" "$v" || echo "failed to export volume $v" >&2
        done
      '';
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
  systemd.user.services."restic-backups-homebackup" = {
    Unit.ConditionACPower = true;
    # Exit 3 = snapshot saved but some files were unreadable; keep going to prune/check.
    Service.SuccessExitStatus = 3;
  };
}
