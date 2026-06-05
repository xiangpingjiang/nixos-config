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
      allowedTCPPorts = [
        53317
        # Mihomo / Clash
        7890 # HTTP
        7891 # SOCKS5
        7897 # Mixed
      ];
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
