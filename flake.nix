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
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-orca, nub, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        ocmonitor = pkgs.callPackage ./nix/packages/ocmonitor { };
        opencode2 = pkgs.callPackage ./nix/packages/opencode2 { };
        lazyskills = pkgs.callPackage ./nix/packages/lazyskills { };
        default = self.packages.${system}.ocmonitor;
      };

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
                opencode2 = final.callPackage ./nix/packages/opencode2 { };
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
