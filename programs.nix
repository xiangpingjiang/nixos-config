
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
  };
}

