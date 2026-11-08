{ lib
, stdenv
, fetchurl
}:

stdenv.mkDerivation rec {
  pname = "lazyskills";
  version = "1.2.0";

  src = fetchurl {
    url = "https://github.com/alvinunreal/lazyskills/releases/download/v${version}/lazyskills_Linux_x86_64.tar.gz";
    sha256 = "0bx5j17fijmarmbrcvkcb1avjmiyhj0y5k3d3a7yxmcx462mklzn";
  };

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp lazyskills $out/bin/lazyskills
    chmod +x $out/bin/lazyskills
  '';

  meta = {
    description = "Blazing-fast mission control for agent skills (TUI + CLI)";
    homepage = "https://github.com/alvinunreal/lazyskills";
    license = lib.licenses.mit;
    mainProgram = "lazyskills";
    platforms = [ "x86_64-linux" ];
  };
}
