#!/usr/bin/env sh
# Bump opencode2 to the newest build without manual hash computation.
#
# Usage:
#   scripts/update-opencode2.sh            # bump to newest "next" build
#   scripts/update-opencode2.sh beta       # bump to newest "beta" build
#   scripts/update-opencode2.sh latest     # bump to newest stable
#
# How it works:
#   1. Reads the newest version for the chosen dist-tag straight from npm.
#   2. Runs `nix-update`, which rewrites version + recomputes the SRI hash
#      by building the new tarball itself (no manual downloading/hashing).
set -e
cd "$(dirname "$0")/.."

pkg="@opencode-ai/cli-linux-x64"
tag="${1:-next}"

ver=$(curl -s "https://registry.npmjs.org/$pkg" | jq -r --arg t "$tag" '."dist-tags".[$t] // empty')
if [ -z "$ver" ]; then
  echo "error: no dist-tag '$tag' found on npm for $pkg" >&2
  exit 1
fi

echo "Bumping opencode2 to $ver (dist-tag: $tag)"
nix run nixpkgs#nix-update -- \
  --flake packages.x86_64-linux.opencode2 \
  --version "$ver" \
  --override-filename nix/packages/opencode2/default.nix
