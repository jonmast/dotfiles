{ pkgs, ... }:

let
  # `opencode-update` — installs and updates opencode2, which is deliberately
  # not in home.packages so a daily release needs no rebuild. Same arrangement
  # as qmllint.nix: the script is a real file, this only puts it on PATH with
  # what it needs.
  #
  # The nixpkgs and recipe it builds against are pinned here, so it is built
  # exactly as `.#opencode2` would be, only with the latest tarball.
  # `nix` itself comes from the system PATH to match the daemon.
  opencode-update = pkgs.writeShellApplication {
    name = "opencode-update";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      export OPENCODE_UPDATE_NIXPKGS="${pkgs.path}"
      export OPENCODE_UPDATE_RECIPE="${../packages/opencode2}"
      exec bash ${./scripts/opencode-update.sh} "$@"
    '';
  };
in
{
  home.packages = [ opencode-update ];
}
