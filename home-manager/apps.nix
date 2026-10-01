{
  ...
}:
{

  programs = {

    chromium = {
      enable = true;
      # package = inputs.nixpkgs-chromium-144.legacyPackages.x86_64-linux.chromium;
      commandLineArgs = [
        # https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland#KDE_Plasma
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        # 钉死 Wayland app_id(X11 下是 WM_CLASS 的 class 那半),否则 KDE 会把这个
        # chromium 和 VS Code 归成同一个应用 —— 任务栏合并成一项、Alt+Tab 里也串在一起。
        # 原因不在 KDE:VS Code 是 Electron,启动时给自己 setenv CHROME_DESKTOP=code.desktop,
        # 这个变量被所有子进程继承(集成终端、extension host、Claude Code 起的 MCP server),
        # 而 chromium 正是读它来决定"我对应哪个 .desktop"、进而决定 app_id。于是从 VS Code
        # 里以任何方式启动的 chromium,app_id 都变成 code。实测三组对照(同一个二进制):
        #   CHROME_DESKTOP=code.desktop                      -> app_id = code
        #   同上 + --class=chromium-browser                   -> app_id = chromium-browser
        #   env -u CHROME_DESKTOP                            -> app_id = chromium-browser
        # 所以 --class 的优先级高于那个环境变量,加在这里能覆盖全部启动路径(KDE 菜单、
        # 集成终端手敲、xdg-open 点链接)。查证:KWin 脚本里打 resourceClass/desktopFileName,
        # 或 `qdbus org.kde.KWin /Scripting loadScript <脚本>` 再 run,输出去 journal。
        #
        # 注意它只改 app_id/WM_CLASS —— chromium 内部仍认为自己是 code.desktop,所以
        # 网页通知的 desktop-entry 提示还会挂在 VS Code 名下。那个要治只能覆盖环境变量,
        # 而 commandLineArgs 到不了环境变量层,没为此去包一层 wrapper。
        # Claude 用的那个 chromium 吃不到这行(它用的是未 override 的 pkgs.chromium),
        # 由 develop/chrome-devtools-mcp.nix 的 systemd service 拉起,自己带
        # --class=chromium-agent。两者 class 必须不同,否则 KDE 把它们合成一项。
        "--class=chromium-browser"
        # 这里**故意不开** --remote-debugging-port=9222。2026-09-22 起 Claude 用的是
        # 一个专用 profile 的独立实例(chromium-agent,CDP 在 9223,见
        # develop/chrome-devtools-mcp.nix),**日常浏览器不再需要开调试端口**。
        # 只有"必须复现主账号下才出现的问题"这一种情况才值得临时开:去
        # chrome://inspect/#remote-debugging 勾上 "Allow remote debugging for this
        # browser instance",实测同样在 9222 起服务、不用重启浏览器,用完记得取消勾选。
        #
        # 删掉这行的理由(2026-09-21 实测):端口无认证,凡是能连 127.0.0.1 的本机进程
        # 都能完全驾驭这个带全部登录态(Gmail、飞书、公司 console、内网 GitLab)的浏览器。
        # 要害是它**穿透 flatpak 沙箱**:WeChat 的权限里有 shared=network
        # (共享宿主 netns),文件系统被挡住、读不到 ~/.config/chromium 的 cookie 库,
        # 但实测从 WeChat 沙箱内 /dev/tcp/127.0.0.1/9222 直接拿到 200。同理,
        # bypassPermissions 下任何 claude 会话一条 curl 就从"隔离空实例"跳进日常浏览器。
        # 而实际用量是阵发的(翻 transcript:六天里三天用到),常开等于全天候白暴露。
        #
        # 注意那个运行时开关**会持久化到 profile**(实测同 profile 重开浏览器仍是 on
        # 且服务自动起来),UI 上 "for this browser instance" 的措辞是误导的,用完记得取消勾选。
        # "--remote-debugging-port=9222"
        # "--user-data-dir=$HOME/.config/chromium-compat" # 和最新版本的不兼容，这条命令数据隔离
      ];
    };
    firefox = {
      enable = true;
    };
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "github.com" = {
          HostName = "ssh.github.com";
          User = "git";
          Port = 443;
          IdentitiesOnly = true;
        };
        "*" = {
          ServerAliveInterval = 60;
        };
        dev75 = {
          HostName = "10.130.10.75";
          User = "root";
          Port = 22;
        };
        dev76 = {
          HostName = "10.130.10.76";
          User = "ecs-user";
          Port = 22;
        };
        jen = {
          HostName = "jumpserver.rockflow.ai";
          User = "xiangpingjiang#localadmin#0d71f23d-8f64-4b71-bbe1-2ca8d0588f50";
          Port = 2222;
        };
        openclaw = {
          HostName = "jumpserver.rockflow.ai";
          User = "xiangpingjiang#ecs-user#bf7eff4f-dd9a-46bc-9a43-1eb1dd60d0d8";
          Port = 2222;
        };
        vk = {
          HostName = "10.65.255.26";
          User = "vk1";
          Port = 22;
        };
      };
    };
  };
}
