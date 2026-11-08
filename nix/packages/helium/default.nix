{ lib
, fetchurl
, appimageTools
}:

# Helium browser, repackaged from the upstream Linux AppImage release.
#
# Not in nixpkgs. Helium is ungoogled-chromium plus its own patches; building
# that from source is a multi-hour Chromium build, so the AppImage — the
# artifact upstream ships and tests — is wrapped with appimageTools.wrapType2
# instead. The FHS environment supplies the system libraries the bundled
# Chromium expects. Unlike openchamber, no --no-sandbox: Chromium's namespace
# sandbox works inside the bwrap environment, and a browser should keep it.
#
# Its in-app updater cannot write to the store; bump here and rebuild.
#
# Bump:
#   1. curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest | jq -r .tag_name
#   2. edit `version` below
#   3. nix store prefetch-file --json \
#        https://github.com/imputnet/helium-linux/releases/download/<version>/helium-<version>-x86_64.AppImage
#      and paste the `hash` into `src.hash`.

let
  pname = "helium";
  version = "0.21.1.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-pivECBuZcJsxFxZc96vnER07VEZxqxcjL0KbmwVEs/o=";
  };

  extracted = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # The AppImage's desktop entry already execs `helium`, the name wrapType2
  # gives the binary, and carries the WebBrowser category and http(s) MIME
  # types, so it is installed as-is.
  extraInstallCommands = ''
    install -Dm644 ${extracted}/helium.desktop $out/share/applications/helium.desktop
    install -Dm644 ${extracted}/usr/share/icons/hicolor/256x256/apps/helium.png \
      $out/share/icons/hicolor/256x256/apps/helium.png
  '';

  meta = {
    description = "Private, fast, and honest web browser based on ungoogled-chromium";
    homepage = "https://helium.computer";
    license = lib.licenses.gpl3Only;
    mainProgram = "helium";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
