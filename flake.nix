{
  description = "jon's dotfiles — home-manager + NixOS config";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nub — all-in-one Node.js toolkit (TypeScript runner, pnpm-compatible
    # package manager, Node version manager). Not yet in nixpkgs (PR #535802).
    nub = {
      url = "github:nubjs/nub";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Voxtype comes from nixpkgs now (nix/home/voxtype.nix overrides it with
    # `onnxSupport = true` to get the Parakeet backend). It used to be an input
    # here because nixpkgs had no way to enable those cargo features; that
    # option landed in nixpkgs with voxtype 1.1.1, so the upstream flake is
    # gone. Same local build either way — the ONNX derivation is not
    # cache-substituted.

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Frozen nixpkgs used only for fractal (nix/home/common.nix). Fractal is
    # built via overrideAttrs to carry the hover-reactions patch, so it can
    # never be substituted from the binary cache: every change to its
    # derivation — even a nixpkgs bump that leaves the version at 14.1 — costs
    # a full local Rust build. Pinning the app to the rev the machine was
    # installed from lets `nix flake update` refresh everything else without
    # touching that build. Bump this rev deliberately (and accept the
    # recompile) only when fractal itself needs updating.
    fractal-nixpkgs.url = "github:nixos/nixpkgs/c59305bab2065cfecc4944690d9eedbb56f3a9fa";

  };

  outputs = { self, nixpkgs, home-manager, nub, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # Separate package set for the patched fractal; see the input comment.
      fractalPkgs = import inputs.fractal-nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        ocmonitor = pkgs.callPackage ./nix/packages/ocmonitor { };
        opencode2 = pkgs.callPackage ./nix/packages/opencode2 { };
        openchamber-desktop = pkgs.callPackage ./nix/packages/openchamber { };
        lazyskills = pkgs.callPackage ./nix/packages/lazyskills { };
        helium = pkgs.callPackage ./nix/packages/helium { };
        default = self.packages.${system}.ocmonitor;
      };

      # Validate the Hyprland Lua config against the `hl` API it uses, with no
      # compositor required (hyprland --verify-config only needs a writable
      # XDG_RUNTIME_DIR). Catches API drift on a Hyprland bump; external CLI
      # contracts are runtime-only and handled by Common/BoundaryAlert.qml.
      #
      # core.lua/binds.lua come from the working tree because their deployed
      # copies are out-of-store symlinks absent from the sandbox; paths.lua and
      # voxtype.lua come from the evaluated config.
      checks.${system}.hyprland-config =
        let
          hypr = self.nixosConfigurations.diogenes.config.home-manager.users.jon.wayland.windowManager.hyprland;
        in
        pkgs.runCommand "hyprland-config-check"
          {
            nativeBuildInputs = [ pkgs.hyprland ];
          }
          ''
            export HOME="$TMPDIR/home"
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
            chmod 700 "$XDG_RUNTIME_DIR"

            cp ${./nix/home/hypr/core.lua} core.lua
            cp ${./nix/home/hypr/binds.lua} binds.lua
            cp ${pkgs.writeText "paths.lua" hypr.extraLuaFiles.paths.content} paths.lua
            cp ${pkgs.writeText "voxtype.lua" hypr.extraLuaFiles.voxtype.content} voxtype.lua

            cat > hyprland.lua <<'EOF'
            package.path = "./?.lua;" .. package.path
            require("binds")
            require("core")
            require("voxtype")
            EOF

            result=$(hyprland --verify-config -c ./hyprland.lua 2>&1) || true
            printf '%s\n' "$result"
            if ! printf '%s' "$result" | grep -q "config ok"; then
              echo "hyprland --verify-config did not report 'config ok'" >&2
              exit 1
            fi
            echo "hyprland config check passed" > "$out"
          '';

      # NixOS system config (also activates home-manager for the jon user).
      #   sudo nixos-rebuild switch --flake .#diogenes
      #
      # home-manager runs as a NixOS module (not standalone) so there is a
      # single activation path and a single nixpkgs evaluation. Running both
      # `nixos-rebuild` and a standalone `home-manager switch` for the same
      # user is discouraged upstream — they fight over the same generation
      # profile and a reboot/rebuild can silently revert standalone changes.
      # If a macOS host is ever added it gets its own standalone/nix-darwin
      # output; this Linux host stays module-only.
      nixosConfigurations.diogenes = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./nix/nixos/diogenes.nix
          home-manager.nixosModules.home-manager
          {
            # System-level overlay. With useGlobalPkgs = true, home-manager
            # shares this pkgs set, so it reaches home.packages too.
            nixpkgs.overlays = [
              (final: prev: {
                # Slicing segfaults in Mesa's native GL drivers while rendering
                # plate thumbnails (Orca issues a draw with a NULL index
                # pointer). Zink sidesteps it and stays hardware-accelerated.
                # Drop once fixed: https://github.com/OrcaSlicer/OrcaSlicer/issues/14453
                # Wrapped rather than overridden so the cached build is reused.
                orca-slicer = final.symlinkJoin {
                  name = "orca-slicer-${prev.orca-slicer.version}";
                  paths = [ prev.orca-slicer ];
                  nativeBuildInputs = [ final.makeWrapper ];
                  postBuild = ''
                    wrapProgram $out/bin/orca-slicer \
                      --set MESA_LOADER_DRIVER_OVERRIDE zink
                  '';
                  inherit (prev.orca-slicer) meta version;
                };

                ocmonitor = final.callPackage ./nix/packages/ocmonitor { };
                opencode2 = final.callPackage ./nix/packages/opencode2 { };
                openchamber-desktop = final.callPackage ./nix/packages/openchamber { };
                lazyskills = final.callPackage ./nix/packages/lazyskills { };
                helium = final.callPackage ./nix/packages/helium { };
                nix-search = final.callPackage ./nix/packages/nix-search { };
                nub = nub.packages.${system}.default;
              })
            ];

            home-manager = {
              useGlobalPkgs = true;
              users.jon = { imports = [ ./nix/home/default.nix ]; };
              extraSpecialArgs = { inherit inputs fractalPkgs; };
            };
          }
        ];
      };
    };
}
