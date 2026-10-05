{ pkgs, inputs, ... }:

let
  # `qs-lint` — qmllint, taught about The Shell. Same arrangement as
  # googletv.nix: the script is a real file so it can be read and run on its
  # own, and this only puts it on PATH with what it needs.
  #
  # The QML tree is deployed as an out-of-store symlink (see hyprland.nix), so
  # it is not built by anything and nothing would ever have noticed a typo in
  # it before the next `systemctl --user restart quickshell`. This is the only
  # check that tree has.
  #
  # Two module paths, both required:
  #   - quickshell's own, for PanelWindow, Process, Singleton and the rest.
  #     Taken from the same pinned flake input hyprland.nix deploys, so the
  #     linter and the running shell can never disagree about the API.
  #   - qtdeclarative's, for QtQuick itself. qmllint does not find it alone.
  quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qs-lint = pkgs.writeShellApplication {
    name = "qs-lint";
    runtimeInputs = [ pkgs.qt6.qtdeclarative ];
    text = ''
      export QS_LINT_ROOT="''${QS_LINT_ROOT:-$HOME/.dotfiles/nix/home/quickshell}"
      export QS_LINT_QML_PATH="${quickshell}/lib/qt-6/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
      exec bash ${./scripts/qs-lint.sh} "$@"
    '';
  };
in
{
  home.packages = [ qs-lint ];
}
