# 跨窗口列出活跃的 Claude Code 会话。这里只管终端交互:取宽度、差分重绘、按键;
# 枚举进程、配 transcript、算标题和状态都在 claude-sessions.py 里($RENDER_PY 由 Nix 注入)。

term_cols() {
  local size
  # 走 /dev/tty 而不是 tput:render 的输出被 $() 捕获时 stdout 不是终端,tput 只会回落到 80
  # 重定向整段包在 {} 里:bash 从左到右处理重定向,`stty < /dev/tty 2>/dev/null`
  # 在没有控制终端的环境里会由 shell 自己把打不开 /dev/tty 的错误吐到 stderr
  size=$({ stty size < /dev/tty; } 2>/dev/null) && {
    printf '%s' "${size##* }"
    return
  }
  printf '100'
}

render() {
  CC_WIDTH=$(term_cols) python3 "$RENDER_PY"
}

# 逐行用 \033[K 覆盖 + 末尾 \033[J 清残留,而不是 \033[2J 全屏清空:
# 全清会让终端出现一帧空屏,在秒级刷新的 pane 里就是持续闪烁。
repaint() {
  printf '\033[H'
  printf '%s\n' "$1" | while IFS= read -r line; do
    printf '%s\033[K\n' "$line"
  done
  printf '\033[J'
}

watch_loop() {
  local interval=$1 prev='' cur key='' paused=0 stamp

  # 静止时一个字节都不往终端写 —— 这是能稳定框选复制的前提。
  # 只在内容真的变了才重绘,所以状态行给的是"最后变化",不是当前时间;
  # 同理 py 那边的等待时长刻意做成粗粒度,否则每分钟一变就等于每分钟闪一次。
  if [[ ! -t 0 ]]; then
    # stdin 不是终端时 read -t 会立刻返回,退化成纯 sleep 轮询,免得空转刷屏
    while true; do
      cur=$(render)
      [[ $cur != "$prev" ]] && { repaint "$cur"; prev=$cur; }
      sleep "$interval"
    done
  fi

  printf '\033[?25l' # 藏光标,不然它在重绘时跳
  # 退出前把光标放回来,不然 pane 里后续的 shell 没有光标
  trap 'printf "\033[?25h\n"; exit 0' INT TERM
  trap 'printf "\033[?25h\n"' EXIT

  while true; do
    if ((paused == 0)); then
      cur=$(render)
      if [[ $cur != "$prev" ]]; then
        stamp=$(date '+%T')
        prev=$cur
        repaint "$cur"
        printf '\n\033[2m最后变化 %s · 每 %ss 检查 · [空格] 暂停 [q] 退出\033[0m\033[K\n' \
          "$stamp" "$interval"
      fi
    fi

    # 用 read 的超时代替 sleep,这样按键能立刻响应。
    # IFS= 不能省:默认 IFS 含空格,读到空格键会被当分隔符剥掉,key 变成空串收不到暂停
    IFS= read -rsn1 -t "$interval" key || key=''
    case $key in
      q | Q) break ;;
      ' ' | p | P)
        paused=$((1 - paused))
        if ((paused == 1)); then
          printf '\033[2m>>> 已暂停,可以框选复制 · [空格] 继续 [q] 退出\033[0m\033[K\r'
        else
          prev='' # 强制下一轮重绘,把暂停提示盖掉
        fi
        ;;
    esac
  done
}

case ${1:-} in
  -w | --watch) watch_loop "${2:-1}" ;;
  -h | --help) printf '用法: cc-sessions [-w|--watch [间隔秒数,默认 1]]\n' ;;
  *) render ;;
esac
