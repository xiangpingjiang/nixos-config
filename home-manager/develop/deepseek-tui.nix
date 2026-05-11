{ pkgs, ... }:

let
  deepseek-tui = pkgs.stdenv.mkDerivation {
    pname = "deepseek-tui";
    version = "latest";

    src = pkgs.fetchurl {
      url = "https://github.com/Hmbown/DeepSeek-TUI/releases/latest/download/deepseek-tui-linux-x64";
      hash = "sha256-viyxKkFbpiSZMGD/ViIWv+4rXAibJG5QPXwjREmqmGc=";
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
