#!/usr/bin/env sh
# Bump omniroute to the newest version.
#
# Usage:
#   scripts/update-omniroute.sh            # bump to latest
#   scripts/update-omniroute.sh 3.8.49     # bump to specific version
#
# How it works:
#   1. Reads the newest version from npm (or uses the version argument).
#   2. Runs `nix-update`, which rewrites version + recomputes the SRI hash
#      by building the new tarball itself (no manual downloading/hashing).
set -e
cd "$(dirname "$0")/.."

pkg="omniroute"

if [ -n "$1" ]; then
  ver="$1"
else
  ver=$(curl -s "https://registry.npmjs.org/$pkg" | jq -r '."dist-tags".latest // empty')
fi

if [ -z "$ver" ]; then
  echo "error: could not determine version for $pkg" >&2
  exit 1
fi

echo "Bumping omniroute to $ver"
nix run nixpkgs#nix-update -- \
  --flake packages.x86_64-linux.omniroute \
  --version "$ver" \
  --override-filename nix/packages/omniroute/default.nix
