{
  config,
  pkgs,
  lib,
  ...
}:

let
  # 上游 <https://github.com/ChromeDevTools/chrome-devtools-mcp>,npm 包名同名。
  # nixpkgs 里没有这个包(只有 mozilla 那个 firefox-devtools-mcp),所以自己打。
  #
  # 打法刻意不用 buildNpmPackage:npm 发布的 tarball 是 rollup bundle 过的,
  # package.json 里 dependencies 为空(puppeteer、yargs、lighthouse 全部打进了 build/),
  # 所以既不需要 lockfile 也不需要 npmDepsHash —— 解压 + 套个 node wrapper 就能跑
  # (实测直接 `node build/src/bin/chrome-devtools-mcp.js --help` 在没有 node_modules
  # 的情况下正常输出)。drv 里没有任何编译,重建就是一次复制。
  #
  # 升级手续:改 version,再跑这行拿新 hash:
  #   nix store prefetch-file --json --name chrome-devtools-mcp-<version>.tgz \
  #     "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-<version>.tgz"
  # 查上游当前最新版本:
  #   curl -s https://registry.npmjs.org/chrome-devtools-mcp | jq -r '."dist-tags".latest'
  version = "1.9.0";

  chromeDevtoolsMcp = pkgs.stdenvNoCC.mkDerivation {
    pname = "chrome-devtools-mcp";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${version}.tgz";
      hash = "sha256-X3U7HL9XdcjkNxE1Is0QwfDO/RZSHgVyVA1XhgVWwTM=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;

    # bin 入口是 ESM(package.json 里 "type": "module"),所以 package.json 必须跟着
    # 一起装,否则 node 会把 .js 当 CommonJS 解析、当场 SyntaxError。
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/chrome-devtools-mcp
      cp -r build package.json $out/lib/chrome-devtools-mcp/
      makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/chrome-devtools-mcp \
        --add-flags $out/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js
      runHook postInstall
    '';

    meta = {
      description = "Chrome DevTools MCP server";
      homepage = "https://github.com/ChromeDevTools/chrome-devtools-mcp";
      license = lib.licenses.asl20;
      mainProgram = "chrome-devtools-mcp";
      platforms = lib.platforms.unix;
    };
  };

  # 被控浏览器的调试端口和 profile 目录。两处都被下面的 service 和 MCP server 引用,
  # 改一处就够 —— 曾经因为两边各写一份字面量而不同步,整条链会静默失败(连不上不报错,
  # 只是每个工具都超时)。
  #
  # 端口刻意**不用 9222**:那是日常浏览器运行时开关(chrome://inspect)会占的端口,
  # 两者要能同时存在。实测 chromium 153 在 9223 绑的是 `127.0.0.1`(v4),和下面
  # browserUrl 里写的一致;CLAUDE.md 记过"127.0.0.1:9222 被占时会退到 [::1]:9222",
  # 那是**同端口**被占时的地址回落,换端口就不会发生,已实测。
  agentPort = "9223";
  agentProfile = "chromium-agent";
in
{
  # 给 MCP 专用的那个 chromium:独立 user-data-dir,**登录态持久保留**,
  # 和日常浏览器(~/.config/chromium)完全分开。
  #
  # 这是 2026-09-22 的架构。在它之前是两个 MCP server:一个 --isolated 的临时实例
  # (每次全新、无登录态),一个连日常浏览器 9222 的 chrome-live。两个都有问题:
  #   - 临时实例每次从零开始,凡是要登录才能看的页面都用不了;
  #   - 连日常浏览器要先去 chrome://inspect 手动勾开关(9222 不常驻,理由见 apps.nix),
  #     而那个端口一旦开着就没有任何认证 —— 凡是能连 loopback 的进程(flatpak 里
  #     shared=network 的应用、任何 bypassPermissions 的 claude 会话)都能完全驾驭
  #     你那个带全部登录态的浏览器。
  # 专用 profile 同时解掉这两条:登录态持久(一次性手动登录,之后 start 就带着),
  # 而暴露出去的只是这个 profile 里的账号 —— 所以**别在这里登公司 SSO、银行、主账号**。
  #
  # 账号隔离**不等于网络隔离**:它仍是 xpj 的进程,VPN 开着时照样能翻 10.x 内网,
  # flatpak 经这个端口能拿它当跳板。所以是按需 start/stop 的服务,不开机自启。
  #
  # 不写 wantedBy => 不自启;Restart=no => 用户手动关掉窗口就是关掉,不要自动拉回来。
  # 显示变量不用自己塞:实测 `systemctl --user show-environment` 里
  # WAYLAND_DISPLAY/DISPLAY/XDG_SESSION_TYPE 都在,service 能正常起图形窗口。
  systemd.user.services.chromium-agent = {
    Unit = {
      Description = "Chromium instance controlled by Claude via CDP (persistent profile)";
      # 窗口要有图形会话才起得来。按需 start 时图形会话必然在,这条只是防止
      # 在 graphical-session 拆掉之后被别的单元拉起来。
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "exec";
      Restart = "no";

      # 用未 override 的 pkgs.chromium,**不是** apps.nix 里那个:后者带着
      # --class=chromium-browser(日常浏览器专用的一套参数),和这里的 --class 撞名,
      # KDE 的 Alt+Tab 会把两个实例合成一项(TabBox.ApplicationsMode=1 下尤其明显)。
      ExecStart = lib.escapeShellArgs [
        "${pkgs.chromium}/bin/chromium"
        # 用 config.home.homeDirectory 而不是 systemd 的 %h:escapeShellArgs 会把整个
        # 参数包进单引号,而 specifier 在引号内展开与否是 systemd 的实现细节,
        # nix 期就定死没有这个不确定性。
        "--user-data-dir=${config.home.homeDirectory}/.local/share/${agentProfile}"
        "--remote-debugging-port=${agentPort}"
        # 任务栏/Alt+Tab 里和日常浏览器、和 VS Code 都分得开。三处 class 各不相同:
        # chromium-browser(日常,apps.nix)/ chromium-agent(这个)/ code(VS Code)。
        "--class=chromium-agent"
        # 和日常浏览器同一套 wayland 参数,不带的话会落到 XWayland(能用但输入法和
        # 缩放都不对)。
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
      ];
    };
  };

  # 走 programs.claude-code.mcpServers 而不是 programs.mcp.servers:后者是给多个
  # AI 客户端共享 MCP 配置用的(还要开 enableMcpIntegration),本机只有 Claude Code 这一个消费者。
  #
  # home-manager 模块把它渲染成一个合成插件(manifest 名 `hm`)的 .mcp.json,
  # 落在 ~/.claude/skills/claude-code-home-manager/,所以:
  #   - 服务在 /mcp 里显示为 `plugin:hm:chrome`,
  #     工具名前缀是 `mcp__plugin_hm_chrome__<tool>`(写 permissions 规则时按这个匹配);
  #   - 终端 `claude` 和 VS Code 插件两份二进制共用 ~/.claude,所以两个入口都吃得到
  #     (前提是两边都 >= 2.1.157,低于这个版本模块会退回 --plugin-dir wrapper,
  #     那条路只包住终端的 claude,插件拿不到。本机两处都钉在 2.1.273)。
  # MCP 配置和 hooks 一样是进程启动时读的,switch 完已开着的会话不会凭空多出这个服务。
  #
  # **只注册一个 server**,这是刻意的。曾经并存两个(chrome-devtools / chrome-live),
  # 它们跑同一个二进制、53 个工具的描述一字不差,模型在工具列表里分辨不出该用哪个,
  # 于是默认挑了名字更"正统"的那个 —— 用户看到的现象就是"Claude 老是新开一个空浏览器,
  # 不用我正在用的"。只留一个,选错这件事在结构上就不可能发生。
  programs.claude-code.mcpServers.chrome = {
    type = "stdio";
    command = lib.getExe chromeDevtoolsMcp;

    args = [
      # 连上面那个 service 起的实例,而不是自己拉一个。
      #
      # **懒连接,已实测**:server 进程在会话启动时就起,但要到第一次调用工具时才
      # `ensureBrowserConnected`(build/src/browser.js 开头是 `if (browser?.connected)
      # return browser`,而它在每次工具调用都走的 #getContext() 里)。由此两条性质:
      #   - 会话开着的时候再 `systemctl --user start`,直接就能用,不必重开会话或 /mcp 重连;
      #   - 浏览器中途关掉再开,下一次调用自动重连(返回里带 `"reconnected": true`)。
      # 多个 claude 会话同时连同一个实例也实测正常(CDP 支持多客户端)。
      "--browserUrl"
      "http://127.0.0.1:${agentPort}"

      # 不写 --executablePath / --isolated / --userDataDir:三者都只对"由 server 自己
      # 拉起浏览器"有意义。这里是连已经跑着的实例,浏览器的生命周期归 systemd 管 ——
      # 实测 MCP server 退出(会话结束)浏览器照常活着。
      #
      # 也**不写 --categoryExtensions / --categoryPwa**:上游说这两类只在 pipe 连接下
      # 可用,实测 --browserUrl 下 list_extensions 不报错但返回 `[{}]`(装着 6 个扩展却
      # 拿不到任何元数据),等于白占 8 个工具位。要装/重载扩展去这个实例的
      # chrome://extensions 手动 Load unpacked / reload。
      #
      # --autoConnect 这条路仍然不通:它要读 <userDataDir>/DevToolsActivePort,而
      # chromium 153 **无论用运行时开关还是命令行 --remote-debugging-port 都不写这个文件**
      # (2026-09-22 用本 service 的 profile 实测,文件不存在)。只能继续用 --browserUrl。
      "--experimentalDevtools"
      "--experimentalVision"
      "--memoryDebugging"
      "--experimentalStructuredContent"
      # 几十个标签是常态,这条让 list_pages 不漏掉任何一个
      # (副作用是 DevTools 自己的页面也会进列表,不是 bug)。
      "--experimentalIncludeAllPages"

      # 录屏工具需要外部 ffmpeg(上游只说"确保 ffmpeg 在 MCP server 的 PATH 里",
      # 这里直接把路径钉死,免得依赖调用方环境)。
      "--experimentalScreencast"
      "--experimentalFfmpegPath"
      "${pkgs.ffmpeg-headless}/bin/ffmpeg"

      # 没开 --categoryExperimentalThirdParty:它把"被检查页面自己声明的开发者工具"
      # 暴露成 MCP 工具 —— 等于让被访问的网页往 Claude 的工具列表里塞东西,
      # 而本机是 bypassPermissions(默认放行)。要用的时候在这儿加一行即可。

      # 遥测:默认会把使用数据发给 Google。关掉不损失任何功能。
      "--no-usage-statistics"
      # performance 工具默认把 trace 里的 URL 提交给 Google 的 CrUX API 换取真实用户
      # 性能数据。代价是被测页面的 URL 出境 —— 本机常测的是 10.x 内网和公司域名,
      # 不该外泄。想要 CrUX 字段数据时删掉这行。
      "--no-performance-crux"

      # 刻意没加 --workspace/--filesystemRoot:客户端协商了 MCP roots 时,写文件类
      # 工具(截图/trace 落盘)就按 roots 放行,Claude Code 2.1.203+ 实现了 roots
      # (会话启动目录 + --add-dir 加的目录)。真遇到"只能写 /tmp"的拒绝,再加
      # "--workspace" + home 目录。
    ];
  };

  # 真需要"每个会话一个互不干扰的空浏览器"时(多会话并发操作浏览器会互相看见对方的
  # 标签页,A 的 close_page 能关掉 B 正在用的页),把下面这段加回来就是第二个 server。
  # 保留在这里是因为 --executablePath 那条不写就会踩坑,别再从头查一遍:
  #
  # programs.claude-code.mcpServers.chrome-isolated = {
  #   type = "stdio";
  #   command = lib.getExe chromeDevtoolsMcp;
  #   # 覆盖从 VS Code 泄漏下来的 CHROME_DESKTOP=code.desktop —— VS Code 是 Electron,
  #   # 启动时给自己 setenv 这一项,整条 extension host → claude → server 的链都继承着,
  #   # 而 chromium 正是读它决定自己对应哪个 .desktop,于是拉起来的浏览器 app_id 变成
  #   # code,KDE 把它和编辑器合成一项。(连已有实例的模式没这个问题,浏览器不是 server
  #   # 的子进程。)
  #   env.CHROME_DESKTOP = "chromium-browser.desktop";
  #   args = [
  #     # 必须显式指定浏览器:puppeteer 在 Linux 上按 /opt/google/chrome/chrome 这类
  #     # FHS 路径找 Chrome,NixOS 上一个都不存在,不指定就会去下载一份(动态链接,跑不起来)。
  #     "--executablePath" "${pkgs.chromium}/bin/chromium"
  #     # 每个会话一份临时 profile,浏览器关掉自动清理。不加的话所有会话共用
  #     # ~/.cache/chrome-devtools-mcp/chrome-profile,profile 单例锁会让第二个会话的
  #     # 浏览器起不来("The browser is already running for ... Use --isolated")。
  #     "--isolated"
  #     # extensions / pwa 只在这种 pipe 连接下才真正可用。
  #     "--categoryExtensions" "--categoryPwa"
  #   ];
  # };
}
