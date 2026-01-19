{
  ...
}:

{
  networking = {
    hostName = "nixos"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.

    networkmanager.enable = true;
    firewall = {
       # localsend use 53317
      allowedTCPPorts = [ 53317 ];
      allowedUDPPorts = [ 53317 ];
      # enable = false;
      trustedInterfaces = [ "Mihomo" ];
      checkReversePath = false;
    };

    # proxy = {
    #   default = "http://127.0.0.1:7897";
    #   httpsProxy = "http://127.0.0.1:7897";
    #   httpProxy = "http://127.0.0.1:7897";
    #   allProxy = "http://127.0.0.1:7897";
    #   noProxy = "127.0.0.1,localhost";
    # };
  };

}