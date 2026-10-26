{
  pkgs,
  config,
  lib,
  ...
}:
let
  # 三个 WebDAV 仓库备份的是同一个目录,差异只有 rclone remote 名和错开的起始分钟。
  # startMinute 在 30 分钟周期里用 0/10/20 错开,避免三个任务同时抢带宽和仓库的共享锁
  # (单次备份实测 20-55s,10 分钟的间隔足够宽)。
  # remote 名要和 home-manager/rclone.nix 里的 remotes 对得上。
  #
  # 周期从 10 分钟放宽到 30 分钟:备份对象是一个手工编辑的 KeePassXC 库(21KB),
  # 10 分钟的 RPO 远超实际需要,代价却是每天 432 次 WebDAV 往返——2026-09-06 那次
  # 13 小时的 prune 就是这么攒出来的(详见下面 restic-prune 的注释)。
  # 文件没改时整个任务被下面的 ExecCondition 跳过,连 rclone 都不起。
  backupInterval = 30;
  kpDir = "/home/xpj/Documents/sync/kp/";

  # 目录内容(文件名 + 内容)的哈希,ExecCondition 和 ExecStartPost 共用。
  # 每个仓库各记一份:某个仓库这次失败了,下一轮它自己会重试,不受另外两个成功的影响。
  # 条件阶段把哈希先写到 .pending,备份成功(ExecStartPost 只在 ExecStart 成功后跑)才转正;
  # 不在 post 阶段重算,否则备份途中文件被改,记下的是没备上的新内容,这次修改就永远漏了。
  kpHashDir = "/var/lib/restic-kp-hash";
  kpChanged = pkgs.writeShellScript "restic-kp-changed" ''
    h=$(cd ${kpDir} && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
    [ "$h" = "$(cat ${kpHashDir}/"$1" 2>/dev/null)" ] && exit 1
    printf '%s' "$h" > ${kpHashDir}/"$1".pending
  '';
  kpRecord = pkgs.writeShellScript "restic-kp-record" ''
    mv ${kpHashDir}/"$1".pending ${kpHashDir}/"$1"
  '';
  resticRepos = {
    webdav-backup = {
      remote = "kp_cst";
      startMinute = 0;
    };
    webdav-backup-nutstore = {
      remote = "kp_nutstore";
      startMinute = 10;
      # 坚果云有频率封禁,restic 进不去(见 CLAUDE.md「坚果云是坏的」),prune 每次必败。
      # 留在 prune 列表里的代价是单元永远是红的,cst/infini 真出问题时就被淹没了。
      # 备份照跑(低频请求不受影响);修好或绕过 restic 清空之后删掉这一行。
      prune = false;
    };
    webdav-backup-infini = {
      remote = "kp_infini";
      startMinute = 20;
    };
  };
in
{
  # 内容没变就跳过备份。restic 自己的 --skip-if-unchanged 靠不住:它比的是整棵树,
  # 父目录的元数据变了也算变,2026-10-22 一天 36 次备份里只有 12 次跳过(Files 0 changed、
  # Dirs 2 changed,照样 saved)。ExecCondition 返回 1 是"跳过",单元不会变红。
  # 写在 imports 里是因为本文件已经有 systemd.services.<名字> = ...,不能再整体赋值 systemd.services。
  imports = [
    {
      systemd.services = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "restic-backups-${name}" {
          serviceConfig = {
            StateDirectory = "restic-kp-hash";
            ExecCondition = "${kpChanged} ${name}";
            ExecStartPost = "${kpRecord} ${name}";
          };
        }
      ) resticRepos;
    }
  ];

  # 2026-09-20 到 09-30 在新加坡期间关过:那边是纯 DNS sinkhole、IP 层不封,直连就够。
  # 关掉的起因是 fake-ip 把公司 VPN 自己的传输层打死
  # (openvpn 把 globalvpn.rockflow.ai 解析成 fake-ip 198.18.0.12,
  # NetworkManager 按惯例给这个"服务器地址"加一条 /32 绕行路由走物理网卡,
  # 而 mihomo 的策略路由只 suppress_prefixlength 0、压不住 /32,包直接进黑洞;
  # 表象是 nmcli 显示 activated 但 10.129/10.130/10.131 全不通)。
  # 现在两地的 VPN 域名(vpn1 国内 / globalvpn 新加坡)都在 fake-ip-filter 里,
  # 所以两地都可以开着,切地点用 netloc。换 VPN 服务器域名时必须同步改那里。
  # 2026-10-07 回到新加坡关过一次;10-08 为访问 polymarket(新加坡 DNS sinkhole)重新打开。
  # 在新加坡开着时 netloc sg;回国按 CLAUDE.md 的切换顺序跑 netloc cn。
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = config.sops.secrets.mihomo_config.path;
  };

  # 改了 secrets/mihomo.enc.yaml 之后,光 nixos-rebuild 不会重启 mihomo：
  # 配置是用 LoadCredential=config.yaml:/run/secrets/mihomo_config 传进去的，
  # 那是个运行时路径，内容变化完全不体现在 unit 文件里，systemd 于是判定无需重启。
  # 2026-09-13 踩过一次：系统代都换了(705→706)，mihomo 还跑着 40 小时前的旧配置，
  # 两代的 mihomo.service diff 为空。
  # 把加密文件的 store 路径挂进 restartTriggers：内容一变 hash 就变，unit 里的
  # X-Restart-Triggers 跟着变，systemd 才会重启。
  # mkIf 包住整个 mihomo 单元:enable = false 时 services.mihomo 模块什么都不定义,
  # 光留一条 restartTriggers 会凭空生成一个没有 ExecStart 的 mihomo.service。
  systemd.services.mihomo = lib.mkIf config.services.mihomo.enable {
    restartTriggers = [
      config.sops.secrets.mihomo_config.sopsFile
    ];
  };

  services.restic.backups = lib.mapAttrs (
    _name:
    {
      remote,
      startMinute,
      ...
    }:
    {
      # 三个仓库都已建好,不要再自动 init:模块的 pre-start 是「读 config 失败就 init」,
      # 而后端限流时会返回假 404 / 500(9/29、10/01 infini 返回 500 时日志里就是先
      # unable to open config 再尝试 create repository)。要重建某个仓库时手动 init。
      initialize = false;
      passwordFile = config.age.secrets.restic_repository.path;
      rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
      extraBackupArgs = [
        # 遇到锁时最多等 3 分钟再报错,避免与其它任务的共享锁瞬时冲突。
        # 注意:prune 已从此处剥离,改由下面的 restic-prune 任务统一执行。
        "--retry-lock=3m"
        # 内容和父快照完全一致就不生成新快照(restic ≥0.17)。没有这一项时,
        # 每次备份都会写一个新的 snapshot 文件 + 一个 index + 若干 tree blob,
        # 哪怕那个 21KB 的 kdbx 一个字节没变——2026-09-06 清理时,三个仓库里
        # 一万多个快照对应的有效数据只有 50 KiB 左右,其余全是这类元数据。
        # 10-01 验证时有效,到 10-22 大多数又变回 saved(父目录元数据也参与比较),
        # 所以主判据改成了上面的 ExecCondition;这项留着兜底,不起冲突。
        "--skip-if-unchanged"
      ];
      paths = [ kpDir ];
      repository = "rclone:${remote}:/kp/";
      # 每 backupInterval 分钟一次,从 startMinute 起算
      # (:00 :30 / :10 :40 / :20 :50)
      timerConfig.OnCalendar = "*:${toString startMinute}/${toString backupInterval}";
    }
  ) resticRepos;

  # 把 forget+prune 从每次备份里剥离，单独按下面的 timer 一周跑两次，
  # 大幅降低独占锁的频率（之前那把 4 个月的死锁就来自跟着每 3 分钟备份跑的 prune）。
  # 仓库列表自动从上面的 resticRepos 派生(跳过 prune = false 的)，增删备份时无需同步修改。
  #
  # 但"剥离"本身不清锁：2026-07-25 / 07-28 各有一次 prune 被中断（休眠或关机时
  # systemd 杀掉了服务），留下的 exclusive 锁一直躺在仓库里，此后 08-10 到 09-03
  # 共 9 次 prune 全部卡在 `repository is already locked`，每次白等 30 分钟
  # （retry-lock 10m × 3 个仓库）。备份任务不受影响是因为它们用的是非独占锁，
  # 而旧脚本的 `|| echo` 让单元始终 exit 0、永远显示 Finished——两者叠加，
  # 一个月没有任何仓库被清理过却没人察觉。下面两处修复各对应一个成因。
  #
  # 2026-09-06 修复后第一次跑,还清的是两个月的欠账:13 小时 2 分,CPU 只用了 89 秒
  # ——99.8% 的时间在等 WebDAV。删掉 10668 个快照(cst 5094 / infini 4847 /
  # nutstore 727),清完后三个仓库各自只剩 30-50 KiB 有效数据。三个后端的差距极大,
  # 同样四千多个快照:infini 10 分钟全程跑完,cst 花了 11.5 小时还在 repack 阶段撞
  # `unexpected EOF` 熔断退出,nutstore 删快照时有 7 个撞 500 导致 forget 判定失败。
  # 结论是瓶颈在后端而不是 restic 或数据量,失败也不必惊慌:forget 删掉的快照是落盘的,
  # 下次跑从十几个快照起步,只补做没做完的 pack 清理。别为 cst 的失败去重建仓库
  # (那些 `does not exist` 是限流下的假 404,同一对象换个时刻就能读到)。
  systemd.services.restic-prune = {
    description = "restic forget + prune (all kp repos)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.rclone ]; # restic 通过 PATH 调用 rclone 后端
    environment = {
      RESTIC_PASSWORD_FILE = config.age.secrets.restic_repository.path;
      RCLONE_CONFIG = "/home/xpj/.config/rclone/rclone.conf";
      # 服务以 root 运行且无 $HOME，restic 无法定位缓存目录（报 "neither
      # $XDG_CACHE_HOME nor $HOME are defined" 并放弃 prune）。用 systemd 托管的
      # CacheDirectory 显式指定缓存路径。
      RESTIC_CACHE_DIR = "/var/cache/restic-prune";
    };
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "restic-prune"; # systemd 创建并管理 /var/cache/restic-prune
    };
    script =
      let
        repos = lib.mapAttrsToList (name: _: config.services.restic.backups.${name}.repository) (
          lib.filterAttrs (_: r: r.prune or true) resticRepos
        );
      in
      ''
        rc=0
        log=$(${pkgs.coreutils}/bin/mktemp)
        trap '${pkgs.coreutils}/bin/rm -f "$log"' EXIT

        # forget 和 prune 分成两条命令，**不要**用 `forget --prune`:
        # restic 只在这一次 forget 真的删掉了快照时才接着跑 prune。一旦快照已经被
        # 上一次运行删干净(remove 0)，prune 阶段会被整个跳过、命令还返回 0——
        # 2026-09-07 就这么假成功过一次:repair index 修好了索引，4098 个待删 blob
        # 却原封不动，远端 2051 个 pack 一个没少，脚本以为成功了。
        # 拆开之后 prune 每次都真的执行，代价是索引正常时多几秒(infini 实测 5 秒)。
        #
        # 两个函数的输出都经 tee 进 journal(保留实时进度)同时留一份给下面判错用，
        # 退出码取 PIPESTATUS[0]——管道的退出码是 tee 的，直接判会永远是成功。
        run_forget() {
          ${pkgs.restic}/bin/restic -r "$1" forget \
            --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
            --retry-lock 10m 2>&1 | ${pkgs.coreutils}/bin/tee "$log"
          return "''${PIPESTATUS[0]}"
        }
        # 第一个参数是仓库，其余原样透传给 restic prune（降级重试用它加 --max-unused）
        run_prune() {
          # local:外层 for 循环的变量也叫 repo，不加就被函数改掉了
          local repo=$1
          shift
          ${pkgs.restic}/bin/restic -r "$repo" prune \
            --retry-lock 10m "$@" 2>&1 | ${pkgs.coreutils}/bin/tee "$log"
          return "''${PIPESTATUS[0]}"
        }

        for repo in ${lib.escapeShellArgs repos}; do
          echo "== forget+prune $repo =="
          # 先清陈旧锁。restic unlock 只删「同主机名且 PID 已不存在」或「超过 30 分钟
          # 没刷新」的锁——正在跑的备份每 5 分钟刷新一次自己的锁，不会被误删，
          # 而所有备份和 prune 都以 root 在本机跑，同主机名这个判据在这里是有效的。
          # 不用 --remove-all：那个连活锁一起删，会破坏并发中的备份。
          # 有了这一步，下次再被休眠打断也能自愈，不会像 07 月那样把仓库锁死两个月。
          ${pkgs.restic}/bin/restic -r "$repo" unlock \
            || echo "!! unlock 失败: $repo（仍然继续尝试 prune）"

          # forget 失败(比如坚果云删快照撞 500)不阻断 prune:该删的 pack 照样能清，
          # 只是这一轮少删几个快照，记 rc=1 让单元变红即可。
          run_forget "$repo" || { echo "!! forget 失败: $repo（仍然继续 prune）"; rc=1; }

          if run_prune "$repo"; then
            continue
          fi

          # 读不回某个 pack 时的降级重试。2026-09-06/07 在 kp_cst 上查清的情况：
          # 索引里记录 data/0889516ffe 是 21983 字节、data/5e68e668fb 是 22047 字节，
          # 而这两个文件的真实大小是 22060 / 22124(各多 77 字节)——服务端的 PROPFIND
          # 和 GET 都返回真实值、内容也完好(sha256 与文件名一致)，失真的是 restic
          # 自己的索引。restic 按索引里的短长度去取 → rclone 用它声明 Content-Length
          # → 实际数据写超 → http2 断开 → unexpected EOF → 重试十次后熔断。
          # 症状固定:每次都停在 repack 阶段的同两个文件上,重跑多少次都一样。
          #
          # `repair index` 治不了这个:实测重建 2034 个索引之后,下一轮请求的长度
          # 还是 21983。别再往那条路上走。
          #
          # 能绕过去的是不去读它们:repack 要把 pack 整个流回来,而删除一个完全没被
          # 引用的 pack 只需要一次 DELETE、不读内容。所以禁掉 repack 就绕开了坏 pack,
          # 4102 个待删 blob 一个都不少(实测降级前后这个数字完全一样——它们全都躺在
          # 完全无引用的 pack 里),留下的只是那十几个部分使用的 pack 里的零头,
          # 而这个仓库清完总共才 50 KiB 有效数据,零头无所谓。
          #
          # **必须用 --max-repack-size 0**。只加 --max-unused unlimited 不够:
          # 它管的是「为回收空间而 repack」,restic 还会为合并过小的 pack 而 repack,
          # 那条路径照走不误——2026-09-07 实测,降级后仍然 [13:50] 14/16 packs repacked
          # 然后撞上第二个坏 pack 熔断。--max-repack-size 0 是「总共只准 repack 0 字节」,
          # 两条路径一起堵死。两个都留着,各堵一条,不要只留一个。
          # 只在降级重试里加,不放进上面的正常路径:infini 那种健康仓库仍然完整清理。
          if ${pkgs.gnugrep}/bin/grep -qE "circuit breaker|unexpected EOF" "$log"; then
            echo "!! $repo 有读不回的 pack，禁用 repack 重试一次"
            run_prune "$repo" --max-repack-size 0 --max-unused unlimited && continue
          fi

          echo "!! prune 失败: $repo（继续下一个仓库）"
          rc=1
        done
        # 任一仓库失败就让单元进入 failed。旧写法始终 exit 0，正是上面那一个月
        # 无人察觉的直接原因；rc 只在循环结束后才生效，不影响其它仓库继续处理。
        exit $rc
      '';
  };

  systemd.timers.restic-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon,Thu *-*-* 04:00:00"; # 每周一、周四凌晨 4 点（一周两次）
      Persistent = true; # 关机错过后，开机补跑一次
      RandomizedDelaySec = "20m"; # 随机延迟，避免与其它定时任务撞点
    };
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  # services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  # nixpkgs 2026-10 起 plasma6 模块默认 programs.kde-pim.enable = mkDefault true,
  # 会装上整套 KMail/Kontact/Merkuro/Akonadi;本机邮件用 himalaya,用不上,关掉。
  programs.kde-pim.enable = false;

  # Configure keymap in X11
  # services.xserver.xkb = {
  #   layout = "cn";
  #   variant = "";
  # };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  services.flatpak.enable = true;

  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    # 必须等网络:开机时 DNS 还没就绪就 remote-add 会直接失败
    # (Could not resolve hostname dl.flathub.org),单元就一直留在 failed 状态。
    after = [
      "network-online.target"
      "mihomo.service" # remote-add 要访问被墙的 dl.flathub.org,得等代理起来
    ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    # 配好了就直接退出,别每次 rebuild 都去碰网络。
    # `remote-add --if-not-exists` 名字有误导:remote 已存在它也会先去拉那个
    # .flatpakrepo 文件,而 dl.flathub.org 在国内要走代理 —— mihomo 因为
    # restartTriggers 每次改配置都重启,两者一撞就是 `[35] SSL connect error`,
    # 单元失败、nixos-rebuild 跟着返回非 0,再跑一次又好了(2026-09-13 连撞 4 次)。
    # 最终 URL 是中科大镜像,而镜像没有 .flatpakrepo(404),所以只能这样绕:
    # 首次仍走官方 add,之后靠这个判断跳过。
    script = ''
      if flatpak remotes --system --columns=name,url 2>/dev/null \
        | grep -q '^flathub[[:space:]].*mirrors\.ustc\.edu\.cn'; then
        echo "flathub 已指向中科大镜像,跳过"
        exit 0
      fi
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak remote-modify flathub \
        --url=https://mirrors.ustc.edu.cn/flathub
    '';
  };
}
