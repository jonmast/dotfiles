{ lib
, stdenv
, fetchurl
, appimageTools
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, git
, openssh
, python3
, nodejs
, cloudflared
, less
, ripgrep
, coreutils
, gnutar
, bzip2
}:

# OpenChamber Desktop, repackaged from the upstream Linux AppImage release.
#
# OpenChamber is the Electron workspace around the OpenCode CLI. Upstream's
# flake builds both the app and a pinned OpenCode from source, which would pull
# a second OpenCode source build into the closure; the AppImage is the artifact
# their release pipeline actually tests and it bundles its own OpenCode CLI
# (see resources/opencode-cli/opencode, currently 2.0.32 while our system
# opencode2 tracks the npm line independently).
#
# The AppImage is wrapped with appimageTools.wrapType2 rather than unpacked
# into a plain derivation: the bundled OpenCode CLI and ripgrep are Ubuntu
# binaries with a /lib64 interpreter, and the FHS environment is what lets them
# run unpatched. Electron also needs the AppImage's own shared libraries, which
# the same environment provides.
#
# Bump:
#   1. curl -fsSL https://api.github.com/repos/openchamber/openchamber/releases/latest | jq -r .tag_name
#   2. edit `version` below
#   3. nix store prefetch-file --json \
#        https://github.com/openchamber/openchamber/releases/download/v<version>/OpenChamber-<version>-linux-x86_64.AppImage
#      and paste the `hash` into `src.hash`.

stdenv.mkDerivation (finalAttrs: let
  # Read the icon out of the release artifact instead of hand-copying it, so a
  # rebrand upstream carries over on the next bump.
  extracted = appimageTools.extract {
    pname = "openchamber-desktop";
    inherit (finalAttrs) version src;
  };

  wrapped = appimageTools.wrapType2 {
    pname = "openchamber-desktop";
    inherit (finalAttrs) version src;

    # Runtime PATH parity with upstream's nix/package.nix and nix/gui.nix:
    # the app shells out to git, ssh, python and cloudflared, and unpacks the
    # local dictation model with tar/bzip2. ripgrep is bundled in the AppImage
    # but git/MCP integrations also look for `rg` on PATH.
    extraPkgs = pkgs: [
      git
      openssh
      python3
      nodejs
      cloudflared
      less
      ripgrep
      coreutils
      gnutar
      bzip2
    ];
  };
in {
  pname = "openchamber-desktop";
  version = "2.5.0";

  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${finalAttrs.version}/OpenChamber-${finalAttrs.version}-linux-x86_64.AppImage";
    hash = "sha256-+QUnw1N9KMPwnJp/mv/G/S73NzFwm588kuMlwVeuGc8=";
  };

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "openchamber";
      desktopName = "OpenChamber";
      comment = "Desktop workspace for OpenCode";
      exec = "openchamber-desktop %U";
      icon = "openchamber";
      categories = [ "Development" ];
      startupWMClass = "openchamber";
      mimeTypes = [ "x-scheme-handler/openchamber" ];
      terminal = false;
    })
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    # The AppImage's own desktop entry passes --no-sandbox: the chrome-sandbox
    # helper needs to be setuid, which it cannot be in the store, and Electron
    # falls back to the namespace sandbox otherwise. Keep the flag in the
    # wrapper too so launching from a terminal behaves like the menu entry.
    makeWrapper ${wrapped}/bin/openchamber-desktop $out/bin/openchamber-desktop \
      --add-flags "--no-sandbox"

    install -Dm644 ${extracted}/usr/share/icons/hicolor/512x512/apps/openchamber.png \
      $out/share/icons/hicolor/512x512/apps/openchamber.png

    runHook postInstall
  '';

  meta = {
    description = "Desktop workspace for OpenCode sessions";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = "openchamber-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
