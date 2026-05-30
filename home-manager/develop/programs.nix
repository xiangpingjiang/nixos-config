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

  xdg.configFile."zellij/layouts/dev.kdl".text = ''
    layout {
      default_tab_template {
        pane size=1 borderless=true {
          plugin location="zellij:tab-bar"
        }

        children

        pane size=2 borderless=true {
          plugin location="zellij:status-bar"
        }
      }

      tab name="editor" {
        pane
        pane split_direction="vertical" {
          pane command="htop"
          pane command="lazygit"
        }
      }

      tab name="logs" {
        pane command="journalctl" {
          args "-f"
        }
      }
    }
  '';
}
