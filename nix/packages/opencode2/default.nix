{ lib
, stdenv
, fetchurl
}:

stdenv.mkDerivation rec {
  pname = "opencode2";
  version = "0.0.0-next-16493";

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/cli-linux-x64/-/cli-linux-x64-${version}.tgz";
    sha256 = "1g1rp21zvxbnkxz9w9124ang5zshaf7vh1f0by8nyq3i9bmvzgl3";
  };

  sourceRoot = "package";

  # CRITICAL: patchelf corrupts the .bun ELF section that contains the
  # embedded JavaScript bundle. The binary already uses /lib64/ld-linux
  # which resolves through nix-ld on NixOS. Do NOT modify the binary.
  # patchelf and strip both corrupt the .bun ELF section
  dontAutoPatchelf = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontFixup = true;
  dontPatchELF = true;

  installPhase = ''
    mkdir -p $out/bin
    cp bin/opencode2 $out/bin/opencode2
    chmod +x $out/bin/opencode2
  '';

  meta = {
    description = "The AI CLI that fits your workflow — opencode v2";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    platforms = [ "x86_64-linux" ];
  };
}
