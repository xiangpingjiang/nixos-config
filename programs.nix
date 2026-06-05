{
  ...
}:

{

  programs = {

    git = {
      enable = true;
      #globalConfig file:/etc/gitconfig
      config = {
        user = {
          name = "xiangpingjiang";
          email = "xiangpingjiang1998@gmail.com";
        };
        init.defaultBranch = "main";
        diff."age" = {
          textconv = "/run/current-system/sw/bin/age -d -i /home/xpj/.ssh/id_ed25519";
          binary = true;
        };
        diff."sops" = {
          textconv = "/home/xpj/.nix-profile/bin/sops -d";
          binary = true;
        };
      };
    };

    appimage = {
      enable = true;
      binfmt = true; # 注册 binfmt，让 AppImage 可以直接双击/直接执行
    };

    nix-ld.enable = true; # 解决的是 NixOS 上运行非 NixOS 打包的二进制时报错的问题。 相当于开了个口子让"外来"二进制能跑
  };
}
