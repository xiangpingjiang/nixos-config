{
  ...
}:
{

  programs = {

    chromium = {
      enable = true;
      # package = inputs.nixpkgs-chromium-144.legacyPackages.x86_64-linux.chromium;
      commandLineArgs = [
        # https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland#KDE_Plasma
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        # "--user-data-dir=$HOME/.config/chromium-compat" # 和最新版本的不兼容，这条命令数据隔离
      ];
    };
    firefox = {
      enable = true;
    };
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "github.com" = {
          HostName = "ssh.github.com";
          User = "git";
          Port = 443;
          IdentitiesOnly = true;
        };
        "*" = {
          ServerAliveInterval = 60;
        };
        dev75 = {
          HostName = "10.130.10.75";
          User = "root";
          Port = 22;
        };
        dev76 = {
          HostName = "10.130.10.76";
          User = "ecs-user";
          Port = 22;
        };
        jen = {
          HostName = "jumpserver.rockflow.ai";
          User = "xiangpingjiang#localadmin#0d71f23d-8f64-4b71-bbe1-2ca8d0588f50";
          Port = 2222;
        };
        openclaw = {
          HostName = "jumpserver.rockflow.ai";
          User = "xiangpingjiang#ecs-user#bf7eff4f-dd9a-46bc-9a43-1eb1dd60d0d8";
          Port = 2222;
        };
        vk = {
          HostName = "10.65.255.26";
          User = "vk1";
          Port = 22;
        };
      };
    };
  };
}
