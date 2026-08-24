{ lib
, stdenv
, fetchFromGitHub
, rustPlatform
, cargo
, rustc
, bun
, nodejs
, pkg-config
, makeWrapper
, webkitgtk_4_1
, gtk3
, glib-networking
, glib
, cairo
, pango
, gdk-pixbuf
, librsvg
, gsettings-desktop-schemas
, openssl
, libsoup_3
, gst_all_1
, libappindicator-gtk3
, wrapGAppsHook3
, mold
, cacert
}:

let
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "cortexkit";
    repo = "magic-context";
    rev = "dashboard-v${version}";
    hash = "sha256-42QYD7uGtE8sWiMRMe1F9FNQG8i4NORHAoaFRGoQx4M=";
  };

  # Vendored node_modules as a fixed-output derivation. Fixed outputs are the
  # only derivations allowed network access under sandbox = true, so this is
  # both hermetic and sandbox-safe — unlike running `bun install` inside the
  # main build. The main derivation then just restores these files offline.
  # Rebuild note: this FOD only changes when src or the bun lockfile change.
  bunModules = stdenv.mkDerivation {
    pname = "magic-context-dashboard-bun-modules";
    inherit version src;

    nativeBuildInputs = [ bun cacert ];

    configurePhase = ''
      runHook preConfigure
      export HOME=$TMPDIR/home
      mkdir -p "$HOME"
      export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      # Bound the install so a stalled connection or failed tarball
      # extraction fails fast instead of hanging the build indefinitely.
      for attempt in 1 2 3; do
        if timeout 300 bun install --frozen-lockfile; then
          break
        elif [ "$attempt" = 3 ]; then
          echo "bun install failed after 3 attempts" >&2
          exit 1
        else
          echo "bun install attempt $attempt failed/timed out, retrying..." >&2
          sleep 5
        fi
      done
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      # bun >= 1.3 defaults to isolated installs: packages live in
      # node_modules/.bun plus per-workspace packages/*/node_modules dirs.
      # Capture the whole installed tree so every workspace's .bin resolves.
      mkdir -p $out/share
      cp -a . $out/share/tree
      runHook postInstall
    '';

    dontFixup = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-9obb+4AEtvCFva2+EJs7YVz57/X220FxvHVgJlILNq4=";
  };
in

stdenv.mkDerivation rec {
  pname = "magic-context-dashboard";
  inherit version src;

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    wrapGAppsHook3
    cargo
    rustc
    mold
    rustPlatform.cargoSetupHook
    bun
    nodejs
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    glib
    glib-networking
    cairo
    pango
    gdk-pixbuf
    librsvg
    gsettings-desktop-schemas
    openssl
    libsoup_3
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    libappindicator-gtk3
  ];

  # Enter src-tauri early so cargo hooks see its Cargo.toml/lock context.
  postPatch = ''
    cd packages/dashboard/src-tauri
  '';

  preBuild = ''
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"

    # Back to repo root for the frontend build.
    cd ../../..

    # Restore the fully-installed bun tree (root + per-workspace
    # node_modules) over the pristine source — offline, sandbox-safe.
    cp -a ${bunModules}/share/tree/. .
    chmod -R u+w ./node_modules ./packages

    # Isolated-install .bin entries are symlinks into node_modules/.bun whose
    # targets carry `#!/usr/bin/env` shebangs that cannot resolve in the
    # sandbox. Patch the TARGET FILES in place — keeping the symlinks intact,
    # since JS bin scripts use relative imports into their own package.
    find node_modules/.bin packages/*/node_modules/.bin -maxdepth 1 -type l \
      > $TMPDIR/bin-links.list 2>/dev/null || true
    while IFS= read -r link; do
      target=$(readlink -f "$link") || continue
      [ -n "$target" ] && [ -f "$target" ] || continue
      [ "$(head -c 2 "$target")" = "#!" ] || continue
      firstLine=$(head -n 1 "$target")
      case "$firstLine" in
        '#!/usr/bin/env '*)
          tool=$(printf '%s' "$firstLine" | sed -e 's|^#!/usr/bin/env ||' -e 's| .*||')
          resolved=$(command -v "$tool") || continue
          sed -i "1s|.*|#!$resolved|" "$target"
          ;;
      esac
    done < $TMPDIR/bin-links.list || true

    # mold links large Tauri binaries several times faster than GNU ld.
    # Applies only to this derivation's cargo invocation.
    export RUSTFLAGS="-Clink-arg=-fuse-ld=mold"

    (
      cd packages/dashboard
      bun run build
    )

    # Back to src-tauri for cargo build
    cd packages/dashboard/src-tauri
  '';

  buildPhase = ''
    runHook preBuild
    
    export HOME=$(mktemp -d)
    cargo build --release --locked
    
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/32x32/apps
    mkdir -p $out/share/icons/hicolor/128x128/apps

    cp target/release/magic-context-dashboard $out/bin/

    cat > $out/share/applications/magic-context-dashboard.desktop << EOF
[Desktop Entry]
Name=Magic Context Dashboard
Exec=$out/bin/magic-context-dashboard
Icon=magic-context-dashboard
Type=Application
Categories=Utility;Development;
EOF

    cp icons/32x32.png $out/share/icons/hicolor/32x32/apps/magic-context-dashboard.png 2>/dev/null || true
    cp icons/128x128.png $out/share/icons/hicolor/128x128/apps/magic-context-dashboard.png 2>/dev/null || true

    runHook postInstall
  '';

  # Expose the FOD so its hash can be harvested/refreshed independently:
  #   nix build .#magic-context-dashboard.passthru.bunModules
  passthru.bunModules = bunModules;

  meta = {
    description = "Magic Context Dashboard — manage memories, context, and sessions";
    homepage = "https://github.com/cortexkit/magic-context";
    license = lib.licenses.mit;
    mainProgram = "magic-context-dashboard";
    platforms = [ "x86_64-linux" ];
  };
}
