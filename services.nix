{
  pkgs,
  config,
  lib,
  ...
}:
let
  resticBackupsBaseSettings = {
    # Automation settings
    initialize = true;
    passwordFile = config.age.secrets.restic_repository.path;
    rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
    # 遇到锁时最多等 3 分钟再报错，避免与其它任务的共享锁瞬时冲突。
    # 注意：prune 已从此处剥离，改由下面每日的 restic-prune 任务统一执行。
    extraBackupArgs = [ "--retry-lock=3m" ];
  };
in
{
  services.mihomo = {
    enable = true;
    tunMode = false;
    webui = pkgs.metacubexd;
    configFile = config.sops.secrets.mihomo_config.path;
  };

  services.restic = {
    backups = {
      webdav-backup = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_cst:/kp/"; # 'kp_cst' matches rclone config name, kp created before
        timerConfig = {
          OnCalendar = "*:0/10"; # 从第 0 分钟起，每 10 分钟一次（:00 :10 :20 …）
        };
      };

      webdav-backup-nutstore = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_nutstore:/kp/";
        timerConfig = {
          OnCalendar = "*:3/10"; # 从第 3 分钟起，每 10 分钟一次（:03 :13 :23 …）错开
        };
      };

      webdav-backup-infini = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_infini:/kp/";
        timerConfig = {
          OnCalendar = "*:6/10"; # 从第 6 分钟起，每 10 分钟一次（:06 :16 :26 …）错开
        };
      };
    };
  };

  # 把 forget+prune 从每次备份里剥离，单独每天跑一次，
  # 大幅降低独占锁的频率（之前那把 4 个月的死锁就来自跟着每 3 分钟备份跑的 prune）。
  # 仓库列表自动从上面的 services.restic.backups 派生，增删备份时无需同步修改。
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
        repos = lib.mapAttrsToList (_: b: b.repository) config.services.restic.backups;
      in
      ''
        for repo in ${lib.escapeShellArgs repos}; do
          echo "== forget+prune $repo =="
          ${pkgs.restic}/bin/restic -r "$repo" forget --prune \
            --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
            --retry-lock 10m || echo "!! prune 失败: $repo（继续下一个仓库）"
        done
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
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak remote-modify flathub \
        --url=https://mirrors.ustc.edu.cn/flathub
    '';
  };
}
