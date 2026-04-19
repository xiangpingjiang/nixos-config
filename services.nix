{
  pkgs,
  config,
  ...
}:
let
  resticBackupsBaseSettings = {
    # Automation settings
    initialize = true;
    passwordFile = config.age.secrets.restic_repository.path;
    rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
    # Maintain backups
    pruneOpts = [
      "--keep-daily 7" # 保留最近 7 天的每日备份
      "--keep-weekly 4" # 保留最近 4 周的每周备份
      "--keep-monthly 3" # 保留最近 3 个月的每月备份
    ];
  };
in
{
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = config.age.secrets.mihomo_config.path;
    # configFile = "/home/xpj/Projects/nixos-config/mihomo_test_config.yaml" 测试调试用;
  };

  services.restic = {
    backups = {
      webdav-backup = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_cst:/kp/"; # 'kp_cst' matches rclone config name, kp created before
        timerConfig = {
          OnCalendar = "*:0/3"; # *：代表 “每一小时”（小时维度不限制） :：分隔小时和分钟 0/3：代表 “从第 0 分钟开始，每隔 3 分钟”
        };
      };

      webdav-backup-nutstore = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_nutstore:/kp/";
        timerConfig = {
          OnCalendar = "*:1/3";
        };
      };

      webdav-backup-infini = resticBackupsBaseSettings // {
        paths = [ "/home/xpj/Documents/sync/kp/" ];
        repository = "rclone:kp_infini:/kp/";
        timerConfig = {
          OnCalendar = "*:2/3"; # *：代表 “每一小时”（小时维度不限制） :：分隔小时和分钟 2/3：代表 “从第 2 分钟开始，每隔 3 分钟”
        };
      };
    };
    # server.prometheus = true;
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

  # services.ollama = {
  #   enable = true;
  #   loadModels = [ "qwen3.5:0.8b" ];
  #   syncModels = true;
  # };

  # services.prometheus = {
  #   enable = true;
  #   # alertmanager.enable = true;
  #   enableReload = true;
  #   exporters = {
  #     node = {
  #       enable = true;
  #       port = 9100;
  #     };
  #     # restic.enable = true;
  #     # systemd.enable = true;
  #   };
  #   globalConfig = {
  #     scrape_interval = "10s";
  #   };
  #   scrapeConfigs = [
  #     {
  #       job_name = "node";
  #       static_configs = [
  #         {
  #           targets = [ "127.0.0.1:9100" ];
  #         }
  #       ];
  #     }
  #   ];
  #   retentionTime = "15d";
  # };
}
