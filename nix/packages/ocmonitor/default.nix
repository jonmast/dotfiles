{ lib
, python3Packages
, fetchurl
}:

python3Packages.buildPythonApplication rec {
  pname = "opencode-monitor";
  version = "1.0.4";
  pyproject = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/46/d3/026ced16f0d8d2040eef54762389b41871a51f79eacb45a5a8cfcc6bfb6c/opencode_monitor-${version}.tar.gz";
    sha256 = "1krp7plgak3wqmc2pmwc8nhcg46hnnvz6b5n7lvw180dycyidix2";
  };

  build-system = with python3Packages; [
    setuptools
    wheel
  ];

  dependencies = with python3Packages; [
    click
    rich
    pydantic
    toml
    pyyaml
    prometheus-client
  ];

  pythonImportsCheck = [ "ocmonitor" ];

  meta = {
    description = "CLI tool for monitoring and analyzing OpenCode AI coding sessions";
    homepage = "https://github.com/Shlomob/ocmonitor-share";
    license = lib.licenses.mit;
    mainProgram = "ocmonitor";
  };
}
