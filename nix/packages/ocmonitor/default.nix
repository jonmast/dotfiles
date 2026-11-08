{ lib
, python3Packages
, fetchurl
}:

python3Packages.buildPythonApplication rec {
  pname = "opencode-monitor";
  version = "1.0.5";
  pyproject = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/86/86/ed190499e5edbb8717cea8e01956601a6b9907ed86316818ad92faa29654/opencode_monitor-${version}.tar.gz";
    sha256 = "12v98j9nz96ygapmmf3yx6lm9hvna1p6qcp8cmdfk9jyg45zrcqw";
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
