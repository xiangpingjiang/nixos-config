{ pkgs, lib, ... }:

let
  # Claude Desktop(Linux beta,https://code.claude.com/docs/en/desktop-linux)。
  # 官方只发 Debian 的 apt 仓库,这里直接吃仓库池里的 .deb:里面是现成的 Electron 构建,
  # drv 里只有解包 + autoPatchelf,没有编译。
  # 应用在 Linux 上不自更新(官方说更新只走 apt),所以升级只能改这里的版本号:
  #   查最新版本和 sha256(Packages 里的 SHA256 是 hex,要转 SRI):
  #     curl -s https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages \
  #       | grep -E '^(Version|SHA256):' | tail -2
  #     nix hash convert --hash-algo sha256 --to sri <hex>
  claudeDesktopVersion = "2.31226.1";
  claudeDesktopHash = "sha256-Wpvr38sd9s44dns3Pzp/q/dxVqLd2KP10Elh2lveMF4=";

  # NEEDED 里的库交给 autoPatchelf;后面几项(libGL/vulkan/wayland/libnotify/libsecret/pulse)
  # 是 Chromium 运行时 dlopen 的,不在 NEEDED 里,只能走 LD_LIBRARY_PATH。
  # libsecret 决定登录态能否存进 KWallet,缺了每次启动都要重新登录。
  runtimeLibs = with pkgs; [
    glib
    nss
    nspr
    atk
    at-spi2-atk
    at-spi2-core
    cups
    dbus
    cairo
    gtk3
    pango
    expat
    libxkbcommon
    libgbm
    libdrm
    systemd # libudev
    alsa-lib
    pipewire
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxtst
    libxcb
    libxshmfence
    libseccomp
    libcap_ng
    stdenv.cc.cc.lib # pty.node 要 libstdc++
    libGL
    vulkan-loader
    wayland
    libnotify
    libsecret
    libpulseaudio
    libappindicator-gtk3
  ];

  # Cowork:应用按 PATH 找 qemu-system-x86_64,所以 qemu 塞进 wrapper 的 PATH。
  # 固件 / virtiofsd / kvm 组 / vhost_vsock 是系统侧的,在 configuration.nix(要 nixos-rebuild)。
  claude-desktop = pkgs.stdenv.mkDerivation {
    pname = "claude-desktop";
    version = claudeDesktopVersion;
    src = pkgs.fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${claudeDesktopVersion}_amd64.deb";
      hash = claudeDesktopHash;
    };
    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = runtimeLibs;
    # chrome-sandbox 在 .deb 里是 setuid,沙箱里 chmod u+s 会失败,所以解包时丢掉权限位。
    # store 里本来就没有 setuid;Chromium 在 userns 可用时不需要它(NixOS 默认开着)。
    unpackPhase = "dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions";
    # .deb 自带 libffmpeg/libvulkan/swiftshader,autoPatchelf 会在 $out 里找到它们。
    installPhase = ''
      mkdir -p $out/lib $out/bin
      cp -r usr/lib/claude-desktop $out/lib/
      cp -r usr/share $out/share
      # postinst 里会做的那份 MIME 注册(claude:// 之外的 .mcpb / .skill 文件类型)
      install -Dm644 usr/lib/claude-desktop/resources/linux-mime/com.anthropic.Claude.xml \
        $out/share/mime/packages/com.anthropic.Claude.xml
      makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
        --prefix PATH : "${lib.makeBinPath [ pkgs.qemu_kvm ]}" \
        --add-flags "--ozone-platform-hint=auto --enable-wayland-ime"
      substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
        --replace-fail 'Exec=claude-desktop' "Exec=$out/bin/claude-desktop"
    '';
  };
in
{
  home.packages = [ claude-desktop ];
}
