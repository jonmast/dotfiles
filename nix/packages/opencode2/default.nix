{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeBinaryWrapper
, installShellFiles
, ripgrep
, wayland
}:

# OpenCode v2, repackaged from the prebuilt npm tarball that upstream's own
# installer (opencode.ai/v2/install) downloads.
#
# We used to build from the `v2` tag via upstream's flake. Two reasons not to:
#
#   1. Upstream pins `bun@1.4.2` and *hard-errors* outside `^1.4.2`, but their
#      nix/opencode.nix patches that check down to a warning because nixpkgs
#      only has bun 1.3.13. The resulting binary embeds 1.3.13 as its runtime,
#      which upstream never tests — the plugin loader misbehaves there.
#   2. The v2 flake is not CI-tested (only the v1 `dev` branch is), so it
#      shipped a stale node_modules hash and installed `bin/opencode2` from a
#      build that emits `bin/opencode`. Both needed local workarounds.
#
# The tarball is the artifact upstream's release pipeline actually publishes
# and tests. Note the npm package is built from the tip of `v2` (see the
# `metadata.github.sha` in the update API), one commit *before* the `release:`
# commit the matching git tag points at.
#
# Bump:
#   1. curl -fsSL https://opencode.ai/update/api/beta/cli/npm   # current version
#   2. edit `version` below
#   3. nix store prefetch-file --json \
#        https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-<version>.tgz
#      and paste the `hash` into `src.hash`.

stdenv.mkDerivation (finalAttrs: {
  pname = "opencode2";
  version = "2.0.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-S4wsrWcpfHFa3/GKVpyICLIv4jxxl/0XdbwRy/oEAi0=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeBinaryWrapper
    installShellFiles
  ];

  # The tarball is a single ~200MB bun-compiled executable at package/bin/opencode.
  # Upstream's installer renames it; we do too, because everything here
  # (nix/home/common.nix, the voxtype scripts, ocmonitor) calls it `opencode2`.
  installPhase = ''
    runHook preInstall

    install -Dm755 bin/opencode $out/bin/opencode2

    runHook postInstall
  '';

  # libwayland-client.so.0 is dlopen'd at runtime by @opentui/core's native
  # clipboard backend (packages/native/src/clipboard/wayland.zig), so it is
  # invisible to autoPatchelf. Without it on the library path the Wayland
  # backend silently fails to load and pasting into the TUI is broken. This is
  # the single reason a wrapper is required rather than a bare binary — the
  # curl-installed copy in ~/.opencode has the same bug and no way to fix it.
  #
  # ripgrep matches upstream's own wrapper: opencode shells out to `rg`.
  # A bun-compiled executable carries its payload in trailing sections; let
  # autoPatchelf rewrite the interpreter but leave the rest alone.
  dontStrip = true;

  # autoPatchelfHook normally runs at the *end* of fixupPhase, i.e. after
  # postFixup. We need it before, because the completion scripts below come
  # from executing the binary and an unpatched one asks for a /lib64
  # interpreter that does not exist here. So: opt out of the automatic run and
  # invoke it first, by hand.
  dontAutoPatchelf = true;

  #
  # It is `--completions <shell>`, not the `completion` subcommand upstream's
  # nix/opencode.nix invokes — that one has been parsed as a directory argument
  # for at least as long as v2 has existed, so the completions in the old
  # source build were a captured ENOENT error message, not a script. The
  # scripts bind themselves to the name `opencode`, so rename them to the name
  # we actually install; every identifier in them is consistently `_opencode*`.
  postFixup = ''
    autoPatchelf $out/bin

    wrapProgram $out/bin/opencode2 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland ]}

    export HOME=$(mktemp -d)
    export OPENCODE_DISABLE_MODELS_FETCH=1
    for shell in bash zsh fish; do
      $out/bin/opencode2 --completions $shell \
        | sed 's/opencode/opencode2/g' > completions.$shell
    done
    installShellCompletion --cmd opencode2 \
      --bash completions.bash \
      --zsh completions.zsh \
      --fish completions.fish
  '';

  meta = {
    description = "The open source coding agent (v2), from the upstream npm release artifact";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
