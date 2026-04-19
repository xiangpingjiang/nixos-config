{

  pkgs,
  ...
}:

{
  programs.konsole = {
    enable = true;
    defaultProfile = "xpj";
    profiles = {
      "xpj" = {
        command = "${pkgs.zsh}/bin/zsh";
        font.size = 13;
        colorScheme = "Black on White";
      };
    };
  };
  programs.plasma = {
    enable = true;
    window-rules = [
      {
        description = "Insomnia icon fix in task switcher";
        match = {
          window-class = {
            value = "insomnia Insomnia";
            type = "exact";
          };
          window-types = [
            "normal"
            "desktop"
            "dock"
            "toolbar"
            "torn-of-menu"
            "dialog"
            "menubar"
            "utility"
            "spash"
            "osd"
          ];
        };
        apply = {
          desktopfile = {
            value = "insomnia";
            apply = "force";
          };
        };
      }
      {
        description = "localsend icon fix in task switcher";
        match = {
          window-class = {
            value = "localsend_app";
            type = "exact";
          };
          window-types = [
            "normal"
            "desktop"
            "dock"
            "toolbar"
            "torn-of-menu"
            "dialog"
            "menubar"
            "utility"
            "spash"
            "osd"
          ];
        };
        apply = {
          desktopfile = {
            value = "LocalSend";
            apply = "initially";
          };
        };
      }
    ];

    workspace = {
      lookAndFeel = "org.kde.breeze.desktop";
      iconTheme = "Breeze Light";
      cursor = {
        theme = "Breeze Dark";
        size = 30;
      };
      wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/Autumn/contents/images/2560x1440.jpg";
    };

    kscreenlocker = {
      autoLock = true;
      timeout = 3;
      appearance.wallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/Path/contents/images/2560x1440.jpg";
    };

    panels = [
      # Windows-like panel at the bottom
      {
        location = "bottom";
        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          {
            iconTasks = {
              launchers = [
                "applications:systemsettings.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:org.kde.plasma-systemmonitor.desktop"
                "applications:code.desktop"
                "applications:chromium-browser.desktop"
              ];
              appearance.showTooltips = true;
            };
          }
          "org.kde.plasma.marginsseparator"
          {
            # cat ~/.config/plasma-org.kde.plasma.desktop-appletsrc
            systemTray = {
              items = {
                showAll = false;
                shown = [
                  "org.kde.plasma.notifications"
                  "org.kde.plasma.networkmanagement"
                  "org.kde.plasma.bluetooth"
                  "org.kde.plasma.volume"
                  "org.kde.plasma.brightness"
                  "org.kde.plasma.battery"
                  "org.kde.plasma.manage-inputmethod"
                  "org.kde.plasma.keyboardindicator"
                  "Fcitx"
                ];
              };
            };
          }
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
    shortcuts = {
      ActivityManager.switch-to-activity-c843b20a-5f2b-41f6-a014-0824867d473b = [ ];
      "KDE Keyboard Layout Switcher"."Switch keyboard layout to English (US)" = [ ];
      "KDE Keyboard Layout Switcher"."Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Meta+Alt+K";
      kaccess."Toggle Screen Reader On and Off" = "Meta+Alt+S";
      kmix.decrease_microphone_volume = "Microphone Volume Down";
      kmix.decrease_volume = "Volume Down";
      kmix.decrease_volume_small = "Shift+Volume Down";
      kmix.increase_microphone_volume = "Microphone Volume Up";
      kmix.increase_volume = "Volume Up";
      kmix.increase_volume_small = "Shift+Volume Up";
      kmix.mic_mute = [
        "Microphone Mute"
        "Meta+Volume Mute"
      ];
      kmix.mute = "Volume Mute";
      ksmserver."Halt Without Confirmation" = [ ];
      ksmserver."Lock Session" = [
        "Meta+L"
        "Screensaver"
      ];
      ksmserver."Log Out" = "Ctrl+Alt+Del";
      ksmserver."Log Out Without Confirmation" = [ ];
      ksmserver.LogOut = [ ];
      ksmserver.Reboot = [ ];
      ksmserver."Reboot Without Confirmation" = [ ];
      ksmserver."Shut Down" = [ ];
      kwin."Activate Window Demanding Attention" = "Meta+Ctrl+A";
      kwin."Cycle Overview" = [ ];
      kwin."Cycle Overview Opposite" = [ ];
      kwin."Decrease Opacity" = [ ];
      kwin."Edit Tiles" = "Meta+T";
      kwin.Expose = "Ctrl+F9";
      kwin.ExposeAll = [
        "Ctrl+F10"
        "Launch (C)"
      ];
      kwin.ExposeClass = "Ctrl+F7";
      kwin.ExposeClassCurrentDesktop = [ ];
      kwin."Grid View" = "Meta+G";
      kwin."Increase Opacity" = [ ];
      kwin."Kill Window" = "Meta+Ctrl+Esc";
      kwin."Move Tablet to Next Output" = [ ];
      kwin.MoveMouseToCenter = "Meta+F6";
      kwin.MoveMouseToFocus = "Meta+F5";
      kwin.MoveZoomDown = [ ];
      kwin.MoveZoomLeft = [ ];
      kwin.MoveZoomRight = [ ];
      kwin.MoveZoomUp = [ ];
      kwin.Overview = "Meta+W";
      kwin."Setup Window Shortcut" = [ ];
      kwin."Show Desktop" = "Meta+D";
      kwin."Switch One Desktop Down" = "Meta+Ctrl+Down";
      kwin."Switch One Desktop Up" = "Meta+Ctrl+Up";
      kwin."Switch One Desktop to the Left" = "Meta+Ctrl+Left";
      kwin."Switch One Desktop to the Right" = "Meta+Ctrl+Right";
      kwin."Switch Window Down" = "Meta+Alt+Down";
      kwin."Switch Window Left" = "Meta+Alt+Left";
      kwin."Switch Window Right" = "Meta+Alt+Right";
      kwin."Switch Window Up" = "Meta+Alt+Up";
      kwin."Switch to Desktop 1" = "Ctrl+F1";
      kwin."Switch to Desktop 10" = [ ];
      kwin."Switch to Desktop 11" = [ ];
      kwin."Switch to Desktop 12" = [ ];
      kwin."Switch to Desktop 13" = [ ];
      kwin."Switch to Desktop 14" = [ ];
      kwin."Switch to Desktop 15" = [ ];
      kwin."Switch to Desktop 16" = [ ];
      kwin."Switch to Desktop 17" = [ ];
      kwin."Switch to Desktop 18" = [ ];
      kwin."Switch to Desktop 19" = [ ];
      kwin."Switch to Desktop 2" = "Ctrl+F2";
      kwin."Switch to Desktop 20" = [ ];
      kwin."Switch to Desktop 3" = "Ctrl+F3";
      kwin."Switch to Desktop 4" = "Ctrl+F4";
      kwin."Switch to Desktop 5" = [ ];
      kwin."Switch to Desktop 6" = [ ];
      kwin."Switch to Desktop 7" = [ ];
      kwin."Switch to Desktop 8" = [ ];
      kwin."Switch to Desktop 9" = [ ];
      kwin."Switch to Next Desktop" = [ ];
      kwin."Switch to Next Screen" = [ ];
      kwin."Switch to Previous Desktop" = [ ];
      kwin."Switch to Previous Screen" = [ ];
      kwin."Switch to Screen 0" = [ ];
      kwin."Switch to Screen 1" = [ ];
      kwin."Switch to Screen 2" = [ ];
      kwin."Switch to Screen 3" = [ ];
      kwin."Switch to Screen 4" = [ ];
      kwin."Switch to Screen 5" = [ ];
      kwin."Switch to Screen 6" = [ ];
      kwin."Switch to Screen 7" = [ ];
      kwin."Switch to Screen Above" = [ ];
      kwin."Switch to Screen Below" = [ ];
      kwin."Switch to Screen to the Left" = [ ];
      kwin."Switch to Screen to the Right" = [ ];
      kwin."Toggle Night Color" = [ ];
      kwin."Toggle Window Raise/Lower" = [ ];
      kwin."Walk Through Windows" = [
        "Meta+Tab"
        "Alt+Tab"
      ];
      kwin."Walk Through Windows (Reverse)" = [
        "Meta+Shift+Tab"
        "Alt+Shift+Tab"
      ];
      kwin."Walk Through Windows Alternative" = [ ];
      kwin."Walk Through Windows Alternative (Reverse)" = [ ];
      kwin."Walk Through Windows of Current Application" = [
        "Meta+`"
        "Alt+`"
      ];
      kwin."Walk Through Windows of Current Application (Reverse)" = [
        "Meta+~"
        "Alt+~"
      ];
      kwin."Walk Through Windows of Current Application Alternative" = [ ];
      kwin."Walk Through Windows of Current Application Alternative (Reverse)" = [ ];
      kwin."Window Above Other Windows" = [ ];
      kwin."Window Below Other Windows" = [ ];
      kwin."Window Close" = "Alt+F4";
      kwin."Window Custom Quick Tile Bottom" = [ ];
      kwin."Window Custom Quick Tile Left" = [ ];
      kwin."Window Custom Quick Tile Right" = [ ];
      kwin."Window Custom Quick Tile Top" = [ ];
      kwin."Window Fullscreen" = [ ];
      kwin."Window Grow Horizontal" = [ ];
      kwin."Window Grow Vertical" = [ ];
      kwin."Window Lower" = [ ];
      kwin."Window Maximize" = "Meta+PgUp";
      kwin."Window Maximize Horizontal" = [ ];
      kwin."Window Maximize Vertical" = [ ];
      kwin."Window Minimize" = "Meta+PgDown";
      kwin."Window Move" = [ ];
      kwin."Window Move Center" = [ ];
      kwin."Window No Border" = [ ];
      kwin."Window On All Desktops" = [ ];
      kwin."Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
      kwin."Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
      kwin."Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
      kwin."Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
      kwin."Window One Screen Down" = [ ];
      kwin."Window One Screen Up" = [ ];
      kwin."Window One Screen to the Left" = [ ];
      kwin."Window One Screen to the Right" = [ ];
      kwin."Window Operations Menu" = "Alt+F3";
      kwin."Window Pack Down" = [ ];
      kwin."Window Pack Left" = [ ];
      kwin."Window Pack Right" = [ ];
      kwin."Window Pack Up" = [ ];
      kwin."Window Quick Tile Bottom" = "Meta+Down";
      kwin."Window Quick Tile Bottom Left" = [ ];
      kwin."Window Quick Tile Bottom Right" = [ ];
      kwin."Window Quick Tile Left" = "Meta+Left";
      kwin."Window Quick Tile Right" = "Meta+Right";
      kwin."Window Quick Tile Top" = "Meta+Up";
      kwin."Window Quick Tile Top Left" = [ ];
      kwin."Window Quick Tile Top Right" = [ ];
      kwin."Window Raise" = [ ];
      kwin."Window Resize" = [ ];
      kwin."Window Shrink Horizontal" = [ ];
      kwin."Window Shrink Vertical" = [ ];
      kwin."Window to Desktop 1" = [ ];
      kwin."Window to Desktop 10" = [ ];
      kwin."Window to Desktop 11" = [ ];
      kwin."Window to Desktop 12" = [ ];
      kwin."Window to Desktop 13" = [ ];
      kwin."Window to Desktop 14" = [ ];
      kwin."Window to Desktop 15" = [ ];
      kwin."Window to Desktop 16" = [ ];
      kwin."Window to Desktop 17" = [ ];
      kwin."Window to Desktop 18" = [ ];
      kwin."Window to Desktop 19" = [ ];
      kwin."Window to Desktop 2" = [ ];
      kwin."Window to Desktop 20" = [ ];
      kwin."Window to Desktop 3" = [ ];
      kwin."Window to Desktop 4" = [ ];
      kwin."Window to Desktop 5" = [ ];
      kwin."Window to Desktop 6" = [ ];
      kwin."Window to Desktop 7" = [ ];
      kwin."Window to Desktop 8" = [ ];
      kwin."Window to Desktop 9" = [ ];
      kwin."Window to Next Desktop" = [ ];
      kwin."Window to Next Screen" = "Meta+Shift+Right";
      kwin."Window to Previous Desktop" = [ ];
      kwin."Window to Previous Screen" = "Meta+Shift+Left";
      kwin."Window to Screen 0" = [ ];
      kwin."Window to Screen 1" = [ ];
      kwin."Window to Screen 2" = [ ];
      kwin."Window to Screen 3" = [ ];
      kwin."Window to Screen 4" = [ ];
      kwin."Window to Screen 5" = [ ];
      kwin."Window to Screen 6" = [ ];
      kwin."Window to Screen 7" = [ ];
      kwin.disableInputCapture = "Meta+Shift+Esc";
      kwin.view_actual_size = "Meta+0";
      kwin.view_zoom_in = [
        "Meta++"
        "Meta+="
      ];
      kwin.view_zoom_out = "Meta+-";
      mediacontrol.mediavolumedown = [ ];
      mediacontrol.mediavolumeup = [ ];
      mediacontrol.nextmedia = "Media Next";
      mediacontrol.pausemedia = "Media Pause";
      mediacontrol.playmedia = [ ];
      mediacontrol.playpausemedia = "Media Play";
      mediacontrol.previousmedia = "Media Previous";
      mediacontrol.stopmedia = "Media Stop";
      "org.chromium.Chromium"."83C83A03321205B57705177438D76442-next" = [ ];
      "org.chromium.Chromium"."83C83A03321205B57705177438D76442-revert" = [ ];
      "org.chromium.Chromium"."83C83A03321205B57705177438D76442-toggle" = [ ];
      org_kde_powerdevil."Decrease Keyboard Brightness" = "Keyboard Brightness Down";
      org_kde_powerdevil."Decrease Screen Brightness" = "Monitor Brightness Down";
      org_kde_powerdevil."Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
      org_kde_powerdevil.Hibernate = "Hibernate";
      org_kde_powerdevil."Increase Keyboard Brightness" = "Keyboard Brightness Up";
      org_kde_powerdevil."Increase Screen Brightness" = "Monitor Brightness Up";
      org_kde_powerdevil."Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
      org_kde_powerdevil.PowerDown = "Power Down";
      org_kde_powerdevil.PowerOff = "Power Off";
      org_kde_powerdevil.Sleep = "Sleep";
      org_kde_powerdevil."Toggle Keyboard Backlight" = "Keyboard Light On/Off";
      org_kde_powerdevil."Turn Off Screen" = [ ];
      org_kde_powerdevil.powerProfile = [
        "Battery"
        "Meta+B"
      ];
      plasmashell."Slideshow Wallpaper Next Image" = [ ];
      plasmashell."activate application launcher" = [
        "Meta"
        "Alt+F1"
      ];
      plasmashell."activate task manager entry 1" = "Meta+1";
      plasmashell."activate task manager entry 10" = [ ];
      plasmashell."activate task manager entry 2" = "Meta+2";
      plasmashell."activate task manager entry 3" = "Meta+3";
      plasmashell."activate task manager entry 4" = "Meta+4";
      plasmashell."activate task manager entry 5" = "Meta+5";
      plasmashell."activate task manager entry 6" = "Meta+6";
      plasmashell."activate task manager entry 7" = "Meta+7";
      plasmashell."activate task manager entry 8" = "Meta+8";
      plasmashell."activate task manager entry 9" = "Meta+9";
      plasmashell.clear-history = [ ];
      plasmashell.clipboard_action = "Meta+Ctrl+X";
      plasmashell.cycle-panels = "Meta+Alt+P";
      plasmashell.cycleNextAction = [ ];
      plasmashell.cyclePrevAction = [ ];
      plasmashell.edit_clipboard = [ ];
      plasmashell."manage activities" = "Meta+Q";
      plasmashell."next activity" = "Meta+A";
      plasmashell."previous activity" = "Meta+Shift+A";
      plasmashell.repeat_action = [ ];
      plasmashell."show dashboard" = "Ctrl+F12";
      plasmashell.show-barcode = [ ];
      plasmashell.show-on-mouse-pos = "Meta+V";
      plasmashell."switch to next activity" = [ ];
      plasmashell."switch to previous activity" = [ ];
      plasmashell."toggle do not disturb" = [ ];
      "services/com.mitchellh.ghostty.desktop"._launch = [ ];
    };
    configFile = {
      baloofilerc.General.dbVersion = 2;
      baloofilerc.General."exclude filters" =
        "*~,*.part,*.o,*.la,*.lo,*.loT,*.moc,moc_*.cpp,qrc_*.cpp,ui_*.h,cmake_install.cmake,CMakeCache.txt,CTestTestfile.cmake,libtool,config.status,confdefs.h,autom4te,conftest,confstat,Makefile.am,*.gcode,.ninja_deps,.ninja_log,build.ninja,*.csproj,*.m4,*.rej,*.gmo,*.pc,*.omf,*.aux,*.tmp,*.po,*.vm*,*.nvram,*.rcore,*.swp,*.swap,lzo,litmain.sh,*.orig,.histfile.*,.xsession-errors*,*.map,*.so,*.a,*.db,*.qrc,*.ini,*.init,*.img,*.vdi,*.vbox*,vbox.log,*.qcow2,*.vmdk,*.vhd,*.vhdx,*.sql,*.sql.gz,*.ytdl,*.tfstate*,*.class,*.pyc,*.pyo,*.elc,*.qmlc,*.jsc,*.fastq,*.fq,*.gb,*.fasta,*.fna,*.gbff,*.faa,po,CVS,.svn,.git,_darcs,.bzr,.hg,CMakeFiles,CMakeTmp,CMakeTmpQmake,.moc,.obj,.pch,.uic,.npm,.yarn,.yarn-cache,__pycache__,node_modules,node_packages,nbproject,.terraform,.venv,venv,core-dumps,lost+found";
      baloofilerc.General."exclude filters version" = 9;
      dolphinrc.General.ViewPropsTimestamp = "2026,1,7,9,13,55.982";
      dolphinrc."KFileDialog Settings"."Places Icons Auto-resize" = false;
      dolphinrc."KFileDialog Settings"."Places Icons Static Size" = 22;
      kactivitymanagerdrc.activities.c843b20a-5f2b-41f6-a014-0824867d473b = "Default";
      kactivitymanagerdrc.main.currentActivity = "c843b20a-5f2b-41f6-a014-0824867d473b";
      kcminputrc."Libinput/1133/45114/LOGI M240 Mouse".PointerAcceleration = 0.200;
      kcminputrc."Libinput/1267/12928/ELAN06FA:00 04F3:3280 Touchpad".NaturalScroll = true;
      kcminputrc."Libinput/1267/12928/ELAN06FA:00 04F3:3280 Touchpad".PointerAcceleration = 0.200;
      kcminputrc."Libinput/1267/12928/ELAN06FA:00 04F3:3280 Touchpad".ScrollFactor = 1.5;
      kded5rc.Module-browserintegrationreminder.autoload = false;
      kded5rc.Module-device_automounter.autoload = false;
      kdeglobals.General.TerminalApplication = "/nix/store/k3wrd5n1a709fkhrv52mwnxqyabl55jw-ghostty-1.2.3/bin/ghostty --gtk-single-instance=true";
      kdeglobals.General.TerminalService = "com.mitchellh.ghostty.desktop";
      kdeglobals.General.UseSystemBell = true;
      kdeglobals."KFileDialog Settings"."Allow Expansion" = false;
      kdeglobals."KFileDialog Settings"."Automatically select filename extension" = true;
      kdeglobals."KFileDialog Settings"."Breadcrumb Navigation" = true;
      kdeglobals."KFileDialog Settings"."Decoration position" = 2;
      kdeglobals."KFileDialog Settings"."Show Full Path" = false;
      kdeglobals."KFileDialog Settings"."Show Inline Previews" = true;
      kdeglobals."KFileDialog Settings"."Show Preview" = false;
      kdeglobals."KFileDialog Settings"."Show Speedbar" = true;
      kdeglobals."KFileDialog Settings"."Show hidden files" = false;
      kdeglobals."KFileDialog Settings"."Sort by" = "Name";
      kdeglobals."KFileDialog Settings"."Sort directories first" = true;
      kdeglobals."KFileDialog Settings"."Sort hidden files last" = false;
      kdeglobals."KFileDialog Settings"."Sort reversed" = false;
      kdeglobals."KFileDialog Settings"."Speedbar Width" = 138;
      kdeglobals."KFileDialog Settings"."View Style" = "DetailTree";
      kdeglobals.KScreen.ScreenScaleFactors = "eDP-1=1;";
      kdeglobals.KScreen.XwaylandClientsScale = false;
      kdeglobals."KShortcutsDialog Settings"."Dialog Size" = "600,480";
      kdeglobals.WM.activeBackground = "227,229,231";
      kdeglobals.WM.activeBlend = "227,229,231";
      kdeglobals.WM.activeForeground = "35,38,41";
      kdeglobals.WM.inactiveBackground = "239,240,241";
      kdeglobals.WM.inactiveBlend = "239,240,241";
      kdeglobals.WM.inactiveForeground = "112,125,138";
      kiorc.Confirmations.ConfirmEmptyTrash = true;
      ksmserverrc.General.loginMode = "emptySession";
      kwalletrc.Wallet."First Use" = false;
      kwinrc.Desktops.Id_1 = "573a2d7b-fc66-453e-ad9e-c493badc4ea6";
      kwinrc.Desktops.Number = 1;
      kwinrc.Desktops.Rows = 1;
      kwinrc.EdgeBarrier.CornerBarrier = false;
      kwinrc.EdgeBarrier.EdgeBarrier = 0;
      kwinrc.Effect-zoom.ZoomFactor = 1.25;
      kwinrc.TabBox.ApplicationsMode = 1;
      kwinrc.TabBox.LayoutName = "big_icons";
      kwinrc.Tiling.padding = 4;
      kwinrc."Tiling/573a2d7b-fc66-453e-ad9e-c493badc4ea6/3813ea82-bf86-469b-b810-2d0cdd8cb965".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/573a2d7b-fc66-453e-ad9e-c493badc4ea6/3a2f59fd-768d-4340-8361-3c8aae7f286f".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/573a2d7b-fc66-453e-ad9e-c493badc4ea6/b166dfbe-c8e9-4317-8ef3-a0b212663eec".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/573a2d7b-fc66-453e-ad9e-c493badc4ea6/c03464a4-6251-4052-bf66-f49d0377c6e9".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/573a2d7b-fc66-453e-ad9e-c493badc4ea6/df389f7e-361e-4687-8190-7cb044e94fa4".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc.Wayland."InputMethod[$e]" =
        "/run/current-system/sw/share/applications/fcitx5-wayland-launcher.desktop";
      kwinrc."org.kde.kdecoration2".BorderSize = "None";
      kwinrc."org.kde.kdecoration2".BorderSizeAuto = false;

      kxkbrc.Layout.DisplayNames = "";
      kxkbrc.Layout.LayoutList = "us";
      kxkbrc.Layout.Use = true;
      kxkbrc.Layout.VariantList = "";
      plasma-localerc.Formats.LANG = "en_HK.UTF-8";
      plasmanotifyrc."Applications/chromium-browser".Seen = true;
      plasmanotifyrc."Applications/org.telegram.desktop".Seen = true;

      spectaclerc.ImageSave.lastImageSaveLocation = "file:///home/xpj/Pictures/Screenshots/Screenshot_20260121_171913.png";
      spectaclerc.ImageSave.translatedScreenshotsFolder = "Screenshots";
      spectaclerc.VideoSave.translatedScreencastsFolder = "Screencasts";
    };
  };

}
