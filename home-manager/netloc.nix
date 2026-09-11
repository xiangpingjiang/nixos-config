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
in
{
  home.packages = [ netloc ];
}
