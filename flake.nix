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

    # Agent Skills 的声明式管理(见 home-manager/develop/agent-skills.nix)。
    # 纯 Nix 库 + shell 脚本,没有编译产物,follows nixpkgs 不存在缓存未命中的代价。
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # 飞书官方 CLI 仓库,这里只取它的 skills/ 目录(agent-skills 的 source 会把 root
    # 限定在 subdir 内,不会把整个 Go 项目导进 store)。flake = false:它不是 flake。
    # 上游新增 skill 不会自动装上——agent-skills.nix 里是白名单。
    #
    # 钉在和 lark-cli 同一个 tag 上,两边同版本升级。原来这里跟随 main(理由是只 fetch
    # markdown、没有编译代价),但 skill 文本是照着同版本 CLI 的行为写的,跟随 main 就会
    # 单方面漂到 CLI 前面 —— 2026-09-11 实测:CLI 还在 1.0.92 时,main 的 lark-doc 已经要求
    # `--presentation-decision '{}'`(旧 CLI 报 audience is required)、`@绝对路径`
    # (旧 CLI 报 unsafe file path,绝对路径是 1.0.93 的 vfs 改动才放开的)、以及 init-draft
    # 返回的 `data.cwd`(旧 CLI 压根不返回这个字段),三处全撞墙,而 shortcut 名字一个没变、
    # 表面看不出不兼容。
    #
    # 仍然是独立 input,不和 lark-cli 的 src 共用:共用的话 skills 一刷新就可能因为 go.mod
    # 变动把一次例行 nix flake update 变成 vendorHash 构建失败。
    # 升级手续:改这里的 tag,同时改 home-manager/home.nix 里 lark-cli 的 version(同一个版本号)。
    lark-skills = {
      url = "github:larksuite/cli/v1.0.95";
      flake = false;
    };

    dbx = {
      # 钉死 rev：上游没有任何 binary cache，dbx-cli/dbx-desktop 都是本地编译（Rust+Tauri，代价大），
      # 不钉的话每次 nix flake update 都会拉最新 rev 触发重编。
      # 升级步骤：改这里的 rev → 重新 prefetch home.nix 里 cargoDeps 的 outputHashes → rebuild
      url = "github:t8y2/dbx/7d5cae6486706973c2ac13138b783a889fdbccf1";
      # 不要 follows nixpkgs：会改变 derivation hash，导致已有本地构建全部作废
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
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # `nix fmt` 的实现。CLAUDE.md 里格式化用的就是 nixfmt,挂上之后
      # 直接 `nix fmt` 就能格式化整个仓库,不必逐个文件敲 nixfmt <file>。
      formatter.${system} = pkgs.nixfmt;

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
          inputs.agent-skills.homeManagerModules.default
          inputs.sops-nix.homeManagerModules.sops
        ];
        extraSpecialArgs = { inherit inputs; };
      };
    };
}
