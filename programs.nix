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
      };
    };

    firefox = {
      enable = true;
    };
    steam = {
      enable = true;
      protontricks.enable = true;
    };
    appimage = {
      enable = true;
      binfmt = true; # 注册 binfmt，让 AppImage 可以直接双击/直接执行
    };
  };
}
