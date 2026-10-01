{
  pkgs,
  ...
}:

{

  networking = {
    hostName = "nixos"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.

    networkmanager = {
      enable = true;
      plugins = [ pkgs.networkmanager-openvpn ];
      # ensureProfiles = {
      #   profiles = {
      #     RFvpn = {
      #       connection = {
      #         id = "RFvpn";
      #         type = "vpn";
      #       };
      #       ipv4 = {
      #         # 把默认 50 改成你想要的 metric（比如 100）
      #         route-metric = 100;
      #       };
      #       ipv6 = {
      #         route-metric = 100;
      #       };
      #       # VPN 类型（openvpn/strongswan）如果需要可以补：
      #       # vpn = {
      #       #   service-type = "org.freedesktop.NetworkManager.openvpn";
      #       # };
      #     };
      #   };
      # };
    };
    firewall = {
      # localsend use 53317
      # mihomo 的 7890/7891/7897 不放行:配置是 allow-lan: false、只绑 127.0.0.1,
      # 放行是死配置;哪天打开 allow-lan,同一 LAN 的人就能无认证地拿它当代理
      # (出境、公司 10.x 内网都通)。
      allowedTCPPorts = [ 53317 ];
      allowedUDPPorts = [ 53317 ];
      # enable = false;
      trustedInterfaces = [
        "Mihomo"
        "tunRFvnp"
      ];
      checkReversePath = false;
    };
  };

}
