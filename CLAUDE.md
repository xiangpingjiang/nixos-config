# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 常用命令

```bash
# 只更新系统配置(configuration.nix 及其 imports,不包含 home-manager)
sudo nixos-rebuild  switch  --flake  -vv

# 只更新 home-manager(home-manager/ 下的改动用这个)
home-manager switch --flake . -b backup -v

# 两边都改了就两条都要跑

# 更新 flake 输入
nix flake update

# 校验配置能否求值/构建
nix flake check

# 格式化 Nix 文件
nixfmt <file.nix>
```

## 架构

单机(hostname `nixos`、用户 `xpj`、x86_64-linux)的 NixOS flake 配置,系统配置和 home-manager **是两个独立的 flake 输出**,分别 rebuild:

- `nixosConfigurations.nixos` — 入口 `configuration.nix`,imports 拆分为 `systemPackages.nix`、`services.nix`、`programs.nix`、`networking.nix`、`secrets.nix`(系统级)。
- `homeConfigurations.xpj` — standalone home-manager,入口 `home-manager/home.nix`,imports `plasma.nix`(plasma-manager)、`rclone.nix`、`secrets.nix`、`programs.nix` 及 `develop/` 下的开发工具配置(claude-code、codex、vscode 等)。故意做成 standalone 而非 NixOS module,只改用户配置时 rebuild 更快。

### flake 输入的缓存约束(重要)

`flake.nix` 中 `llm-agents` 和 `dbx` **故意不 follows nixpkgs**:一旦 override,derivation hash 变化会导致上游 binary cache(cache.numtide.com 等)全部未命中,需要本地编译(dbx 是 Rust+Tauri,代价很大)。修改 inputs 时不要"顺手"给它们加 `inputs.nixpkgs.follows`。

同样的道理适用于**自打包的东西吃哪棵 nixpkgs**。`dbx-cli`(上游 flake 只输出 desktop,CLI 得自己打)
一度用本仓库的 `pkgs.rustPlatform` 构建,结果是:dbx 的 rev 钉死、版本号一个字没改,但只要
`nix flake update` 动了 nixpkgs,rustc/stdenv 一变 derivation hash 就变,上游又没有 cache,
每次例行更新都要本地重编十几二十分钟。现在改成 `import inputs.dbx.inputs.nixpkgs`(见
`home-manager/home.nix`),不变量是:只有 dbx 这个 input 及其子输入树变化才重编。
注意 dbx-cli 段落里 `cmake`/`pkg-config`/`fontconfig`/`freetype`/`openssl` 也必须取自 `dbxPkgs`
——漏一个,外层 nixpkgs 就又进闭包,整个安排作废。验证方法(两边必须打印同一个 drv):

```bash
EXPR='ps: (builtins.head (builtins.filter (p: (p.pname or "") == "dbx-cli") ps)).drvPath'
nix eval --raw .#homeConfigurations.xpj.config.home.packages --apply "$EXPR"
nix eval --raw --override-input nixpkgs github:NixOS/nixpkgs/<任意旧 rev> \
  .#homeConfigurations.xpj.config.home.packages --apply "$EXPR"
```

代价是 CLI 链到的 glibc/openssl 跟着 dbx 那棵 nixpkgs 走(比外层滞后),安全更新随 dbx 升级到来;
desktop 本来就是这个状况。

### Claude Code 有两份互不相干的二进制

终端里的 `claude` 和 VS Code 插件里的 Claude Code **不是同一个程序**,版本可以长期不一致:

| 入口 | 实际执行的二进制 | 来源 |
| --- | --- | --- |
| 终端 `claude` | `~/.nix-profile/bin/claude` | `llm-agents` input |
| VS Code 插件面板 | 插件目录里的 `resources/native-binary/claude`(约 214MB) | `vscode.nix` 里按版本号钉的 marketplace vsix |

插件的 `extension.js` 里 `resolveClaudeBinary()` **只在自己的 `resources/` 下找二进制,全程不查 PATH**,
找不到就直接抛 `unsupported_platform`,没有 fallback。所以升级 `llm-agents` 对插件里的会话毫无影响,
反之亦然——两个 input 都要更新。唯一的改写口子是 `claudeCode.claudeProcessWrapper` 配置项,
但它是 wrapper 语义(插件会 `wrapper <自带二进制路径> <真实参数...>`),不是替换,且跨版本协议不保证兼容,
没有实测过,别指望它统一版本。

判断当前跑的是哪个:`readlink /proc/<pid>/exe`。

### nix4vscode 的更新窗口(版本不对先加 --refresh)

插件版本不是查询时实时抓的,是 nix4vscode 仓库里预生成的 `data/vscode/data_*.json`。
CI 每天 00:00 UTC 启动,跑 2h10m-2h30m,固定在 **02:10-02:30 UTC(10:10-10:30 CST)** 提交一次。
所以 CST 上午 10:30 之后 `nix flake update` 才拿得到当天的数据。上游本身并不慢——
实测 2.1.246 在 08-25 22:53 UTC 发布,08-26 02:17 UTC 就进了数据,延迟只有 3.5 小时。

真正会踩的坑是拉到「看起来是最新」的 rev 却没有新版本,两个原因叠加:

- **openvsx 流水线收工更早**(约 01:20 UTC)。01:20 到 02:17 之间 master HEAD 是
  `chore: update data/openvsx` 那个 commit,`data/vscode` 还是前一天的。
- **nix 的 `tarball-ttl` 默认 3600s**,会缓存 GitHub 的 branch head,更新时可能拿到一小时前的 rev。

所以发现 nix4vscode 版本不对,先怀疑缓存而不是上游:

```bash
nix flake update nix4vscode --refresh
```

查上游数据里到底有哪些版本(不用先 update,直接看 master HEAD):

```bash
curl -s "https://raw.githubusercontent.com/nix-community/nix4vscode/master/data/vscode/data_98.json" \
  | python3 -c "import json,sys; print(list(dict.fromkeys(x['v'] for x in json.load(sys.stdin)['anthropic.claude-code']))[:6])"
```

分片号(`data_98.json`)会随上游数据量漂,查不到就 `grep -rl anthropic.claude-code` 重新定位。
另外别费劲换插件源:实测同一时刻 nix4vscode 2.1.243 > nixpkgs 2.1.238 > nix-vscode-extensions 2.1.237,
nix4vscode 已经是最新的自动源。

**但 `anthropic.claude-code` 已于 2026-09-02 脱离 nix4vscode**,本节只对其余扩展适用。
起因是 Fable 5.1 需要 Claude Code 2.1.255+,而 marketplace 上已是 2.1.258 时,nix4vscode
数据里最高只有 2.1.252——所有自动源都要等各自的流水线,最快的 nix4vscode 也有一天的窗口。
现在它在 `home-manager/develop/vscode.nix` 里按版本号直接钉 marketplace 的 vsix:复用 nixpkgs
的 `vscode-extensions.anthropic.claude-code` 脚手架(autoPatchelfHook 负责 patch 那个 214MB 的
native binary),`overrideAttrs` 只换 `src` 和 `version`,drv 里没有编译,重建就是解压 + patchelf。
升级手续变成手动:改 `claudeCodeVersion`,再跑一行 `nix store prefetch-file` 拿新 hash——
两条命令(查 marketplace 最新版本、算 hash)都写在该文件的注释里。

顺带一个事实:nix4vscode 打出来的插件二进制**没有 patchelf**(interpreter 是 `/lib64/ld-linux-x86-64.so.2`),
一直是靠 `programs.nix` 里开着的 nix-ld 才跑得起来;换成 nixpkgs 脚手架后是正经 patchelf 过的。

### 密钥管理(agenix + sops-nix 双方案)

两套方案共用同一把 SSH 私钥 `/home/xpj/.ssh/id_ed25519` 解密:

- **agenix**:`.age` 文件放 `secrets/`,接收者公钥定义在 `secrets/secrets.nix`。系统级声明在根 `secrets.nix`,用户级声明在 `home-manager/secrets.nix`。编辑密钥:在 `secrets/` 目录下 `agenix -e <name>.age`。
- **sops-nix**:用于部分加密的 YAML(目前只有 `secrets/mihomo.enc.yaml`,`key = ""` 表示解密整个文件给 mihomo 服务用)。

### restic 备份(services.nix)

三个备份任务(cst / nutstore / infini)每 10 分钟一次,`OnCalendar` 分别以 0/3/6 分钟错开,通过 rclone WebDAV 后端(remote 定义在 `home-manager/rclone.nix`)。**forget+prune 被刻意从备份任务中剥离**,由单独的 `restic-prune` systemd timer 每周两次执行,仓库列表自动从 `services.restic.backups` 派生——增删备份仓库时无需同步改 prune 脚本。历史教训:prune 跟着高频备份跑曾造成长达数月的仓库死锁。

### Claude Code Agent Monitor(CCAM,claude-code.nix)

本地会话监控面板 <http://localhost:4820>,由 `ccam-dashboard` systemd user service 托管(声明在 `home-manager/develop/claude-code.nix`),记录每个 Claude Code 会话的事件、工具调用和 token 成本。

**hooks 只能声明式配置**:上游装 hooks 的两个入口(`npm run install-hooks`、以及 server 启动时的自动安装)都是写 `~/.claude/settings.json`,而这个文件是 home-manager 生成的 /nix/store 只读符号链接,两条路都会失败(server 那次包在 try/catch 里静默失败,不影响服务启动)。8 个事件的 hook 条目写在 `claude-code.nix` 的 `settings.hooks` 里,和原有的 notify-send 通知 / kubectl 守卫条目并存(同一事件下是数组,CCAM 的 `matcher = "*"` 与守卫的 `matcher = "Bash"` 可以共存)。

源码有意放在 store 之外的 `~/.local/share/ccam`,不用 `fetchFromGitHub` 钉版本:上游几天一个版本,钉进 store 每次升级都要重算根目录和 client 两份 `npmDepsHash`。代价是**升级不走 `home-manager switch`**:

```bash
cd ~/.local/share/ccam && git pull --rebase && npm install && npm run build
systemctl --user restart ccam-dashboard
```

用 `--rebase` 是因为 clone 里有**本地补丁 commit**(目前一个,session 跳回 VS Code 的按钮,见下),普通 `git pull` 会生成 merge commit 把它埋掉。重建后跑 `npm run test:client` 预期**恰好 3 个失败**(Analytics / Workflows / Claude Config 三个快照,上游自带,与本机无关)——变成 4 个就说明升级引入了新问题,别当成补丁的预期失败忽略掉。

从面板跳回 VS Code 里的会话:`anthropic.claude-code` 扩展在运行时用 `registerUriHandler` 注册了深链(package.json 里查不到,`contributes.uriHandler` 不是合法字段,要在 `extension.js` 里 grep),支持

```
vscode://anthropic.claude-code/open?session=<sessionId>[&prompt=<text>]
```

CCAM 的 session id 就是 Claude Code 的 sessionId(和 `transcript_path` 的文件名一致),所以拿面板上的 id 直接拼 URI 即可。扩展侧行为:该 session 的 panel 已开着就 `reveal()` 激活那个 tab,没开就新建 panel 并 resume。`x-scheme-handler/vscode` 已由 `code-url-handler.desktop` 注册,浏览器里点链接即可,不需要额外 Nix 配置。已知局限:**URI 被派发给当前活跃的那个 VS Code 窗口**,不是 session 所属项目的窗口(实测:激活 ccam 窗口后发一个 cwd 属于 pi-agent 的 session,panel 开在了 ccam 窗口),开着多个窗口时就会开错地方。曾经用一个 `ccam-jump://` 中转 handler(先按 cwd 用 kdotool 前置正确窗口再转发)绕开这点,已于 2026-08-29 连同其 desktop entry 一起删除,面板按钮现在直接发 `vscode://`。

点击到 panel 出现约 1.5-2s,瓶颈是 `code --open-url` 每次都要起一个 Electron CLI(单独实测 1.3s);这台机器上没有 `vscode-ipc-*.sock`,没有更快的绕法。这条 URI 已经做成前端按钮(clone 里的本地补丁 commit):新增 `client/src/components/OpenInVSCode.tsx`,挂在 Kanban 卡片、Sessions 列表行、会话详情页三处。Codex 会话(没有这个 URI handler)、远程采集的会话(本机不存在,resume 只会开出空 panel)、pre-identity 进程卡片(还没有真实 id)一律不渲染按钮。改动只有 3 个源文件各两行 + 1 个新文件 + Session detail 快照,rebase 面已尽量压小。

其他注意点:hook 改动只对新开的会话生效(当前会话加载的是旧 settings.json);SQLite 后端走 Node 24 内置的 `node:sqlite`(`better-sqlite3` 只是 optionalDependency,新版 npm 默认不跑依赖的 install script,它的 native 二进制没编译,正好绕开 NixOS 上 prebuild-install 二进制跑不起来的问题);服务只监听 `127.0.0.1:4820`,面板不带认证却能读全部会话记录,别改成 `0.0.0.0`。

### 面板跑到内置屏 / 主屏漂移(plasma.nix)

`plasma.nix` 里面板的 `screen = 0` 钉的是 Plasma 的 0 号屏,即 KWin 中 priority 1 的输出(主屏)。KWin 按"输出组合 + 盖子开合"在 `~/.config/kwinoutputconfig.json` 里分别存优先级,换口/换显示器、飞书屏幕共享的虚拟输出出现/消失、合盖开盖、唤醒时的输出上线竞态,都可能把优先级写乱(出现并列 priority 1 甚至负数),面板随之跳到内置屏。这不是 Nix 配置问题,修复只需一条命令(立即生效并写回)。注意**外接屏的连接器名本身也会漂**(同一台显示器重启后可能从 DP-2 变成 DP-1),所以命令里用 uuid 而不是名字——uuid 跨改名稳定:

```bash
# 当前这台外接屏的 uuid;换显示器后用 kscreen-doctor -o 重新查
kscreen-doctor output.73ad35c6-a068-4f37-a2c0-99a1fedd7060.priority.1 output.eDP-1.priority.2
```

诊断用 `kscreen-doctor -o` 看各输出的 priority 是否唯一。

## 约定

- 注释使用中文,新增配置保持这一风格。
- `mihomo_test_config.yaml`(根目录)是 mihomo 的明文测试配置,真实配置在 `secrets/mihomo.enc.yaml`(sops 加密)。
