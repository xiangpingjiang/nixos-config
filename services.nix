
{
  pkgs,
  ...
}:

{
services.mihomo = {
  enable = true;
  tunMode = true;
  webui = pkgs.metacubexd;
  configFile = "/home/xpj/.config/mihomo/newConfig.yaml";
};


  # 测试后发现auto-cpufreq效果不如 ppd
  # services.power-profiles-daemon.enable = true;
  # services.auto-cpufreq.enable = true;

}
