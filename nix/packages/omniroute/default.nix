{ lib
, buildNpmPackage
, fetchurl
, nodejs
, makeWrapper
}:

buildNpmPackage rec {
  pname = "omniroute";
  version = "3.8.49";

  src = fetchurl {
    url = "https://registry.npmjs.org/omniroute/-/omniroute-${version}.tgz";
    sha256 = "sha256-fcGsAxOdv1ZSwt24eHJu97lyRATKBw8rYeFvGTRhxYs=";
  };

  sourceRoot = "package";

  npmDepsHash = "sha256-hx+6wDgyhFx4cRPiLMhNmctwZG4s6vFw19uMbZ4v7UY=";

  npmFlags = [ "--legacy-peer-deps" "--ignore-scripts" ];

  dontNpmBuild = true;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  dontAutoPatchelf = true;
  dontConfigure = true;
  dontStrip = true;
  dontFixup = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/omniroute
    cp -r . $out/lib/omniroute/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/omniroute \
      --add-flags "$out/lib/omniroute/bin/omniroute.mjs"
    makeWrapper ${nodejs}/bin/node $out/bin/omniroute-reset-password \
      --add-flags "$out/lib/omniroute/bin/reset-password.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Unified AI router with 160+ providers, RTK+Caveman compression, auto fallback, MCP/A2A, desktop, PWA, and OpenAI-compatible APIs";
    homepage = "https://omniroute.online";
    license = lib.licenses.mit;
    mainProgram = "omniroute";
    platforms = [ "x86_64-linux" ];
  };
}
