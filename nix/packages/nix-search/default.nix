{ pkgs, lib }:

let
  # Standard NixOS options JSON for this system's nixpkgs version.
  # Fetched from cache.nixos.org — no local build needed on the first run.
  optionsJSON =
    (import (pkgs.path + "/nixos") {
      configuration = { };
      system = pkgs.stdenv.hostPlatform.system;
    }).config.system.build.manual.optionsJSON;

  # Pre-process 25k options into a TSV: type | name | description | type_str | default
  # Built once and cached; rebuilds only when nixpkgs changes.
  optionsTsv = pkgs.runCommand "nixos-options-tsv" {
    nativeBuildInputs = [ pkgs.jq ];
    src = optionsJSON;
  } ''
    jq -r '
      to_entries[]
      | select(.key | startswith("_") | not)
      | [
          "opt",
          .key,
          (
            (.value.description // "")
            | gsub("[\\n\\r\\t]"; " ")
            | gsub("<[^>]+>"; "")
            | ltrimstr(" ")
            | .[0:110]
          ),
          (.value.type // ""),
          (
            if .value.default == null then ""
            elif (.value.default | type) == "object" and (.value.default | has("text"))
            then .value.default.text | gsub("[\\n\\r]"; " ") | .[0:60]
            else (.value.default | tostring | gsub("[\\n\\r]"; " ") | .[0:60])
            end
          )
        ]
      | @tsv
    ' "$src/share/doc/nixos/options.json" > "$out"
  '';

  # ctrl-s: open a nix shell for the selected package in a new ghostty window
  ctrlSBin = pkgs.writeShellScript "nix-search-ctrl-s" ''
    TYPE="$1"
    NAME="$2"
    if [[ "$TYPE" == pkg ]]; then
      ghostty -e nix shell "nixpkgs#$NAME" &
    fi
  '';

  # ctrl-o: open the selection on search.nixos.org
  ctrlOBin = pkgs.writeShellScript "nix-search-ctrl-o" ''
    TYPE="$1"
    NAME="$2"
    if [[ "$TYPE" == opt ]]; then
      xdg-open "https://search.nixos.org/options?query=$NAME" &
    else
      xdg-open "https://search.nixos.org/packages?query=$NAME" &
    fi
  '';

  # Preview pane helper — called by fzf --preview with field references as args.
  # Uses the full PATH set at build time so it doesn't rely on the user's session PATH.
  previewBin = pkgs.writeShellScript "nix-search-preview" ''
    set -euo pipefail
    export PATH="${pkgs.nix}/bin:${pkgs.jq}/bin:$PATH"

    TYPE="''${1:-}"
    NAME="''${2:-}"
    DESC="''${3:-}"
    OPT_TYPE="''${4:-}"
    OPT_DEFAULT="''${5:-}"

    case "$TYPE" in
      opt)
        printf '\033[1m%s\033[0m\n' "$NAME"
        printf '\033[2mType:\033[0m    %s\n' "$OPT_TYPE"
        [[ -n "$OPT_DEFAULT" ]] && printf '\033[2mDefault:\033[0m %s\n' "$OPT_DEFAULT"
        printf '\n%s\n' "$DESC"
        # Show evaluated value from the running system if available
        if result=$(/run/current-system/sw/bin/nixos-option "$NAME" 2>/dev/null); then
          printf '\n\033[2m──── evaluated value ────\033[0m\n%s\n' "$result"
        fi
        ;;
      pkg)
        printf '\033[1m%s\033[0m\n\n' "$NAME"
        nix search nixpkgs "^$NAME\$" --json 2>/dev/null \
          | jq -r '.[] | "Version:  \(.version // "?")\n\n\(.description // "")"' \
          2>/dev/null \
          || printf '%s\n' "$DESC"
        ;;
    esac
  '';

  # Reload command — called by fzf change:reload binding with {q} as first arg.
  # Always emits the full options list; appends live package search when query >= 2 chars.
  reloadBin = pkgs.writeShellScript "nix-search-reload" ''
    set -euo pipefail
    export PATH="${pkgs.nix}/bin:${pkgs.jq}/bin:$PATH"

    QUERY="''${1:-}"
    OPTIONS_TSV="''${2:-}"

    # Options are pre-built; emit unconditionally for fzf to filter
    cat "$OPTIONS_TSV"

    # Package search: live via nix search, only for non-trivial queries
    if [[ ''${#QUERY} -ge 2 ]]; then
      nix search nixpkgs "$QUERY" --json 2>/dev/null \
        | jq -r '
            to_entries[]
            | [
                "pkg",
                (.key | split(".") | last),
                (.value.description // "" | gsub("[\\n\\r\\t]"; " ") | .[0:110]),
                "package",
                (.value.version // "")
              ]
            | @tsv
          ' 2>/dev/null \
        || true
    fi
  '';

in

pkgs.writeShellApplication {
  name = "nix-search";
  runtimeInputs = with pkgs; [ fzf wl-clipboard ];
  text = ''
    OPTIONS_TSV="${optionsTsv}"

    result=$(
      cat "$OPTIONS_TSV" \
      | fzf \
          --ansi \
          --layout=reverse \
          --prompt="  nix  > " \
          --header="ENTER copy · CTRL-S nix shell (pkg) · CTRL-O nixos.org" \
          --query="''${*:-}" \
          --delimiter=$'\t' \
          --with-nth=1,2,3 \
          --preview="${previewBin} {1} {2} {3} {4} {5}" \
          --preview-window="right:50%:wrap" \
          --bind="change:reload:${reloadBin} {q} $OPTIONS_TSV" \
          --bind="ctrl-s:execute:${ctrlSBin} {1} {2}" \
          --bind="ctrl-o:execute:${ctrlOBin} {1} {2}"
    )

    if [[ -n "$result" ]]; then
      name=$(printf '%s' "$result" | cut -f2)
      printf '%s' "$name" | wl-copy
      echo "$name"
    fi
  '';
}
