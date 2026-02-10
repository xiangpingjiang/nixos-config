
{
  pkgs,
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

}
