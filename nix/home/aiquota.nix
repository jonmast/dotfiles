{ pkgs, ... }:

let
  # The collector behind the bar's AI quota pill
  # (nix/home/quickshell/Bar/AiQuotaWidget.qml). Kept as a real file in the repo
  # rather than inlined here so it stays runnable and diffable on its own —
  # `python3 nix/home/scripts/ai-quota.py | jq` is the whole debugging story,
  # and it needs no rebuild.
  #
  # Stdlib only, like omarchy's collectors, and Sextant needs no credentials,
  # so the dependency surface is just the interpreter. That matters because
  # this runs every minute from the bar.
  ai-quota = pkgs.writeShellApplication {
    name = "ai-quota";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./scripts/ai-quota.py} "$@"
    '';
  };
in
{
  home.packages = [ ai-quota ];
}
