
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
      repository = "rclone:kp_cst:/kp/"; # 'kp_cst' matches rclone config name
      
      # Automation settings
      initialize = true;
      passwordFile = config.age.secrets.restic_repository.path;
      timerConfig = {
        OnCalendar="*:0/1";
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
