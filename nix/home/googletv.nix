{ pkgs, ... }:

let
  # The bridge behind the bar's Google TV pill
  # (nix/home/quickshell/Bar/GoogleTv.qml). Same arrangement as ai-quota: the
  # script is a real file so it can be run and read on its own, and this only
  # puts it on PATH with its one dependency.
  #
  # androidtvremote2 speaks the Android TV Remote protocol v2 — the same one
  # the Google TV phone app uses — so no developer options or ADB on the TV,
  # just a one-time PIN pairing from the widget's panel.
  googletv-remote = pkgs.writeShellApplication {
    name = "googletv-remote";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [ ps.androidtvremote2 ]))
    ];
    text = ''
      exec python3 ${./scripts/googletv-remote.py} "$@"
    '';
  };
in
{
  home.packages = [ googletv-remote ];
}
