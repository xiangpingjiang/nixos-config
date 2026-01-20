
{
  ...
}:

{

  programs = {
    # 默认使用 zsh 。 在 konsole profile 里配置
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      enableBashCompletion = true;
      ohMyZsh = {
        enable = true;
        theme = "robbyrussell";
        plugins = [
          "git"
          "dirhistory"
          "history"
        ];
      };
    };

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
  };
}

