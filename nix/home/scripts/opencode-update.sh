#!/usr/bin/env bash
#
# Install the latest opencode2 npm release into a user profile, no rebuild.
#
# Builds the repo's own recipe (nix/packages/opencode2) with version and hash
# swapped for the latest npm release, and points a dedicated profile at it.
# That profile is the only opencode2 on the machine; its bin/ reaches PATH via
# dot_zshrc, so only shells see it.
#
# Usage:
#   opencode-update             # install latest if newer than the profile
#   opencode-update --force     # rebuild even if already up to date
#   opencode-update --check     # only report current vs latest
#   opencode-update --rollback  # back to the previous profile generation
#   opencode-update --remove    # drop the profile (uninstalls opencode2)
#
# Expects OPENCODE_UPDATE_NIXPKGS and OPENCODE_UPDATE_RECIPE (set by the
# wrapper in nix/home/opencode-update.nix).

set -euo pipefail

readonly PACKAGE_URL="https://registry.npmjs.org/@opencode/cli-linux-x64"
readonly KEEP_GENERATIONS=5
readonly profile="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/opencode2"
: "${OPENCODE_UPDATE_NIXPKGS:?not set}" "${OPENCODE_UPDATE_RECIPE:?not set}"

usage() {
  sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

mode=update
force=0
while (($#)); do
  case $1 in
    --force) force=1 ;;
    --check) mode=check ;;
    --rollback) mode=rollback ;;
    --remove) mode=remove ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case $mode in
  rollback)
    nix-env --profile "$profile" --rollback
    "$profile/bin/opencode2" --version
    exit 0
    ;;
  remove)
    rm -fv "$profile" "$profile"-*-link
    echo "removed; run opencode-update to reinstall"
    exit 0
    ;;
esac

current=none
if [[ -e $profile ]]; then
  current=$(basename "$(readlink -f "$profile")")
  current=${current#*-opencode2-}
fi

echo "current: $current"
latest=$(curl -fsSL "$PACKAGE_URL" | jq -er '."dist-tags".latest')
if [[ ! $latest =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
  echo "npm returned an unusable version: $latest" >&2
  exit 1
fi
echo "latest:  $latest"

if [[ $mode == check ]]; then
  exit 0
fi
if [[ $latest == "$current" && $force -eq 0 ]]; then
  echo "already up to date (use --force to rebuild anyway)"
  exit 0
fi

tarball="$PACKAGE_URL/-/cli-linux-x64-$latest.tgz"
echo "prefetching $tarball"
hash=$(nix store prefetch-file --json "$tarball" | jq -er '.hash')

echo "building opencode2 $latest"
mkdir -p "$(dirname "$profile")"
nix build --impure --profile "$profile" --expr "
  let pkgs = import $OPENCODE_UPDATE_NIXPKGS { config = { }; overlays = [ ]; };
  in (pkgs.callPackage $OPENCODE_UPDATE_RECIPE { }).overrideAttrs {
    version = \"$latest\";
    src = pkgs.fetchurl { url = \"$tarball\"; hash = \"$hash\"; };
  }
"

nix-env --profile "$profile" --delete-generations "+$KEEP_GENERATIONS" >/dev/null
echo "installed: $("$profile/bin/opencode2" --version)"
