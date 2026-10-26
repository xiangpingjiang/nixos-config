# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  inputs,
  ...
}:

let
  # 完整版(带本地 sherpa-onnx);只用云端识别可换成 .fcitx5-vinput-lite
  fcitx5-vinput = inputs.fcitx5-vinput.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # 解开蓝牙的 rfkill 并确认适配器起来,起不来就重启 bluetoothd。
  # 挂起唤醒、开机、bt-fix 三处共用。
  bluetoothUnblock = pkgs.writeShellApplication {
    name = "bluetooth-unblock";
    runtimeInputs = with pkgs; [
      util-linux
      bluez
      systemd
      gnugrep
      coreutils
    ];
    text = ''
      powered() { bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; }
      rfkill unblock bluetooth
      for _ in $(seq 10); do
        powered && exit 0
        sleep 1
      done
      echo "蓝牙 10 秒内没起来,重启 bluetooth.service" >&2
      systemctl restart --no-block bluetooth.service
      sleep 3
      bluetoothctl power on || true
    '';
  };

  # 应急命令:醒来后蓝牙鼠标连不上时用(终端敲 bt-fix,或 plasma.nix 里的 Meta+Shift+B)。
  # 解锁 + 确认适配器 + 逐个连接已配对的输入设备。
  btFix = pkgs.writeShellApplication {
    name = "bt-fix";
    runtimeInputs = with pkgs; [
      bluetoothUnblock
      bluez
      gnugrep
      gawk
      libnotify
    ];
    text = ''
      bluetooth-unblock
      bluetoothctl power on || true
      bluetoothctl devices Paired | awk '{print $2}' | while read -r mac; do
        if bluetoothctl info "$mac" | grep -q 'Icon: input-'; then
          bluetoothctl connect "$mac" || true
        fi
      done
      status=$(bluetoothctl devices Connected)
      echo "''${status:-没有已连接的设备}"
      notify-send -a bt-fix "蓝牙" "''${status:-没有已连接的设备,鼠标拨一下电源开关再试}" || true
    '';
  };

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
      # binary cache for fcitx5-vinput
      "https://fcitx5-vinput.cachix.org"
      # 优先使用国内镜像

      # "https://mirrors.cernet.edu.cn/nix-channels/store"
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
      # "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      # "https://mirror.nju.edu.cn/nix-channels/store"

    ];

    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "fcitx5-vinput.cachix.org-1:XpX3AA6+dDIX4qJhb1QM7sbTwX6/qSlGvW8Z5NK6XdU="
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

  # memoryPercent 默认 50。2026-09-18 实测压缩比 3.42(zram 里 11.5G 数据只占 3.4G 物理内存),
  # 默认值下 13.5G 的 zram 早就写满、溢出到 nvme 上那个 swap 分区又用掉 8.4G,
  # io PSI 的 full avg300 到了 49——近一半时间全系统卡在换页 IO 上。调到 100 让更多页
  # 留在 zram 而不落盘。注意这只让抖动变轻,补不上工作集本身超出物理内存的那部分
  # (那次是 ~35G 工作集塞进 27G 机器,真正的解法是关掉闲置的 chromium 标签页/VS Code 窗口)。
  zramSwap.memoryPercent = 100;

  # 挂起期间给蓝牙断电,醒来再开(2026-10 连续三晚电池耗光的修复)。
  # 本机蓝牙(MediaTek 0489:e0cd)是挂在 XHC0(63:00.3)下的内部 USB 设备,和核显同在
  # PCIe 桥 00:08.1 下。蓝牙鼠标连着时挂起,那个桥会报 `PME: Spurious native interrupt`
  # 把挂起打断,内核立刻重试,而 amdgpu 在这个"打断—恢复—再挂起"的路径上偶尔卡死:
  # 日志停在第二次 `PM: suspend entry`,机器以 5-6W 耗一整夜(正常 s2idle 不到 1W)。
  # rfkill 直接断掉蓝牙,比只关 USB 唤醒可靠(btusb 挂起时会按配对设备自己重新打开唤醒)。
  # 代价:不能晃鼠标唤醒,要开盖或按电源键;醒来鼠标一两秒后自动重连。
  # StopWhenUnneeded:sleep.target 在唤醒后退出,本单元随之 stop,ExecStop 就是"醒来"的钩子。
  systemd.services.bluetooth-sleep = {
    description = "挂起期间关闭蓝牙";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/rfkill block bluetooth";
      ExecStop = "${bluetoothUnblock}/bin/bluetooth-unblock";
    };
  };

  # 关掉 00:08.1 桥下设备的系统唤醒(2026-10-18,上面那条 rfkill 不够)。
  # 10-17 夜里蓝牙已被 block,同一个 `PME: Spurious native interrupt` 照样出现:
  # 先打断 23:24 的挂起(第二次挂起倒是睡着了),01:24 转休眠时又把冻结打断,
  # 回滚路径上 amdgpu 卡死,没写出镜像(次日 `PM: Image not found`),机器醒着耗光电池。
  # 10-17 凌晨还见过它连续十几次打断休眠、每分钟重试一次。所以中断源不只蓝牙,
  # 桥下能唤醒的另外三个都关:XHC0(1022:15b9)、XHC1(15ba)、ACP 音频(15e2)。
  # 按 ID 而不是总线号匹配,BIOS 改了枚举顺序也不会失效。
  # 代价:USB 键盘/鼠标不能唤醒,开盖和电源键不受影响(走 EC/ACPI,不经过这个桥)。
  # 必须同时匹配 bind(2026-10-23):只写 add 时 XHC 两个关掉了,ACP 却仍是 enabled ——
  # snd_pci_ps 在 probe 里自己把唤醒打开,而 probe 晚于 add 事件。bind 事件在 probe 之后发出,
  # 这时再写才压得住。10-22 夜里的休眠就是在只剩它开着的情况下被 PME 打断的。
  #
  # 曾有第二条把 HD Audio 控制器(63:00.6,1022:15e3)钉成 power/control=on,2026-10-25 撤掉:
  # 它是 spurious PME 的来源(每次休眠退回后每 12.6 秒一次),但规则重启后不生效 ——
  # snd_hda_intel 的 probe 后半段是异步的,bind 事件之后才 pm_runtime_allow,把 on 改回 auto。
  # 而且没必要了:休眠改成 HibernateMode=shutdown(见下)之后,写完镜像就断电,不再检查唤醒事件,
  # PME 打不断它。
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x15b9|0x15ba|0x15e2", ATTR{power/wakeup}="disabled"
  '';

  # 不加载 SD 读卡器驱动(2026-10-23):它才是休眠一直失败的直接原因,上面那条 udev 规则不是。
  # Realtek 读卡器(rtsx_pci_sdmmc,挂在 00:02.3 下)每次设备恢复都会做一次插卡检测,
  # 同时登记一个唤醒事件(唤醒源 mmc0)。休眠流程里拍完快照要先把设备恢复回来才能写盘,
  # 这时读卡器就登记一次;到断电前检查"有没有待处理的唤醒事件"时撞上它,于是放弃,
  # 报 `Failed to put system to sleep ... Device or resource busy`。
  # 10-22 夜里 44 次休眠全部这样失败,机器黑着屏醒了一整夜(约 4W,7.5 小时从 63% 掉到 10%);
  # mmc0 的 active_count 正好等于睡眠次数。开了 pm_debug_messages 后日志直接写出
  # `PM: Wakeup pending, aborting suspend` / `PM: active wakeup source: mmc0`。
  # 之前归给 00:08.1 那个 spurious PME 的休眠失败,当时没开调试日志,多半也是它。
  # 代价:SD 卡槽不能用。要用时 `sudo modprobe rtsx_pci_sdmmc`,用完 `sudo rmmod` 掉再睡。
  boot.blacklistedKernelModules = [ "rtsx_pci_sdmmc" ];

  # 开机也解一次锁。systemd-rfkill 会在关机时保存、开机时恢复 rfkill 状态,
  # 而电池恰恰可能在"挂起中、蓝牙被 block"时耗光 —— 不解锁的话下次开机蓝牙是关的,
  # 触摸板又坏着,就没有鼠标可用了。
  systemd.services.bluetooth-unblock-boot = {
    description = "开机时确保蓝牙未被 rfkill 锁住";
    after = [
      "systemd-rfkill.service"
      "bluetooth.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bluetoothUnblock}/bin/bluetooth-unblock";
    };
  };

  # 电池保养模式(2026-10-24):机器大多插着电用,常年停在 100% 老化最快。
  # ideapad_acpi 给 BAT0 挂了 charge_types,三档 Fast / Standard / Long_Life,
  # Long_Life 即联想的保养模式,充到约 80% 停。出门要满电就临时切回去(不用重启):
  #   echo Standard | sudo tee /sys/class/power_supply/BAT0/charge_types
  # 不用 udev 规则:这个属性是 ideapad_acpi 绑定后以 battery hook 补挂上去的,
  # BAT0 的 add 事件那一刻可能还不存在,所以开机后等它出现再写。
  systemd.services.battery-long-life = {
    description = "开机时把电池充电模式设为 Long_Life(保养模式)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      f=/sys/class/power_supply/BAT0/charge_types
      for _ in $(seq 30); do
        [ -w "$f" ] && { echo Long_Life > "$f"; cat "$f"; exit 0; }
        sleep 1
      done
      echo "$f 30 秒内没出现,ideapad_acpi 没加载?" >&2
      exit 1
    '';
  };

  # 和 systemPackages.nix 里那份列表合并
  environment.systemPackages = [
    btFix
    fcitx5-vinput # vinput CLI 和 vinput-gui
  ];

  # 让 bt-fix(应急命令,不带 sudo)能重启 bluetooth.service。
  # 鼠标是唯一的指点设备,应急时可能只能靠快捷键起它,没有终端输 sudo 密码。
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "bluetooth.service" &&
          subject.user == "xpj") {
        return polkit.Result.YES;
      }
    });
  '';

  # 休眠兜底:KDE 电池模式下"睡眠"走 suspend-then-hibernate(plasma.nix 的 whenSleepingEnter),
  # 睡满 HibernateDelaySec 后写盘关机。只救得了"睡着了但睡得浅",救不了彻底卡死
  # (卡死时 RTC 闹钟也不会被处理)。
  # 注意 zram:休眠要先把内存压到 image_size 以下,优先级更高的 zram 换出等于没腾出物理内存,
  # 内存吃得很满时可能 `Error -12 creating image` 失败(2026-10-23 实测撞上过,当时已用 17G)。
  # 只有 suspend-then-hibernate 那条路失败后会回到挂起;空闲自动休眠(plasma.nix 的 autoSuspend)
  # 是直接 hibernate,失败了就原样醒着,10 分钟后再试 —— 不丢东西,但会一直耗电。
  boot.resumeDevice = "/dev/disk/by-uuid/59506173-06a5-402e-9060-39a2b835927e";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "2h";

  # 休眠写完镜像后直接断电,不走 ACPI S4(2026-10-25)。默认 "platform shutdown" 先试 platform,
  # 而 platform 在断电前最后检查一次唤醒事件,有就回滚(内核 hibernate.c 的 power_down():
  # 只有 HIBERNATION_PLATFORM 分支会 `rolling back`,shutdown 分支直接 kernel_power_off)。
  # 回滚在这台机器上是致命的:amdgpu sdma0 超时、Mode2 reset 失败,GPU 挂死,机器半死不活醒着耗光电池
  # (10-23 23:25、10-24 01:57、10-25 01:35 三次,最后一次之后冻结用户态失败、挂起每两分钟重试一次,
  # 04:01 电量耗尽)。打断它的东西不止一个:先是 HDA 的 spurious PME,修掉之后 10-25 那次
  # 调试日志写的是 `last active wakeup source: PNP0C0C:00` —— 电源键。合着盖没人按,是固件在
  # EC 重启时自己发的电源键通知(s2idle 醒来时 libinput 也会收到一个没人按的 Power Button 事件)。
  # 与其一个个堵唤醒源,不如让这个检查不存在:镜像已经完整写盘,断电方式对恢复没有影响。
  # 代价:S5 下不能用 USB/网卡唤醒休眠中的机器(本来也没用)。
  # 别拿 `cat /sys/power/disk` 核对:systemd 只在休眠那一刻才写入,平时一直显示 [platform]。
  systemd.sleep.settings.Sleep.HibernateMode = "shutdown";

  # 睡眠调试日志常开(2026-10-24)。读卡器 blacklist 之后休眠仍被打断过一次:10-23 23:25
  # 镜像已经写完,断电前 `Wakeup event detected during hibernation, rolling back`,
  # 但当时没开调试日志,不知道是谁 —— 而运行时 echo 进去的开关重启就复位,事后补不回来。
  # 开着之后失败时会多打一行 `PM: active wakeup source: <名字>`,平时几乎没有额外输出。
  # 那次回滚之后 amdgpu 的 sdma0 环超时、Mode2 reset 失败,GPU 再没恢复(黑屏、按电源键没反应,
  # 只能强关)。所以休眠被打断的代价不只是耗电,而是整台机器废掉。
  boot.kernelParams = [ "pm_debug_messages" ];

  # 放开 SysRq(默认 16 只允许 sync)。GPU 挂死时 KWin 跟着卡住,电源键交给 powerdevil 处理也没用,
  # 内核却还活着(logind 照样记 `Power key pressed`)。这时用 Alt+SysRq+R E I S U B 逐个按,
  # 先同步、卸载再重启,比长按电源键强关安全。本机 SysRq 在 Fn+S 或 PrtSc 上,不同键盘位置不一样。
  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest; # 取决于 flake.lock 锁定的 nixpkgs 版本 和 https://search.nixos.org/packages?channel=unstable 无关

  # Set your time zone.
  # 用新加坡而不是上海：同为 UTC+8,时间完全一样，但浏览器会把时区名原样暴露给网页脚本
  # (Intl...timeZone),claude.ai 里的 hCaptcha / Datadog / Stripe 都读得到,"Asia/Shanghai"
  # 等于直接报"在中国"(2026-10-01 实测)。新加坡是常驻地，也在 Anthropic 支持地区。
  time.timeZone = "Asia/Singapore";

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
      fcitx5-vinput
    ];
  };

  # 语音输入的另一半:识别在这个 daemon 里跑,fcitx5 插件只管按键和上屏(经 D-Bus 通信)。
  # 上游 unit 装在 share/systemd/user,systemd.packages 只扫 lib/systemd/user,所以这里自己声明。
  # 模型不进 Nix:在 vinput-gui 或 `vinput model add` 下载,落在 ~/.local/share/vinput 一类目录。
  systemd.user.services.vinput-daemon = {
    description = "Vinput Voice Input Daemon";
    after = [ "pipewire.service" ];
    wantedBy = [ "default.target" ];
    # 云端 provider(doubaoime 等)是 daemon 拉起的 python 脚本,继承这里的环境。
    # 脚本用 ctypes.util.find_library("opus") 找库,NixOS 上没有 ldconfig 缓存,
    # 上游 wrapper 塞的 LD_LIBRARY_PATH 它不查(实测返回 None),只能显式给路径。
    environment.VINPUT_ASR_LIBOPUS_PATH = "${pkgs.libopus}/lib/libopus.so.0";
    serviceConfig = {
      Type = "dbus";
      BusName = "org.fcitx.Vinput";
      ExecStart = "${fcitx5-vinput}/bin/vinput-daemon";
    };
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
