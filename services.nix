
{
  pkgs,
  config,
  ...
}:

{
services.mihomo = {
  enable = true;
  tunMode = true;
  webui = pkgs.metacubexd;
  #todo , not aliyunpan_config.json for config file
  configFile = "/home/xpj/Projects/nixos-config/config/mihomo.yaml";
};


  # 测试后发现auto-cpufreq效果不如 ppd
  # services.power-profiles-daemon.enable = true;
  # services.auto-cpufreq.enable = true;

  services.restic.backups = {
    webdav-backup = {
      paths = [ "/home/xpj/Documents/sync/kp/" ];
      repository = "rclone:kp_cst:/kp/"; # 'kp_cst' matches rclone config name, kp created before
      
      # Automation settings
      initialize = true;
      passwordFile = config.age.secrets.restic_repository.path;
      timerConfig = {
        OnCalendar="*:0/3";  # *：代表 “每一小时”（小时维度不限制） :：分隔小时和分钟 0/3：代表 “从第 0 分钟开始，每隔 3 分钟”
      };
      rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
      
      # Maintain backups 
      pruneOpts = [
        "--keep-daily 7" # 保留最近 7 天的每日备份
        "--keep-weekly 4" # 保留最近 4 周的每周备份
        "--keep-monthly 3" # 保留最近 3 个月的每月备份
      ];
    };

    webdav-backup-nutstore = {
      paths = [ "/home/xpj/Documents/sync/kp/" ];
      repository = "rclone:kp_nutstore:/kp/"; # 'kp_cst' matches rclone config name,  kp created before
      
      # Automation settings
      initialize = true;
      passwordFile = config.age.secrets.restic_repository.path;
      timerConfig = {
        OnCalendar="*:3/5";
      };
      rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
      
      # Maintain backups
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 3"
      ];
    };

    webdav-backup-infini = {
      paths = [ "/home/xpj/Documents/sync/kp/" ];
      repository = "rclone:kp_infini:/kp/";
      
      # Automation settings
      initialize = true;
      passwordFile = config.age.secrets.restic_repository.path;
      timerConfig = {
        OnCalendar="*:2/3";  # *：代表 “每一小时”（小时维度不限制） :：分隔小时和分钟 2/3：代表 “从第 2 分钟开始，每隔 3 分钟”
      };
      rcloneConfigFile = "/home/xpj/.config/rclone/rclone.conf";
      
      # Maintain backups
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 3"
      ];
    };
  };


}
