# tun-watch — 记录 Mihomo tun 网卡的消失与恢复
#
# tun 在 mihomo 没重启的情况下静默消失过两次(2026-09-12 的 00:36 和 01:57),
# journal 里没有任何关闭记录,所以连"多久掉一次"都不知道。这个只观测、不修复
# ——和 netloc 的 --fix-tun 是显式开关同一个立场:先拿到数据再谈修。
#
# 只在状态**翻转**时记一条,不是每分钟刷。状态存在 XDG_RUNTIME_DIR(tmpfs,重启即失,
# 重启后第一次检查会重新建立基线)。

state_dir=${XDG_RUNTIME_DIR:-/tmp}/tun-watch
state_file=$state_dir/last
mkdir -p "$state_dir"

if ip link show Mihomo >/dev/null 2>&1; then
  now=up
else
  now=down
fi

last=""
[ -r "$state_file" ] && last=$(cat "$state_file")

if [ "$now" = "$last" ]; then
  exit 0
fi

printf '%s' "$now" >"$state_file"

# 首次运行(没有基线)只在异常态时出声,正常态静默建立基线
if [ -z "$last" ] && [ "$now" = up ]; then
  exit 0
fi

# 掉了的时候把周边状态一起记下来:默认路由走哪个接口、mihomo 进程还在不在。
# 之前两次事件都伴随 `[TUN] Auto detect interface ... failed`,所以默认接口是重点。
if [ "$now" = down ]; then
  route=$(ip route show default 2>/dev/null | head -1)
  pid=$(pgrep -x mihomo 2>/dev/null | head -1)
  logger -t tun-watch -p user.warning \
    "Mihomo 网卡消失(默认路由: ${route:-无};mihomo pid: ${pid:-不在})"
else
  logger -t tun-watch -p user.notice "Mihomo 网卡已恢复"
fi
