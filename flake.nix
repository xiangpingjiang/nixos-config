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
    # fcitx5 语音输入插件(见 configuration.nix 的 i18n.inputMethod)。
    # 同 llm-agents:不要 follows nixpkgs,否则 fcitx5-vinput.cachix.org 全部未命中,
    # 要在本地编 sherpa-onnx + onnxruntime。
    fcitx5-vinput.url = "github:xifan2333/fcitx5-vinput";
    nix4vscode = {
      url = "github:nix-community/nix4vscode/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent Skills 的声明式管理(见 home-manager/develop/agent-skills.nix)。
    # 纯 Nix 库 + shell 脚本,没有编译产物,follows nixpkgs 不存在缓存未命中的代价。
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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

    # tare:让 Claude Code 读自己的 transcript 诊断用量去向(一个 skill + 三个纯标准库 python 脚本,
    # 不联网)。只取 skills/tare/,装法见 agent-skills.nix。跟随 main:没有编译,也没有配套 CLI
    # 会和 skill 文本版本错位(lark-skills 要钉 tag 的理由在这里不成立)。
    tare = {
      url = "github:kelviq/tare";
      flake = false;
    };

    # dbx 官方 skill 的源码。CLI/desktop 本身改吃上游 release 的预编译二进制(见 home.nix),
    # 这里只剩 skills/ 目录有用,所以 flake = false,不再拉 crane/rust-overlay/那棵 nixpkgs。
    # 钉 CLI 的 release tag:skill 文档描述的是 CLI 的命令,两者必须同版本(理由同 lark-skills)。
    # 升级手续:改这里的 tag,同时改 home-manager/home.nix 里 dbxCliVersion(同一个版本号)。
    dbx = {
      url = "github:t8y2/dbx/packages-v0.4.127";
      flake = false;
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
