{ pkgs, ... }:
# netloc —— mihomo 的地点一键切换(常驻新加坡,间歇回国)。
#
# 为什么要有这个脚本:切换本身只是两条 PUT,但「切完到底成不成」要看四处
# ——两个组的读回值、tun 网卡、节点存活、以及 claude 组有没有停在危险的那一侧。
# 手敲的时候最容易漏掉后两项,而漏掉的代价不对称:在国内漏掉 claude 那步,
# 请求就带着中国 IP 发出去了(中国大陆不在 Anthropic 支持地区)。
#
# 脚本刻意不在中途 exit:每步失败都记下来继续跑完,最后统一非 0 退出,
# 一次输出看清所有线索。排查提示直接跟在每个失败下面。
let
  netloc = pkgs.writeShellApplication {
    name = "netloc";
    runtimeInputs = with pkgs; [
      curl
      jq
      gnugrep
      iproute2 # ip -br addr,判断 tun 网卡是否存在
      systemd # systemctl is-active
      coreutils
    ];
    # 不要 errexit:这个脚本靠「跑完全部检查再汇总」给出可读的失败日志,
    # 半路退出会让人少看到后面的线索。
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./netloc.sh;
  };

  # tun 掉线的观测。根因未明(两次都没有关闭日志),先把"什么时候掉的、掉了多久"
  # 记下来再谈修 —— 和 netloc 的 --fix-tun 是显式开关同一个立场。只在状态翻转时
  # 写一条 journal,不是每分钟刷屏。
  tunWatch = pkgs.writeShellApplication {
    name = "tun-watch";
    runtimeInputs = with pkgs; [
      iproute2
      procps # pgrep
      util-linux # logger
      coreutils
    ];
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./tun-watch.sh;
  };
in
{
  home.packages = [
    netloc
    tunWatch
  ];

  systemd.user.services.tun-watch = {
    Unit.Description = "记录 Mihomo tun 网卡的消失与恢复";
    Service = {
      Type = "oneshot";
      ExecStart = "${tunWatch}/bin/tun-watch";
    };
  };

  systemd.user.timers.tun-watch = {
    Unit.Description = "每分钟检查一次 Mihomo tun 网卡";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
