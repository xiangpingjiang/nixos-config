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

