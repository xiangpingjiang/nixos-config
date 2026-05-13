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
    # nixpkgs-chromium-144 = {
    #   url = "github:NixOS/nixpkgs/01d402053f2a5cbd4238d20c7e35ff091ff65f36";
    # };
    nixpkgs-latest = {
      url = "github:NixOS/nixpkgs/master";
    };
    agenix = {
      url = "github:ryantm/agenix/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-openclaw = {
    #   url = "github:openclaw/nix-openclaw";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.home-manager.follows = "home-manager";
    # };
    nix4vscode = {
      url = "github:nix-community/nix4vscode/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      nix4vscode,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # System configurations
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          inherit system;
          modules = [
            ./configuration.nix
            agenix.nixosModules.default
            {
              environment.systemPackages = [ agenix.packages.x86_64-linux.default ];
            }
          ];
        };
      };

      # Standalone home-manager — faster rebuild when only ~/home-manager changes
      homeConfigurations.xpj = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home-manager/home.nix
          inputs.agenix.homeManagerModules.default
          inputs.plasma-manager.homeModules.plasma-manager
        ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
}
