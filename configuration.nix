# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  ...
}:

let
  # 精确字族名 "Noto Sans SC" 的字体。nixpkgs 的 noto-fonts-cjk-sans 提供的族名是
  # "Noto Sans CJK SC",两者对不上:飞书画板导出的 SVG 里 font-family 写的是
  # "Noto Sans SC"(飞书线上用的就是这套),resvg 靠 fontdb 按族名精确匹配、不解析
  # fontconfig 的 alias 规则,族名缺失时只打一条 warning 就把文字整段丢掉——渲出来
  # 是无字白图却不报错,很容易误判成"渲染没问题"。
  # 装到系统 fonts.packages 而不是 home.packages:fontdb 是顺着系统 fontconfig 链
  # 发现 /nix/store 里的字体的,用户侧字体能否被发现未验证。
  # 版本跟随 noto-fonts-cjk-sans(同为 2.004),tag 钉死——用 raw/main 的话上游一动
  # hash 就失效,构建直接挂。
  noto-sans-sc = pkgs.runCommand "noto-sans-sc-2.004" { } ''
    install -Dm444 ${
      pkgs.fetchurl {
        url = "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf";
        hash = "sha256-+qbJ32UhFt3nidNRNZ89fl0ihaKyofBKLXJE33BtXqk=";
      }
    } $out/share/fonts/opentype/NotoSansSC-Regular.otf
    install -Dm444 ${
      pkgs.fetchurl {
        url = "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/SC/NotoSansSC-Bold.otf";
        hash = "sha256-xstak6uqntyO50Y7frt/QtYY1A5u0velNxyXsLZHZ8A=";
      }
    } $out/share/fonts/opentype/NotoSansSC-Bold.otf
  '';
in

{

  nix.settings = {
    substituters = [
      # 官方缓存暂时放前 国内最近比较卡
      "https://cache.nixos.org"
      # binary cache for llm-agents
      "https://cache.numtide.com"

      "https://nix-community.cachix.org"
      # binary cache for cachix/nixpkgs-python
      "https://nixpkgs-python.cachix.org"
      # 优先使用国内镜像

      # "https://mirrors.cernet.edu.cn/nix-channels/store"
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
      # "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      # "https://mirror.nju.edu.cn/nix-channels/store"

    ];

    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU="
    ];
    trusted-users = [
      "root"
      "xpj"
    ];
  };

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./systemPackages.nix
    ./services.nix
    ./system-programs.nix
    ./networking.nix
    ./system-secrets.nix
  ];

  environment.variables = {
    # 开启 Go Modules
    GO111MODULE = "on";
    # 设置国内代理（任选其一即可）
    GOPROXY = "https://goproxy.cn,direct";

    JDK8_HOME = "${pkgs.jdk8}";
  };

  environment.sessionVariables = {
    XMODIFIERS = "@im=fcitx";
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 内存压缩 swap。这台机器 27G 内存长期吃到 20G+、磁盘 swap 用掉 21G/30G,
  # 大头不是单个巨型进程而是几十个 chromium/code 进程累加,压缩比通常在 3:1 左右。
  # zram 优先级(默认 5)高于 nvme 上那个 swap 分区(-1),换出先走内存、压不下才落盘。
  # 它不减少内存需求本身,只是让换页快一个量级。
  zramSwap.enable = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest; # 取决于 flake.lock 锁定的 nixpkgs 版本 和 https://search.nixos.org/packages?channel=unstable 无关

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_HK.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  # chinese input setting: https://zhuanlan.zhihu.com/p/1963358188226183647
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-fluent # 主题皮肤
      (fcitx5-rime.override {
        rimeDataPkgs = [
          pkgs.rime-ice
        ];
      })
    ];
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.xpj = {
    isNormalUser = true;
    description = "xpj";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

  # 字体问题
  fonts = {
    packages = with pkgs; [
      nerd-fonts.fira-code
      noto-fonts-cjk-sans
      noto-sans-sc # 见上方 let:给 resvg 渲飞书画板 SVG 补精确族名 "Noto Sans SC"
      # noto-fonts-cjk-serif
      noto-fonts-cjk-serif-static # for typst resume
      noto-fonts-color-emoji
    ];
    fontconfig = {
      antialias = true;
      hinting.enable = true;
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [ "FiraCode Nerd Font" ];
        sansSerif = [ "Noto Sans CJK SC" ];
        serif = [ "Noto Serif CJK SC" ];
      };
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 10d";
  };
  # 与 gc 互补:gc 删旧代、optimise 把内容相同的文件收成硬链接压体积。
  # 注意 standalone home-manager 的代不在 root 的 gc 范围内,那边单独配了
  # nix.gc(见 home-manager/home.nix),缺了它这里的 gc 基本回收不到东西。
  nix.optimise.automatic = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

}
