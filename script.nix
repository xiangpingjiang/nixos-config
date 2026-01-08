{
  lib,
  config,
  pkgs,
  ...
}:

{
  systemd.services.aliyunpan-sync = {
    description = "aliyunpan sync";
    wantedBy = [ "basic.target" ];
    # 脚本的绝对路径
    script = ''
      ${pkgs.bash}/bin/bash  /home/xpj/Downloads/aliyunpan-v0.3.7-linux-amd64/sync.sh 
    '';
    serviceConfig = {
      RestartSec = 5;
    };
  };

}
