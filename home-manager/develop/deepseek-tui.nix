{ pkgs, ... }:

let
  version = "0.8.38";
  deepseek-tui = pkgs.stdenv.mkDerivation {
    pname = "deepseek-tui";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/Hmbown/DeepSeek-TUI/releases/download/v${version}/deepseek-tui-linux-x64";
      hash = "sha256-D2Jq3n7OiOKzN/+5pXHErukyZW9BVu04Q/5dEVOh6S4="; # pkgs.lib.fakeHash 不带引号
    };

    dontUnpack = true;

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc
      pkgs.dbus
    ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/deepseek-tui
      chmod +x $out/bin/deepseek-tui
    '';

    meta = {
      description = "DeepSeek TUI - terminal interface for DeepSeek AI";
      homepage = "https://github.com/Hmbown/DeepSeek-TUI";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  home.packages = [ deepseek-tui ];
}
