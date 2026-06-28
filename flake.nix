{
  description = "jon's dotfiles — home-manager + NixOS config";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    handy = {
      url = "github:cjpais/Handy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, handy, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Standalone home-manager activation:
      #   home-manager switch --flake .#jon
      homeConfigurations."jon" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit handy; };
        modules = [ ./nix/home/default.nix ];
      };

      # NixOS system config (also activates home-manager for the jon user):
      #   sudo nixos-rebuild switch --flake .#diogenes
      nixosConfigurations.diogenes = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./nix/nixos/diogenes.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              users.jon = { imports = [ ./nix/home/default.nix ]; };
              extraSpecialArgs = { inherit handy; };
            };
          }
        ];
      };
    };
}
