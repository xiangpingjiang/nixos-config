{
  inputs,
  pkgs,
  lib,
  ...
}:

let

  # dbx 的 CLI 和 desktop 都直接吃上游 GitHub Release 的预编译二进制,不再从源码编译。
  # 上游 flake 没有 binary cache、也不打包 CLI,源码构建 = 每次升级本地编 Rust + Tauri,
  # 结果钉着一个两个月前的 rev 不敢动。release 产物 drv 里只有解包 + patchelf,升级是秒级。
  # 两条 release 线各自独立:CLI 在 packages-v* tag,desktop 在 v* tag,版本号不同步,各钉各的。
  # 升级:改版本号,跑下面的 prefetch 换 hash;CLI 升级时同步改 flake.nix 里 dbx input 的 tag(skill 源码)。
  #   nix store prefetch-file https://github.com/t8y2/dbx/releases/download/packages-v<版本>/dbx-cli-linux-x64-gnu.tar.gz
  #   nix store prefetch-file https://github.com/t8y2/dbx/releases/download/v<版本>/DBX_<版本>_amd64.deb
  # 查最新:gh release list -R t8y2/dbx --exclude-pre-releases | grep -E 'packages-v|^v'
  dbxCliVersion = "0.4.115";
  # desktop 钉在 0.6.38:0.6.39 起 Linux 主窗口加了 "transparent": true(src-tauri/tauri.linux.conf.json,
  # 上游 commit 786ccad),KDE Wayland 下一交互就整窗狂闪。上游已在 6cd2dc1 改成默认不透明
  # (DBX_LINUX_FLOATING_FRAME=1 才开),但 v0.6.40 之后才提交、还没进 release。
  # 升级前核对:新 tag 里 tauri.linux.conf.json 的 transparent 不再是 true,或该 commit 已包含在内:
  #   gh api repos/t8y2/dbx/compare/6cd2dc1c9...v<版本> --jq .status   # ahead/identical 才行
  dbxDesktopVersion = "0.6.38";

  # CLI 只依赖 glibc(openssl/fontconfig 都静态链进去了),autoPatchelfHook 改个 interpreter 就行。
  # 二进制保持原名 dbx:官方 skill(skills/dbx/SKILL.md)里的命令都是 `dbx ...`,
  # 名字冲突由 desktop 侧让位解决(见下方 dbx-desktop)。
  dbx-cli = pkgs.stdenvNoCC.mkDerivation {
    pname = "dbx-cli";
    version = dbxCliVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/t8y2/dbx/releases/download/packages-v${dbxCliVersion}/dbx-cli-linux-x64-gnu.tar.gz";
      hash = "sha256-/Mdpi48sFTHosta8d96PtiRJvR5aIYi4yzM8SNMwjS0=";
    };
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    installPhase = ''
      install -Dm755 dbx $out/bin/dbx
    '';
  };

  # desktop 用 .deb(比 AppImage 小一半,且不用 FHS 沙箱)。Tauri 的标准运行时依赖由
  # autoPatchelfHook 补 rpath;wrapGAppsHook3 提供 GIO/GSettings 环境,glib-networking
  # 是 webview 里 HTTPS 的前提(缺了 libsoup 报 TLS/SSL support not available)。
  # 二进制改名 dbx-desktop,把原名让给 CLI;desktop entry 的 Exec 跟着改。
  # 列表照抄上游 flake 的 linuxTauriDeps。appindicator/librsvg 等是运行时 dlopen 的,
  # autoPatchelf 看不见(不在 NEEDED 里),dlopen 又不认 RPATH,所以下面还要塞进 LD_LIBRARY_PATH。
  dbxDesktopRuntimeLibs = with pkgs; [
    webkitgtk_4_1
    gtk3
    libsoup_3
    libappindicator-gtk3
    libayatana-appindicator
    librsvg
    glib
    glib-networking
    dbus
    at-spi2-atk
    cairo
    gdk-pixbuf
    harfbuzz
    pango
    fontconfig
    openssl
    libx11
    libxext
    libxfixes
  ];
  dbx-desktop = pkgs.stdenv.mkDerivation {
    pname = "dbx-desktop";
    version = dbxDesktopVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/t8y2/dbx/releases/download/v${dbxDesktopVersion}/DBX_${dbxDesktopVersion}_amd64.deb";
      hash = "sha256-nN464rRZypzlsa+eBsh2TUOXC5IkppIxLmvAaD5Ra9U=";
    };
    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
      wrapGAppsHook3
    ];
    buildInputs = dbxDesktopRuntimeLibs;
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      install -Dm755 usr/bin/dbx $out/bin/dbx-desktop
      cp -r usr/share $out/share
      # Wayland 下 app_id 取自二进制名(改名后是 dbx-desktop),KDE 按 app_id 找同名 .desktop
      # 拿图标;文件名或 StartupWMClass 对不上,任务栏就是默认的 "W"。三处必须一致。
      mv $out/share/applications/DBX.desktop $out/share/applications/dbx-desktop.desktop
      substituteInPlace $out/share/applications/dbx-desktop.desktop \
        --replace-fail 'Exec=dbx' 'Exec=dbx-desktop' \
        --replace-fail 'StartupWMClass=dbx' 'StartupWMClass=dbx-desktop'
    '';
    # WebKitGTK 默认的 DMA-BUF 硬件渲染在本机(AMD Phoenix 核显 + Wayland)不兼容:
    # 界面点几下就卡死,WebKitWebProcess 在 Mesa shader 线程里堆损坏崩溃(coredump 可查),
    # AppImage/Nix 打包均复现,是 Tauri 生态已知问题。禁用 DMA-BUF 渲染器走软件合成即可,
    # 见 https://v2.tauri.app/develop/debug/linux-graphics/
    preFixup = ''
      gappsWrapperArgs+=(
        --set WEBKIT_DISABLE_DMABUF_RENDERER 1
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath dbxDesktopRuntimeLibs}"
      )
    '';
  };

  # lark-cli 升到上游最新 release。nixos-unstable 里还钉在 1.0.88,而上游 larksuite/cli
  # 几天一个 tag,单独升 nixpkgs 换不来新版,只能在这里覆盖 version/src/metaDataRelease。
  # Go 纯 CLI,本地编译代价不大;这个 drv 上游 cache 里不存在,必然本地构建。
  #
  # metaData(内嵌的开放平台 API 注册表)现在跟随 nixpkgs 的新做法,不再自己 fetchurl
  # 飞书线上端点:那个端点没有版本化,内容随时漂,钉的 hash 一过期构建就挂,且旧字节
  # 永久拿不回来(1.0.58 就是这么死的)。新做法是从官方 release 的 linux-amd64 tarball
  # 里把注册表按字节扫出来(nixpkgs 侧的 extract-meta.py),版本内不可变、可复现。
  # 所以这里只需要覆盖 metaDataRelease 的 hash,metaData 那层 runCommand 交给 nixpkgs。
  #
  # 升级步骤(三步):
  #   a. 查最新 tag:gh api repos/larksuite/cli/releases/latest --jq .tag_name
  #   b. 改下面的 version,重算两个 hash:
  #        nix-prefetch-url --unpack --type sha256 \
  #          https://github.com/larksuite/cli/archive/refs/tags/v<新版本>.tar.gz
  #        nix-prefetch-url --type sha256 \
  #          https://github.com/larksuite/cli/releases/download/v<新版本>/lark-cli-<新版本>-linux-amd64.tar.gz
  #        各自 nix hash convert --hash-algo sha256 --to sri <输出>
  #        (tarball 那个也可以直接抄 release 里 checksums.txt 的 sha256)
  #   c. vendorHash 留旧值直接 build,go.mod 没动就直接过;动了则报错信息里带正确 hash,抄进来。
  #
  # skills 走的是另一条 input(lark-skills,见 flake.nix 和 develop/agent-skills.nix),
  # 故意不跟这里共用一份源码:那样每次 skills 刷新都可能把一次例行 nix flake update 变成
  # vendorHash 构建失败。但那个 input 钉的是和这里同一个 tag —— skill 文本按同版本 CLI 的
  # 行为写,版本漂开就会撞上不兼容(细节见 flake.nix 里 lark-skills 的注释),所以改这里的
  # version 时同步改那边的 tag。
  lark-cli = pkgs.lark-cli.overrideAttrs (
    finalAttrs: _old: {
      version = "1.0.95";

      src = pkgs.fetchFromGitHub {
        owner = "larksuite";
        repo = "cli";
        tag = "v${finalAttrs.version}";
        hash = "sha256-aTRJE8h+5BHxRUOdCrBr29URFniasQ9NgfM/L5G0ybg=";
      };

      vendorHash = "sha256-DdDx//DYulqko26afCBoaT/dhUhikXpDkleh6TuOazI=";

      metaDataRelease = pkgs.fetchurl {
        name = "lark-cli-${finalAttrs.version}-linux-amd64.tar.gz";
        url = "https://github.com/larksuite/cli/releases/download/v${finalAttrs.version}/lark-cli-${finalAttrs.version}-linux-amd64.tar.gz";
        hash = "sha256-faktQmt9AAkIx2o2uHp9A1fCcN6/THFJu8YBCyDSVB4=";
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
    ./user-secrets.nix
    ./apps.nix
    ./mail.nix
    ./netloc.nix
    ./develop/vscode.nix
    ./develop/claude-code.nix
    ./develop/chrome-devtools-mcp.nix
    ./develop/codex.nix
    ./develop/pi.nix
    ./develop/agent-skills.nix

    ./develop/shell.nix
  ];
  nix.package = lib.mkDefault pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # standalone home-manager 的代在 ~/.local/state/nix/profiles/,而系统那边的 nix.gc
  # 是 root 跑 nix-collect-garbage、只扫 /nix/var/nix/profiles/——看不到这里。
  # 不配这段,每次 switch 都在 store 里永久钉住一份完整闭包(VS Code 那个 214MB 的
  # Claude Code 插件等全在内),系统 gc 每周跑一次基本回收不到东西
  # (发现时已积到 39 个 home-manager 代 + 90 个 profile 代)。
  # 用 nix.gc 而不是 services.home-manager.autoExpire:后者只删 home-manager-*-link,
  # 管不到 nix profile 每次 switch 留下的 profile-*-link。
  # 依赖上面的 nix.package——删那行这段就没有 nix 可用了。
  nix.gc = {
    automatic = true;
    # 用 dates 而不是 frequency:后者已被 home-manager 改名,留着只会每次 eval 刷警告
    dates = "weekly";
    options = "--delete-older-than 10d";
  };

  home.packages = with pkgs; [
    gitleaks
    kubectl
    google-cloud-sdk # gcloud / gsutil / bq
    kind
    scrcpy
    android-tools
    kdePackages.krfb
    kdePackages.krdc

    devenv
    direnv
    dig

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
    lx-music-desktop
    nixfmt
    nil
    hugo
    nix-init
    go
    gcc
    python3
    ripgrep # codex 喜欢用

    dbx-desktop # 上游 release 的 deb(见上方 let),二进制名 dbx-desktop
    dbx-cli # 上游 release 的 CLI(见上方 let),占用原名 dbx,供官方 skill 直接调用
    jq
    uv
    sops
    mihomo # 防止断网

    kdlfmt
    mpv

    resvg # SVG -> PNG/PDF 光栅化,画架构图时把 SVG 渲出来自查

    # PDF 工具链。按交互范式分层,彼此不重叠(环境事实写在
    # develop/skills/local-pdf-env,给 Claude Code 及其子代理看)。
    # okular 故意不在这里:它随 services.desktopManager.plasma6 进系统 profile,
    # 再加 kdePackages.okular 会装第二份。
    qpdf # 页面拆合、加解密、--check 诊断结构;页面内容按字节无损搬运
    poppler-utils # pdftotext/pdftoppm/pdfimages/pdfinfo,把内容取出来变成文本或图片
    mupdf-headless # 只提供 mutool。qpdf 报读不进来时的救援工具(对坏 xref 容忍度更高)
    pdfarranger # GUI:缩略图里拖拽删页、调序、旋转、拼接
    xournalpp # GUI:手写笔迹和签名,导出时把笔迹压平进 PDF

    ory
    lark-cli

  ];
}
