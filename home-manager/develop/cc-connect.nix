{
  pkgs,
  lib,
  config,
  ...
}:

let
  # 把飞书消息接到本机 Claude Code 的桥(github.com/chenhg5/cc-connect)。
  #
  # 纯 Go 单二进制,用 no_web tag 构建:web 管理界面(9820 端口)那套要先跑 pnpm+vite
  # 把 web/dist 打出来给 //go:embed 用,而它的作用是在浏览器里改 config.toml——本仓库
  # 的配置是 /nix/store 里的只读文件,那个界面能做的事这里一件都不成立,不如不编。
  # goolm 跟着上游 Makefile 走(matrix 平台的 olm 用纯 Go 实现,免掉 libolm 这个 C 依赖)。
  #
  # 升级步骤:
  #   a. 查最新 tag:curl -s https://api.github.com/repos/chenhg5/cc-connect/releases/latest | jq -r .tag_name
  #   b. 改 version,重算 src hash:
  #        nix-prefetch-url --unpack --type sha256 \
  #          https://github.com/chenhg5/cc-connect/archive/refs/tags/v<新版本>.tar.gz
  #        nix hash convert --hash-algo sha256 --to sri <输出>
  #   c. vendorHash 留旧值直接 build,go.mod 没动就直接过;动了则报错里带正确 hash,抄进来。
  version = "1.5.0";

  cc-connect = pkgs.buildGoModule {
    pname = "cc-connect";
    inherit version;

    src = pkgs.fetchFromGitHub {
      owner = "chenhg5";
      repo = "cc-connect";
      tag = "v${version}";
      hash = "sha256-7+Eys/M8Aw5OPnBDuyYlqUIIkXMyGesuY76eK24oLB0=";
    };

    vendorHash = "sha256-de6mWsH//yHl9zvU0NYyRmtz5rPzLZLAOqhbhEVNX6I=";

    subPackages = [ "cmd/cc-connect" ];
    tags = [
      "no_web"
      "goolm"
    ];
    ldflags = [
      "-s"
      "-w"
      "-X"
      "main.version=v${version}"
    ];

    # 测试要拉起真实的 agent CLI / 外部网络,构建期跑不了
    doCheck = false;

    meta = {
      description = "把本地 coding agent 接到 IM 的桥,这里只用飞书 + Claude Code";
      homepage = "https://github.com/chenhg5/cc-connect";
      license = lib.licenses.mit;
      mainProgram = "cc-connect";
    };
  };

  # bot 的默认工作目录。进去以后可以用 /dir 切到具体仓库(需要 admin_from 权限)。
  workDir = "${config.home.homeDirectory}/Projects";

  # 谁能用这个 bot(飞书 open_id,逗号分隔)。
  # **留空或写 "*" 等于全租户放行**,而这是一个能在本机跑 claude 的 bot,绝不能这么开。
  # open_id 是 per-app 的,别处(lark-cli)拿到的那个在这里不通用,只能等应用建好、
  # 自己给 bot 发一条消息后从 debug 日志里读(见 CLAUDE.md 的引导步骤)。
  # 拿到之前保持这个占位值:谁都不匹配,fail-closed。
  allowFrom = "PENDING_SET_YOUR_OPEN_ID";

  credentialsReady = pkgs.writeShellScript "cc-connect-credentials-ready" ''
    if [ -z "''${CC_FEISHU_APP_SECRET:-}" ] || [ "$CC_FEISHU_APP_SECRET" = "REPLACE_ME" ]; then
      echo "飞书凭证还是占位值,先按 CLAUDE.md 的引导步骤填 secrets/cc-connect.enc.yaml" >&2
      exit 1
    fi
  '';

  # 配置文件全量由 Nix 生成。TOML 里所有字符串值都支持 ''${VAR} 环境变量替换
  # (config/config.go 的 resolveEnvPlaceholders,反射遍历所有 string 字段),
  # 所以凭证不落盘在这里,而是由 systemd 的 EnvironmentFile 从 sops 注入。
  #
  # 代价:这个文件在 ~/.cc-connect/config.toml 是指向 /nix/store 的只读符号链接,
  # 走管理 API 写配置的路径(web admin、/commands add、/alias add)会失败。
  # 前两个我们本来就没开;自定义命令要加就写进这里的 [[commands]]。
  configToml = pkgs.writeText "cc-connect-config.toml" ''
    # 由 home-manager/develop/cc-connect.nix 生成,不要手改——每次 switch 都会被覆盖。

    [log]
    level = "info"

    [[projects]]
    name = "default"
    # 特权命令(/dir /shell /restart /upgrade /cron addexec)的白名单,和 allow_from 一样是 open_id
    admin_from = "${allowFrom}"

    [projects.agent]
    type = "claudecode"

    [projects.agent.options]
    work_dir = "${workDir}"
    # 钉死二进制,保证和终端/VS Code 里跑的是同一个 claude
    cmd = "${config.programs.claude-code.package}/bin/claude"
    # 文件编辑自动放行,其他工具仍在飞书里问一次。
    # 想全自动改成 "bypassPermissions",想更保守改 "default"。
    mode = "acceptEdits"

    [[projects.platforms]]
    type = "feishu"

    [projects.platforms.options]
    app_id = "''${CC_FEISHU_APP_ID}"
    app_secret = "''${CC_FEISHU_APP_SECRET}"
    allow_from = "${allowFrom}"
  '';
in
{
  # 凭证渲染成 EnvironmentFile 用的 KEY=VALUE 文件。
  # 用 sops.templates 而不是两个独立的 secret 文件:systemd 的 EnvironmentFile 只吃
  # KEY=VALUE 格式,不能直接喂裸密钥。渲染结果在
  # ~/.config/sops-nix/secrets/rendered/cc-connect.env(0400,tmpfs)。
  sops.templates."cc-connect.env".content = ''
    CC_FEISHU_APP_ID=${config.sops.placeholder.cc_feishu_app_id}
    CC_FEISHU_APP_SECRET=${config.sops.placeholder.cc_feishu_app_secret}
  '';

  home.packages = [ cc-connect ];

  # 放在默认路径上(而不是给服务传 --config),这样终端里直接敲 cc-connect sessions
  # 之类的命令看到的是同一份配置。数据目录 ~/.cc-connect 由程序自己建,不受影响。
  home.file.".cc-connect/config.toml".source = configToml;

  # 不要用上游的 `cc-connect daemon install`:它会自己往 ~/.config/systemd/user/ 写
  # 一份单元,和这里的声明式单元打架。启停一律 systemctl --user。
  systemd.user.services.cc-connect = {
    Unit = {
      Description = "cc-connect — 飞书 ↔ 本地 Claude Code";
      After = [
        "network-online.target"
        "sops-nix.service"
      ];
      Wants = [
        "network-online.target"
        "sops-nix.service"
      ];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = "${config.home.homeDirectory}/.cc-connect";
      ExecStart = "${cc-connect}/bin/cc-connect";
      EnvironmentFile = config.sops.templates."cc-connect.env".path;
      # 凭证还是 sops 里的占位值时直接跳过启动。用 ExecCondition 而不是
      # ConditionPathExists:要判的是环境变量的内容而不是文件在不在,而 ExecCondition
      # 非零退出会让 systemd 按"条件不满足"跳过,既不算失败也不会触发 Restart=always
      # 空转刷日志(ExecStartPre 失败则会)。
      ExecCondition = credentialsReady;
      Environment = [
        # systemd user service 不继承登录 shell 的环境,PATH 是完全覆盖的。
        # 除了 cc-connect 自己要 spawn 的 claude,还挂上用户 profile——飞书发来的
        # 指令最终是 claude 在跑 bash,PATH 太窄什么都干不了。
        "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:${
          lib.makeBinPath [
            pkgs.git
            pkgs.openssh
            pkgs.which
            pkgs.coreutils
            pkgs.bashInteractive
            config.programs.claude-code.package
          ]
        }"
      ];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
