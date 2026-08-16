{
  description = "my nixos flake";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = "";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # 不要 override nixpkgs，否则 derivation hash 变化导致 cache.numtide.com 缓存全部未命中
    };
    nix4vscode = {
      url = "github:nix-community/nix4vscode/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    serena = {
      url = "github:oraios/serena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dbx = {
      # 钉死 rev：上游没有任何 binary cache，dbx-cli/dbx-desktop 都是本地编译（Rust+Tauri，代价大），
      # 不钉的话每次 nix flake update 都会拉最新 rev 触发重编。
      # 升级步骤：改这里的 rev → 重新 prefetch home.nix 里 cargoDeps 的 outputHashes → rebuild
      url = "github:t8y2/dbx/2f3a32955c1db9173258a59ce0095e1d01bf7e51";
      # 不要 follows nixpkgs：会改变 derivation hash，导致已有本地构建全部作废
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      agenix,
      nix4vscode,
      serena,
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
            inputs.sops-nix.nixosModules.sops
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
