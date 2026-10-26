{
  pkgs,
  ...
}:
{

  programs = {
    ghostty = {
      enable = true;
      settings = {
        # shell-integration = zsh;
        shell-integration-features = "ssh-env,ssh-terminfo";
        command = "${pkgs.zsh}/bin/zsh";
        theme = "Tomorrow Night Eighties";
        # font-size = 10;
        # keybind = [
        #   "ctrl+h=goto_split:left"
        #   "ctrl+l=goto_split:right"
        # ];
      };
    };

    # 配置使用 zsh
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        theme = "";
        plugins = [
          "git"
          "dirhistory"
          "history"
          "direnv"
          "kubectl"
        ];
      };
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      # kubernetes 模块默认是关的;不写 detect_* 就在所有目录显示当前 context
      settings.kubernetes.disabled = false;
    };

    java = {
      enable = true;
      package = pkgs.jdk21;
    };

    zellij = {
      enable = true;
      settings = {
        default_shell = "zsh";
        default_layout = "dev";

      };
    };

  };

  xdg.configFile."zellij/layouts/dev.kdl".text = builtins.readFile ./zellij/dev.kdl;

  # 进 devenv 目录时 direnv 默认打印整串 `+AR +AS +NIX_CFLAGS_COMPILE ...`,
  # zellij 窗格一窄就折成半屏;只保留 loading 提示,不列变量差异。
  xdg.configFile."direnv/direnv.toml".text = ''
    [global]
    hide_env_diff = true
  '';
}
