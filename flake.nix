{
  description = "jon's dotfiles — home-manager + NixOS config";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pin a known-good nixpkgs for orca-slicer. 2.3.2 in nixos-unstable
    # is broken (graphical plates won't open):
    # https://github.com/OrcaSlicer/OrcaSlicer/issues/13137
    nixpkgs-orca.url = "github:nixos/nixpkgs/62efab0dada7d38f14f7147bdd6c350780e9af10";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Quickshell — the QtQuick desktop shell toolkit that hosts The Shell
    # (nix/home/quickshell). Pinned to the upstream v0.3.1 tag rather than
    # taken from nixpkgs: nixpkgs-unstable still ships 0.3.0, whose `kill`
    # returns before the instance has actually exited. That race bites every
    # shell restart (`systemctl --user restart quickshell` can land a new
    # instance while the old one still holds the layer-shell surfaces).
    # Upstream fixed it in 0.3.1; nixpkgs PR #554917 is the pending bump.
    # Drop this input and switch to pkgs.quickshell once nixpkgs is >= 0.3.1.
    #
    # `inputs.nixpkgs.follows` is MANDATORY, not hygiene: quickshell links
    # against private Qt APIs and must be built against the exact same Qt as
    # the rest of the session, or it crashes at startup on ABI mismatch.
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell?ref=refs/tags/v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hermes Agent (Nous Research). Official flake: provides the `hermes`
    # CLI, the Hermes Desktop Electron app, and a home-manager module
    # (programs.hermes-agent / services.hermes-agent).
    hermes-agent.url = "github:NousResearch/hermes-agent";

    # Nub — all-in-one Node.js toolkit (TypeScript runner, pnpm-compatible
    # package manager, Node version manager). Not yet in nixpkgs (PR #535802).
    nub = {
      url = "github:nubjs/nub";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Voxtype — taken from upstream rather than nixpkgs for the `onnx` package.
    # nixpkgs builds voxtype with no cargo features, so its Parakeet backend is
    # absent: `--model parakeet-tdt-0.6b-v3` there logs "Unknown model", falls
    # back to whisper base.en, and looks like it worked. This input is what
    # makes engine = "parakeet" possible at all (nix/home/voxtype.nix).
    #
    # Costs a ~280-derivation source build on every rev bump, all of it small
    # Rust crates: onnxruntime itself is a cached nixpkgs dependency, linked
    # dynamically via the parakeet-load-dynamic feature rather than vendored.
    voxtype = {
      url = "github:peteonrails/voxtype/v1.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenCode v2 (`opencode2`) — built from the upstream `v2.0.x` tag rather
    # than the prebuilt npm tarball we used to fetchurl. The repo's
    # nix/opencode.nix installs its binary as `opencode2` and sets
    # mainProgram = "opencode2", so this is a drop-in for the old derivation.
    # The default branch (dev) is v1 and builds a binary named `opencode`;
    # only the v2 tags carry `opencode2`.
    #
    # Bump: change the tag in the URL below, then `nix flake update opencode`.
    #
    # `inputs.nixpkgs.follows` is deliberately NOT set: the node_modules tree
    # is a fixed-output derivation whose hash is pinned in upstream's
    # nix/hashes.json, computed against upstream's own pinned nixpkgs (and its
    # bun). Following our nixpkgs risks a hash mismatch on a bun difference.
    opencode.url = "github:anomalyco/opencode/v2.0.2";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-orca, nub, opencode, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        ocmonitor = pkgs.callPackage ./nix/packages/ocmonitor { };
        opencode2 = opencode.packages.${system}.default;
        lazyskills = pkgs.callPackage ./nix/packages/lazyskills { };
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
            # System-level overlay: pin orca-slicer to a known-good nixpkgs.
            # 2.3.2 in nixos-unstable is broken (graphical plates won't open):
            # https://github.com/OrcaSlicer/OrcaSlicer/issues/13137
            # With useGlobalPkgs = true, home-manager shares this pkgs set, so
            # the overlay reaches home.packages without a second nixpkgs eval.
            nixpkgs.overlays = [
              (final: _prev: {
                orca-slicer =
                  (import nixpkgs-orca {
                    inherit system;
                  }).orca-slicer;

                ocmonitor = final.callPackage ./nix/packages/ocmonitor { };
                opencode2 = opencode.packages.${system}.default;
                lazyskills = final.callPackage ./nix/packages/lazyskills { };
                nix-search = final.callPackage ./nix/packages/nix-search { };
                nub = nub.packages.${system}.default;
              })
            ];

            home-manager = {
              useGlobalPkgs = true;
              users.jon = { imports = [ ./nix/home/default.nix ]; };
              extraSpecialArgs = { inherit inputs; };
            };
          }
        ];
      };
    };
}
