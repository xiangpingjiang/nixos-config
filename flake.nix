{
  description = "A very basic flake";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";

    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";

    };
    nixpkgs-chromium-144 = {
      url = "github:NixOS/nixpkgs/01d402053f2a5cbd4238d20c7e35ff091ff65f36";

    };
    agenix = {
      url = "github:ryantm/agenix/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      ...
    }@inputs:
    {
      # System configurations
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; }; # this is the important part
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              # home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.xpj = {
                imports = [
                  ./home-manager/home.nix
                  inputs.agenix.homeManagerModules.default
                  inputs.plasma-manager.homeModules.plasma-manager
                ];
              };
              home-manager.extraSpecialArgs = { inherit inputs; };
            }
            {
              environment.systemPackages = [ agenix.packages.x86_64-linux.default ];
            }
          ];
        };
      };
    };
}
