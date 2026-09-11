# netloc — mihomo 的地点一键切换
#
# 出境规则全部走 OUT selector,所以切地点只改这一个;claude 组必须单独切,因为它的
# 判据是账号安全而不是速度(中国大陆不在 Anthropic 支持地区)。详见 CLAUDE.md 的
# 「mihomo 的双地点切换(一个 OUT 开关)」。
#
# 设计上把「切」和「查」分开:任何一步失败都继续往下跑完、最后统一非 0 退出,
# 这样一次输出就能看清是哪一环坏的 —— 半路 exit 会让人少看到后面的线索。

API=${MIHOMO_API:-http://127.0.0.1:9097}
CURL_AUTH=()
if [ -n "${MIHOMO_SECRET:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer ${MIHOMO_SECRET}")
fi

if [ -t 1 ]; then
  C_R=$'\033[31m' C_G=$'\033[32m' C_Y=$'\033[33m' C_D=$'\033[2m' C_B=$'\033[1m' C_N=$'\033[0m'
else
  C_R='' C_G='' C_Y='' C_D='' C_B='' C_N=''
fi

rc=0
fix_tun=0
step() { printf '%s==>%s %s\n' "$C_B" "$C_N" "$*"; }
ok() { printf '    %s✓%s %s\n' "$C_G" "$C_N" "$*"; }
bad() {
  printf '    %s✗%s %s\n' "$C_R" "$C_N" "$*"
  rc=1
}
warn() { printf '    %s!%s %s\n' "$C_Y" "$C_N" "$*"; }
hint() { printf '      %s%s%s\n' "$C_D" "$*" "$C_N"; }

usage() {
  cat <<'EOF'
用法: netloc [cn|sg|status] [--quick] [--fix-tun]

  cn        切到回国配置:出境走机场,Claude 走日本节点
  sg        切到新加坡配置:全部直连(本地网络已无限制时都用这个)
  status    只看当前状态,不做改动(默认)

  --quick     跳过订阅节点健康检查(那一步要 1-2 分钟)
  --fix-tun   发现 tun 没开就顺手开(默认只报告,不动它)

环境变量: MIHOMO_API(默认 http://127.0.0.1:9097)、MIHOMO_SECRET
EOF
}

# ---- 与 mihomo 交互 ----------------------------------------------------------

# 组的当前选择;组不存在或 API 不通时返回空
group_now() {
  curl -fsS -m 5 "${CURL_AUTH[@]}" "$API/proxies/$1" 2>/dev/null | jq -r '.now // empty'
}

api_alive() {
  curl -fsS -m 5 "${CURL_AUTH[@]}" "$API/version" >/dev/null 2>&1
}

# 前置检查。分清三种失败:服务没起 / API 不通 / 配置里没有这两个组(= 没 rebuild)
preflight() {
  step "前置检查"

  if ! systemctl is-active --quiet mihomo 2>/dev/null; then
    bad "mihomo 服务未运行"
    hint "sudo systemctl start mihomo"
    return 1
  fi
  ok "mihomo 服务运行中"

  if ! api_alive; then
    bad "控制接口不可达:$API"
    hint "确认 external-controller 的地址/端口,或用 MIHOMO_API 指定"
    hint "设了 secret 的话用 MIHOMO_SECRET 传"
    return 1
  fi
  ok "控制接口可达 $API"

  local missing=()
  [ -z "$(group_now OUT)" ] && missing+=(OUT)
  [ -z "$(group_now claude)" ] && missing+=(claude)
  if [ ${#missing[@]} -gt 0 ]; then
    bad "配置里找不到代理组: ${missing[*]}"
    hint "这两个组是本脚本的前提。改完 secrets/mihomo.enc.yaml 之后需要重建系统:"
    hint "sudo nixos-rebuild switch --flake . -vv"
    hint "(.enc.yaml 在 eval 期复制进 store,只 restart mihomo 拿不到新内容)"
    return 1
  fi
  ok "代理组 OUT / claude 就位"
  return 0
}

# 切一个组并立刻读回核对。分清「PUT 失败」和「PUT 成功但没生效」
switch_group() {
  local group=$1 target=$2 code now
  code=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' \
    -X PUT -H 'Content-Type: application/json' "${CURL_AUTH[@]}" \
    -d "{\"name\":\"${target}\"}" "$API/proxies/${group}" 2>/dev/null || echo 000)

  case "$code" in
  204 | 200) ;;
  000)
    bad "$group -> $target 请求失败(控制接口无响应)"
    return 1
    ;;
  404)
    bad "$group -> $target 失败:组或成员不存在(HTTP 404)"
    hint "确认 $target 是 $group 的合法成员:curl -s $API/proxies/$group | jq .all"
    return 1
    ;;
  *)
    bad "$group -> $target 失败(HTTP $code)"
    return 1
    ;;
  esac

  now=$(group_now "$group")
  if [ "$now" != "$target" ]; then
    bad "$group 读回是 '$now',期望 '$target'"
    hint "PUT 返回成功但没生效。这通常意味着 $target 不是该组成员,或组类型不接受手动选择"
    return 1
  fi
  ok "$group = $target"
  return 0
}

# ---- 各步骤 ------------------------------------------------------------------

# tun 是唯一劫持系统 DNS 的环节:关掉它,被墙域名的解析会回落到本地 resolver
# (在新加坡就是 ISP 的 DNS sinkhole)。判据只看网卡 ——`/configs` 的 tun.enable
# 实测会在适配器已经起来并转发流量时仍然报 false。
tun_up() {
  ip -br addr 2>/dev/null | grep -qi '^Mihomo'
}

# PATCH /configs 只改运行时,不落配置文件;配置里本来就是 enable: true,
# 所以这是「把掉下去的拉回来」,不是改设定。
enable_tun() {
  local code i
  code=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' \
    -X PATCH -H 'Content-Type: application/json' "${CURL_AUTH[@]}" \
    -d '{"tun":{"enable":true}}' "$API/configs" 2>/dev/null || echo 000)
  if [ "$code" != "204" ] && [ "$code" != "200" ]; then
    bad "开启 tun 失败(HTTP $code)"
    hint "mihomo 需要 CAP_NET_ADMIN 才能建 tun 设备。services.nix 里 tunMode 应为 true"
    return 1
  fi
  # 网卡不是立刻出现,轮询等一会儿
  for i in $(seq 1 10); do
    if tun_up; then
      ok "已开启($((i * 500))ms 后网卡出现)"
      return 0
    fi
    sleep 0.5
  done
  bad "PATCH 成功但 Mihomo 网卡没出现"
  hint "看日志定位:journalctl -u mihomo -n 30 | grep -i tun"
  return 1
}

check_tun() {
  step "tun 状态"
  if tun_up; then
    ok "已启用(Mihomo 网卡存在)"
    return
  fi

  if [ "$fix_tun" -eq 1 ]; then
    warn "未启用,正在开启(--fix-tun)"
    enable_tun || return
    # 修好了也要说一句根因未知:tun 静默消失已经出现过两次(2026-09-12 的 00:36 和
    # 01:57,都没有关闭日志),自动拉起只是止血,别把它当成问题已解决。
    hint "注意:这只是把 tun 拉回来。它自己掉下去的原因仍未查清,"
    hint "反复发生就查 auto-detect-interface 在接口抖动时的行为:"
    hint "journalctl -u mihomo | grep -i 'auto detect interface'"
  else
    warn "未启用 —— 系统 DNS 没有被接管"
    hint "被墙站点会拿到本地 resolver 的结果(新加坡:ISP sinkhole;国内:GFW 污染)"
    hint "只有显式走代理端口的请求才正常。加 --fix-tun 让本脚本顺手开,或手动:"
    hint "curl -X PATCH -H 'Content-Type: application/json' -d '{\"tun\":{\"enable\":true}}' $API/configs"
  fi
}

# 订阅节点健康检查。仓库列表从 API 派生,增删机场不用改这里。
healthcheck() {
  step "订阅节点健康检查(可能要 1-2 分钟)"
  local providers
  providers=$(curl -fsS -m 10 "${CURL_AUTH[@]}" "$API/providers/proxies" 2>/dev/null |
    jq -r '.providers | to_entries[] | select(.value.vehicleType == "HTTP") | .key')

  if [ -z "$providers" ]; then
    warn "没有 HTTP 类型的订阅(全是内联节点?)"
    return
  fi

  local p code total alive
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # 进度行只在交互终端打印,跑完用 \r + 清到行尾擦掉(否则结果比它短时会留残字);
    # 重定向到文件时直接跳过,免得 \r 和转义序列进日志
    [ -t 1 ] && printf '    %s…%s %s ' "$C_D" "$C_N" "$p"
    code=$(curl -sS -m 300 -o /dev/null -w '%{http_code}' \
      "${CURL_AUTH[@]}" "$API/providers/proxies/${p}/healthcheck" 2>/dev/null || echo 000)
    [ -t 1 ] && printf '\r\033[K'
    if [ "$code" != "204" ] && [ "$code" != "200" ]; then
      bad "$p 健康检查失败(HTTP $code)"
      continue
    fi
    read -r total alive < <(
      curl -fsS -m 10 "${CURL_AUTH[@]}" "$API/providers/proxies" 2>/dev/null |
        jq -r --arg p "$p" '
          .providers[$p].proxies
          | [length, ([.[] | select(.alive and ((.history | length) > 0) and (.history[-1].delay > 0))] | length)]
          | @tsv'
    )
    if [ "${alive:-0}" -eq 0 ]; then
      bad "$p:$total 个节点全部不可用"
      hint "从当前网络到机场入口不通。换网络(热点/WiFi)再试,仍然全灭就是机场故障"
    elif [ "$alive" -lt $((total / 4)) ]; then
      warn "$p:$alive/$total 可用(偏少)"
      hint "多半是部分入口机从当前网络不可达,不是机场全挂"
      hint "在国内跑仍然是 ~39/172,说明广州入口(cl-199)不是路径问题而是真挂了,找机场"
    else
      ok "$p:$alive/$total 可用"
    fi
  done <<<"$providers"
}

# 连通性自检。两地各测一个有针对性的目标:
#   cn — google 被 GFW 封,必须经代理才通,能验证出境链路
#   sg — polymarket 被本地 DNS sinkhole,只有 DNS 被接管且拿到真实 IP 才通
selftest() {
  local loc=$1 url name code
  step "连通性自检"
  case "$loc" in
  cn) url=https://www.google.com/generate_204 name="google(验证出境代理)" ;;
  sg) url=https://polymarket.com/ name="polymarket(验证 DNS 未被 sinkhole)" ;;
  esac

  code=$(curl -sS -m 20 --noproxy '*' -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
  case "$code" in
  200 | 204)
    ok "$name -> HTTP $code"
    ;;
  000)
    bad "$name -> 无响应"
    if [ "$loc" = sg ]; then
      hint "tun 没开,或 DNS 仍解析到 sinkhole。核对一下:"
      hint "getent ahostsv4 polymarket.com   # 不该是 13.248.x / 76.223.x"
    else
      hint "出境链路不通。上面健康检查里可用节点数是 0 的话先解决那个;"
      hint "都可用却仍失败,看实时日志定位:journalctl -u mihomo -f"
    fi
    ;;
  *)
    warn "$name -> HTTP $code(能连通,但状态码意外)"
    ;;
  esac
}

# Claude 的出口要单独确认:store-selected 会在启动时先恢复上次存的选择,健康检查
# 才纠正它,收敛要几十秒到两三分钟。在国内那段窗口里如果停在 DIRECT,请求就带着
# 中国 IP 发出去了 —— 中国大陆不在 Anthropic 支持地区。
claude_guard() {
  local loc=$1 now
  step "Claude 出口确认"
  now=$(group_now claude)
  case "$loc" in
  cn)
    if [ "$now" = DIRECT ]; then
      bad "claude 组停在 DIRECT —— 在国内这是中国 IP"
      hint "中国大陆不在 Anthropic 支持地区。开会话前必须切走:"
      hint "netloc cn        # 或手动 PUT claude = MESL_Claude"
    else
      ok "claude = $now(非直连)"
      hint "Claude 会话开始前再核对一次:netloc status"
    fi
    ;;
  sg)
    if [ "$now" = DIRECT ]; then
      ok "claude = DIRECT(住宅/移动 IP,风控画像最干净)"
    else
      warn "claude = $now —— 走的是机场共享出口"
      hint "机场节点是 proxy+hosting 双标记的数据中心 IP,且几百人共享;"
      hint "新加坡在 Anthropic 支持地区内,直连更干净:netloc sg"
    fi
    ;;
  esac
}

# 只报两个 selector 的选择;tun 由 check_tun 单独报(它在未启用时还要给排查提示)
show_status() {
  local out claude
  out=$(group_now OUT)
  claude=$(group_now claude)

  step "当前状态"
  printf '      OUT    = %s\n' "${out:-?}"
  printf '      claude = %s\n' "${claude:-?}"

  case "$out" in
  DIRECT) hint "地点:新加坡 / 本地网络无限制" ;;
  MESL) hint "地点:国内(出境经机场)" ;;
  esac
}

# ---- 主流程 ------------------------------------------------------------------

quick=0
action=status
for arg in "$@"; do
  case "$arg" in
  cn | sg | status) action=$arg ;;
  --quick) quick=1 ;;
  --fix-tun) fix_tun=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf '未知参数: %s\n\n' "$arg" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [ "$action" = status ]; then
  preflight || exit 1
  show_status
  check_tun
  # 从 OUT 反推地点,把切换时那套判据照样用上。最该被抓住的状态就是
  # 「OUT=MESL 而 claude 还停在 DIRECT」——国内重启后、fallback 收敛前的窗口期,
  # 光打印两个值等于把判断丢回给人,而这个脚本存在的意义就是替人做这个判断。
  case "$(group_now OUT)" in
  MESL) claude_guard cn ;;
  DIRECT) claude_guard sg ;;
  esac
  exit "$rc"
fi

preflight || exit 1

case "$action" in
cn)
  step "切到回国配置"
  switch_group OUT MESL || true
  switch_group claude MESL_Claude || true
  check_tun
  [ "$quick" -eq 0 ] && healthcheck
  selftest cn
  claude_guard cn
  ;;
sg)
  step "切到新加坡配置"
  switch_group OUT DIRECT || true
  switch_group claude DIRECT || true
  check_tun
  selftest sg
  claude_guard sg
  ;;
esac

echo
if [ "$rc" -eq 0 ]; then
  printf '%s切换完成%s。选择已由 profile.store-selected 记住,重启不用再切。\n' "$C_G" "$C_N"
else
  printf '%s切换未完全成功%s —— 上面每个 ✗ 下面跟着排查步骤。\n' "$C_R" "$C_N"
  printf '当前实际状态:\n'
  show_status
fi
exit "$rc"
