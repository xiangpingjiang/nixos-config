{
  inputs,
  pkgs,
  lib,
  ...
}:

let

  maestro-studio = pkgs.appimageTools.wrapType2 {
    pname = "maestro-studio";
    version = "latest";
    src = pkgs.fetchurl {
      url = "https://studio.maestro.dev/MaestroStudio.AppImage";
      sha256 = "sha256-/peSlEt6+OoESVReTL+refh1hyagfkLhzbA0hMZwrPg=";
    };
  };

  # dbx 上游 flake 只输出 desktop(Tauri GUI),CLI 在 workspace 的 crates/dbx-cli 里没被打包,
  # 这里自行构建。注意:这个 derivation 上游 binary cache 里不存在,dbx 输入更新后必然本地重编
  # (纯 Rust CLI,不含 Tauri/前端,比 desktop 轻得多)。
  dbx-cli = pkgs.rustPlatform.buildRustPackage {
    pname = "dbx-cli";
    version =
      (builtins.fromTOML (builtins.readFile "${inputs.dbx}/crates/dbx-cli/Cargo.toml")).package.version;
    src = inputs.dbx;
    cargoLock = {
      lockFile = "${inputs.dbx}/Cargo.lock";
      # lockfile 里的 3 个 git 依赖(t8y2 的 fork)。显式给 hash 走 fetchgit 按 rev 拉,
      # 不依赖 allowBuiltinFetchGit(历史上 tokio-postgres-gaussdb 按 branch 锁定时 fetchGit
      # 找不到 commit,现在上游虽已改为 rev 锁定,保持 hash 方式更稳)。
      # dbx 更新换了 rev 后需要重新 nix-prefetch-git(hash 和版本号都可能变)。
      outputHashes = {
        "mysql-common-derive-0.32.2" = "sha256-fw1rDLNh0BByLHjS8Cgc7KQxdj3N51HVMHXvRyETsas=";
        "mysql_async-0.37.0" = "sha256-zIMZitF9fU6wkeuGAv4LJv80bCWbvmUkgQ1/G5MjDv8=";
        "mysql_common-0.38.0" = "sha256-fw1rDLNh0BByLHjS8Cgc7KQxdj3N51HVMHXvRyETsas=";
        "postgres-protocol-0.6.12" = "sha256-ybf+2siiLokb2iylFEhmLAFCFmbjSKF+zNdH93LggkM=";
        "postgres-types-0.2.14" = "sha256-ybf+2siiLokb2iylFEhmLAFCFmbjSKF+zNdH93LggkM=";
        "tokio-postgres-0.7.18" = "sha256-ybf+2siiLokb2iylFEhmLAFCFmbjSKF+zNdH93LggkM=";
      };
    };
    # 只编译 cli 这个 crate,不碰 desktop/web
    cargoBuildFlags = [
      "-p"
      "dbx-cli"
    ];
    # cmake: aws-lc-sys(rustls 后端);pkg-config + fontconfig/freetype: dbx-core 的 font-kit
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
    ];
    buildInputs = [
      pkgs.fontconfig
      pkgs.freetype
      pkgs.openssl
    ];
    # 0.4.69 起某个依赖启用了 openssl-sys 的 vendored 特性(源码编译 OpenSSL,需要 perl),
    # 用 OPENSSL_NO_VENDOR 强制改链 nixpkgs 的 openssl,更快也更省
    env.OPENSSL_NO_VENDOR = 1;
    # 数据库相关测试需要外部服务,跳过
    doCheck = false;
    # 二进制保持原名 dbx:官方 skill(skills/dbx/SKILL.md)里的命令都是 `dbx ...`,
    # 名字冲突由 desktop 侧让位解决(见下方 dbx-desktop wrapper)
  };

  # dbx 原名让给 CLI,desktop 这边包一层改名成 dbx-desktop。
  # 不能 overrideAttrs 上游 derivation:hash 一变 binary cache 全部未命中,Tauri 要本地重编。
  # runCommand 只做零成本包装:bin 用 makeWrapper 改名并注入环境变量(见下);desktop entry 的
  # Exec 原本按 PATH 找 dbx,现在会打到 CLI 上,改写成 wrapper 的绝对路径;图标原样链接。
  dbx-desktop-upstream = inputs.dbx.packages.${pkgs.stdenv.hostPlatform.system}.dbx-desktop;
  dbx-desktop = pkgs.runCommand "dbx-desktop-renamed" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/bin $out/share/applications
    # WebKitGTK 默认的 DMA-BUF 硬件渲染在本机(AMD Phoenix 核显 + Wayland)不兼容:
    # 界面点几下就卡死,WebKitWebProcess 在 Mesa shader 线程里堆损坏崩溃(coredump 可查),
    # AppImage/Nix 打包均复现,是 Tauri 生态已知问题。禁用 DMA-BUF 渲染器走软件合成即可,
    # 见 https://v2.tauri.app/develop/debug/linux-graphics/
    makeWrapper ${dbx-desktop-upstream}/bin/dbx $out/bin/dbx-desktop \
      --set WEBKIT_DISABLE_DMABUF_RENDERER 1
    ln -s ${dbx-desktop-upstream}/share/icons $out/share/icons
    substitute ${dbx-desktop-upstream}/share/applications/dbx.desktop \
      $out/share/applications/dbx.desktop \
      --replace-fail 'Exec=dbx' "Exec=$out/bin/dbx-desktop"
  '';
  # lark-cli 升到上游最新 release,并重建 metaData。两件事都必须自己做:
  #
  # 1) 版本:nixos-unstable 里 lark-cli 还钉在 1.0.58(nixpkgs master 已到 1.0.88,
  #    但 channel 滞后),上游 larksuite/cli 几天一个 tag,差了三十来个版本。
  #    单独升 nixpkgs 换不来新版,只能在这里覆盖 src/version。
  #    Go 纯 CLI,本地编译代价不大;这个 drv 上游 cache 里不存在,必然本地构建。
  # 2) metaData:是个 fetchurl,从飞书线上端点抓 API 定义 JSON。端点内容随飞书服务端
  #    更新而变,钉的 hash 一过期构建就直接挂(hash mismatch)。这里整块重写而不是
  #    `old.metaData.overrideAttrs`——old 里的 url 还带着旧 version 的 client_version。
  #
  # 升级步骤(四步,顺序固定):
  #   a. 查最新 tag:gh api repos/larksuite/cli/releases/latest --jq .tag_name
  #   b. 改下面的 version,重算 src hash:
  #        nix-prefetch-url --unpack --type sha256 \
  #          https://github.com/larksuite/cli/archive/refs/tags/v<新版本>.tar.gz
  #        然后 nix hash convert --hash-algo sha256 --to sri <上一步输出>
  #   c. 重算 metaData hash(要对 postFetch 归一化后的结果算 —— 原始响应每次都不同,
  #      URL 里的 client_version 必须跟下面的 version 一致):
  #        curl -sSL 'https://open.feishu.cn/api/tools/open/api_definition?protocol=meta&client_version=v<新版本>' \
  #          | jq -S .data > /tmp/m.json && nix hash file --sri --type sha256 /tmp/m.json
  #   d. vendorHash 留旧值直接 build,go.mod 没动就直接过;动了则报错信息里带正确 hash,抄进来。
  #
  # skills 走的是另一条路(flake input lark-skills 跟随 upstream main,见 flake.nix
  # 和 develop/agent-skills.nix),故意不跟这里共用一份源码:那样每次 skills 刷新都可能
  # 把一次例行 nix flake update 变成 vendorHash 构建失败。
  lark-cli = pkgs.lark-cli.overrideAttrs (
    finalAttrs: _old: {
      version = "1.0.89";

      src = pkgs.fetchFromGitHub {
        owner = "larksuite";
        repo = "cli";
        tag = "v${finalAttrs.version}";
        hash = "sha256-ou3k24Xb2jvmUHbpHh1NdMBxxbm2/BpH+AsRrwi2l5Q=";
      };

      vendorHash = "sha256-WClES7ilNmQ0018Qf13tNHouE/SIwh99MaewZ7VGQ2E=";

      metaData = pkgs.fetchurl {
        name = "meta_data.json";
        url = "https://open.feishu.cn/api/tools/open/api_definition?protocol=meta&client_version=v${finalAttrs.version}";
        hash = "sha256-fPEg0FtoytyuLtyCTt74YA39xmjdeF7jd++lF3w2+Q4=";
        postFetch = ''
          ${lib.getExe pkgs.jq} -S ".data" "$out" > normalized
          mv normalized "$out"
        '';
      };
    }
  );

in
{

  home.username = "xpj";
  home.homeDirectory = "/home/xpj";
  home.stateVersion = "26.05";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.nix4vscode.overlays.default
  ];
  imports = [
    ./plasma.nix
    ./rclone.nix
    ./secrets.nix
    ./programs.nix
    ./develop/vscode.nix
    ./develop/claude-code.nix
    ./develop/codex.nix
    ./develop/agent-skills.nix

    ./develop/programs.nix
  ];
  nix.package = lib.mkDefault pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  home.packages = with pkgs; [
    gitleaks
    kubectl
    kind
    scrcpy
    android-tools
    kdePackages.krfb
    kdePackages.krdc
    kdePackages.qrca

    devenv
    direnv
    dig

    maestro-studio
    maestro
    # mitmproxy
    openssl

    maven
    jdt-language-server

    go-jsonnet
    jsonnet-bundler

    telegram-desktop
    nixpkgs-review
    gh

    feishu
    insomnia

    restic # 需要cli unlock 或者，远端恢复
    wget
    unzip
    localsend
    keepassxc
    fastfetch
    unrar-free

    (inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default) # 单独执行 hm 的更新

    basedpyright
    nodejs
    inputs.serena.packages.${pkgs.stdenv.hostPlatform.system}.serena
    lx-music-desktop
    nixfmt
    nil
    hugo
    nix-init
    go
    gcc
    python3
    ripgrep # codex 喜欢用

    dbx-desktop # 上游 GUI 的改名 wrapper(见上方 let),二进制名 dbx-desktop
    dbx-cli # 自打包的 CLI(见上方 let),占用原名 dbx,供官方 skill 直接调用
    dbeaver-bin
    jq
    uv
    sops
    mihomo # 防止断网

    kdlfmt
    mpv

    resvg # SVG -> PNG/PDF 光栅化,画架构图时把 SVG 渲出来自查

    ory
    lark-cli

  ];
  xdg.desktopEntries.maestro-studio = {
    name = "Maestro Studio";
    exec = "${maestro-studio}/bin/maestro-studio";
    icon = "maestro-studio"; # 可选，没有图标也能显示
    categories = [ "Development" ];
  };
}
