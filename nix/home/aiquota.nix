{ pkgs, ... }:

let
  # The collector behind the bar's AI quota pill
  # (nix/home/quickshell/Bar/AiQuotaWidget.qml). Kept as a real file in the repo
  # rather than inlined here so it stays runnable and diffable on its own —
  # `python3 nix/home/scripts/ai-quota.py | jq` is the whole debugging story,
  # and it needs no rebuild.
  #
  # Stdlib only, like omarchy's collectors. The dependency surface is therefore
  # just the interpreter plus kwallet-query for the admin key, which matters
  # because this runs every minute from the bar.
  ai-quota = pkgs.writeShellApplication {
    name = "ai-quota";
    runtimeInputs = [
      pkgs.python3
      # Provides kwallet-query. The key lives in kdewallet under cpamp/admin-key
      # and is never written to the store, the environment, or the process
      # table — the wallet is already unlocked at login by kwallet-pam
      # (CONTEXT.md, "KDE infra").
      pkgs.kdePackages.kwallet
    ];
    text = ''
      exec python3 ${./scripts/ai-quota.py} "$@"
    '';
  };
in
{
  home.packages = [ ai-quota ];
}
