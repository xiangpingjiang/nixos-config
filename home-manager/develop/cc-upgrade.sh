# cc-upgrade:把终端 CLI 和 VS Code 插件两份 Claude Code 升到各自的最新版,
# home-manager switch,然后重启所有 VS Code 窗口让插件换代。
# 两份二进制互不相干、版本各钉各的(见 CLAUDE.md「Claude Code 有两份互不相干的二进制」)。
#
#   cc-upgrade                 升级 + switch + 重启 VS Code
#   cc-upgrade --no-restart    只升级和 switch,不碰 VS Code
#   cc-upgrade --restart-only  不查版本,只重启 VS Code
#
# 仓库位置默认 ~/Projects/nixos-config,可用 NIXOS_CONFIG_DIR 覆盖。

repo=${NIXOS_CONFIG_DIR:-$HOME/Projects/nixos-config}
cli_nix=$repo/home-manager/develop/claude-code.nix
ext_nix=$repo/home-manager/develop/vscode.nix
gcs=https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases

restart=1
upgrade=1
case "${1:-}" in
  --no-restart) restart=0 ;;
  --restart-only) upgrade=0 ;;
  # 内部用:由 systemd-run 在 VS Code 进程树之外调起,参数是要重启的主进程 pid
  --restart-worker)
    shift
    sleep 3
    kill -TERM "$@" 2>/dev/null || true
    for _ in $(seq 60); do
      alive=0
      for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
      [ "$alive" = 0 ] && break
      sleep 0.5
    done
    if [ "$alive" = 1 ]; then echo "VS Code 30s 内没退干净,放弃重启" >&2; exit 1; fi
    exec ~/.nix-profile/bin/code ;;
  "") ;;
  *) echo "用法: cc-upgrade [--no-restart|--restart-only]" >&2; exit 2 ;;
esac

# VS Code 主进程:comm 是 code、且父进程不是 code 的那些
# (extension host、pylance 之类的 node 进程 comm 也是 code,但父进程是 code)。
vscode_main_pids() {
  ps -eo pid=,ppid=,comm= | while read -r pid ppid comm; do
    [ "$comm" = code ] || continue
    [ "$(ps -o comm= -p "$ppid" 2>/dev/null)" = code ] && continue
    echo "$pid"
  done
}

# 重启必须跑在 VS Code 进程树之外:这个脚本常常就是在 VS Code 的终端或 Claude 会话里
# 被调用的,主进程一退整棵树都会被带走。所以交给 systemd-run 起一个临时 user service。
# - SIGTERM 是 Electron 的优雅退出(走 app.quit),VS Code 照常做 hot exit,未保存的
#   文件和窗口布局都会恢复(window.restoreWindows / files.hotExit 都是默认值)。
# - 重新拉起用不带参数的 `code`,它按上次退出时的窗口列表全部恢复。
# - KillMode=process:`code` CLI 起完主进程就退出,service 随之结束;默认的
#   control-group 会把刚拉起的 VS Code 一起杀掉。
# - 环境来自 systemd --user,天然没有 VS Code 泄漏的 CHROME_DESKTOP。
restart_vscode() {
  local pids
  pids=$(vscode_main_pids | tr '\n' ' ')
  if [ -z "${pids// /}" ]; then
    echo "VS Code 没在运行,跳过重启"
    return 0
  fi
  echo "3 秒后重启 VS Code(主进程: $pids),窗口和未保存内容会自动恢复"
  # shellcheck disable=SC2086  # pids 要按空格拆成多个参数
  systemd-run --user --collect --quiet \
    --unit="cc-upgrade-restart-$$" \
    -p KillMode=process \
    "$(readlink -f "$0")" --restart-worker $pids
}

if [ "$upgrade" = 0 ]; then
  restart_vscode
  exit $?
fi

[ -f "$cli_nix" ] && [ -f "$ext_nix" ] || { echo "找不到 $cli_nix 或 $ext_nix" >&2; exit 1; }

cur_cli=$(sed -n 's/^ *claudeCodeVersion = "\(.*\)";/\1/p' "$cli_nix")
cur_ext=$(sed -n 's/^ *claudeCodeVersion = "\(.*\)";/\1/p' "$ext_nix")

new_cli=$(curl -fsS "$gcs/latest") || { echo "查 CLI 最新版本失败" >&2; exit 1; }
new_ext=$(curl -fsS -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
  -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=3.0-preview.1' \
  -d '{"filters":[{"criteria":[{"filterType":7,"value":"anthropic.claude-code"}],"pageSize":1}],"flags":950}' \
  | jq -r '.results[0].extensions[0].versions[0].version') || { echo "查插件最新版本失败" >&2; exit 1; }

echo "CLI:  $cur_cli -> $new_cli"
echo "插件: $cur_ext -> $new_ext"

# 只往前升:上游返回的版本不比当前新就不动(不为对齐把某一边往回压)
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

# 改版本号 + 换 hash。两个文件里都只有一行 `hash = "sha256-..."`,直接整行替换。
bump() {
  local file=$1 ver=$2 url=$3 name=$4 hash
  hash=$(nix store prefetch-file --json --name "$name" "$url" | jq -r .hash)
  case "$hash" in sha256-*) ;; *) echo "prefetch 失败: $url" >&2; return 1 ;; esac
  sed -i -E \
    -e "s|^( *claudeCodeVersion = )\"[^\"]*\";|\1\"$ver\";|" \
    -e "s|^( *hash = )\"sha256-[^\"]*\";|\1\"$hash\";|" \
    "$file"
}

changed_ext=0
changed=0
if newer "$cur_cli" "$new_cli"; then
  bump "$cli_nix" "$new_cli" "$gcs/$new_cli/linux-x64/claude" claude || exit 1
  changed=1
fi
if newer "$cur_ext" "$new_ext"; then
  bump "$ext_nix" "$new_ext" \
    "https://anthropic.gallery.vsassets.io/_apis/public/gallery/publisher/anthropic/extension/claude-code/$new_ext/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage?targetPlatform=linux-x64" \
    anthropic-claude-code.vsix || exit 1
  changed=1
  changed_ext=1
fi

if [ "$changed" = 0 ]; then
  echo "两边都已是最新,不用 switch"
  exit 0
fi

(cd "$repo" && home-manager switch --flake . -b backup -v) || { echo "home-manager switch 失败" >&2; exit 1; }

echo "终端 CLI: $(~/.nix-profile/bin/claude --version)"
echo "插件:     $(jq -r .version ~/.vscode/extensions/anthropic.claude-code/package.json)"

# 插件没换代就没必要重启 VS Code(CLI 只影响新开的终端会话)
if [ "$restart" = 1 ] && [ "$changed_ext" = 1 ]; then
  restart_vscode
fi
