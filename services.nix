
{
  pkgs,
  ...
}:

{
# services.mihomo = {
#   enable = true;
#   tunMode = true;
#   webui = pkgs.metacubexd;
#   configFile = "/home/xpj/.config/mihomo/newConfig.yaml";
# };

  services.power-profiles-daemon.enable = false;

  services.auto-cpufreq.enable = true;

}
