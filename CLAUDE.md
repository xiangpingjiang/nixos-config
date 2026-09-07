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

- `nixosConfigurations.nixos` — 入口 `configuration.nix`,imports 拆分为 `systemPackages.nix`、`services.nix`、`system-programs.nix`、`networking.nix`、`system-secrets.nix`。
- `homeConfigurations.xpj` — standalone home-manager,入口 `home-manager/home.nix`,imports `plasma.nix`(plasma-manager)、`rclone.nix`、`user-secrets.nix`、`apps.nix`(浏览器 + ssh)及 `develop/` 下的开发工具配置(claude-code、codex、vscode、shell 等)。故意做成 standalone 而非 NixOS module,只改用户配置时 rebuild 更快。

### 两套 profile,两套 gc(不配 HM 侧的 gc,系统 gc 基本白跑)

代数放在两个互不相干的位置,root 的 `nix-collect-garbage` **只扫前者**:

| 谁的代 | 位置 | 由谁回收 |
| --- | --- | --- |
| 系统(`nixos-rebuild`) | `/nix/var/nix/profiles/` | `configuration.nix` 的 `nix.gc` |
| standalone HM 的代 | `~/.local/state/nix/profiles/home-manager-*-link` | `home-manager/home.nix` 的 `nix.gc` |
| `nix profile`(HM 装 home.packages 时留下) | `~/.local/state/nix/profiles/profile-*-link` | 同上 |

发现时系统只剩 4 代,而用户侧积了 39 个 HM 代 + 90 个 profile 代(最老的追到 2026-08-08)。
这些全是 GC root,每个钉住一份完整闭包(那个 214MB 的 Claude Code 插件、dbx-cli 都在内),
系统 gc 每周跑一次基本回收不到东西。

HM 侧用 `nix.gc.automatic` 而不是 `services.home-manager.autoExpire`:后者只删
`home-manager-*-link`,管不到 `profile-*-link`,而后者的数量是前者的两倍多。
`nix.gc` 依赖 `home.nix` 里的 `nix.package`(那行看着冗余,删掉这段就没 nix 可用了)。
配合系统侧的 `nix.optimise.automatic`(硬链接去重)。

手动清一次:`nix-collect-garbage --delete-older-than 10d`(以 xpj 身份,不要 sudo——
sudo 跑的是 root 的 profile)。

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
| 终端 `claude` | `~/.nix-profile/bin/claude` | `llm-agents` input,可被 `claude-code.nix` 里的 `claudeCodeVersion` 覆盖 |
| VS Code 插件面板 | 插件目录里的 `resources/native-binary/claude`(约 214MB) | `vscode.nix` 里按版本号钉的 marketplace vsix |

插件的 `extension.js` 里 `resolveClaudeBinary()` **只在自己的 `resources/` 下找二进制,全程不查 PATH**,
找不到就直接抛 `unsupported_platform`,没有 fallback。所以升级一边对另一边毫无影响,
两处版本号都要改:`home-manager/develop/claude-code.nix` 的 `claudeCodeVersion`(CLI,官方 GCS 二进制)
和 `home-manager/develop/vscode.nix` 的 `claudeCodeVersion`(插件 vsix),各自的取 hash 命令写在两个文件的注释里。
CLI 那份是"上游追上就自动让路"的写法(`lib.versionAtLeast` 比一下 llm-agents 打出来的版本),
所以只是想跟着上游走的话不用碰它,`nix flake update llm-agents` 即可;
只有需要抢在 llm-agents 打包之前用新版时才改那个版本号。

想让两个入口共用一份二进制的话,唯一的改写口子是 `claudeCode.claudeProcessWrapper` 配置项,
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
一直是靠 `system-programs.nix` 里开着的 nix-ld 才跑得起来;换成 nixpkgs 脚手架后是正经 patchelf 过的。

### 密钥管理(agenix + sops-nix 双方案)

两套方案共用同一把 SSH 私钥 `/home/xpj/.ssh/id_ed25519` 解密:

- **agenix**:`.age` 文件放 `secrets/`,接收者公钥定义在 `secrets/secrets.nix`。系统级声明在根 `system-secrets.nix`,用户级声明在 `home-manager/user-secrets.nix`。编辑密钥:在 `secrets/` 目录下 `agenix -e <name>.age`。
- **sops-nix**:加密 YAML。系统级 `secrets/mihomo.enc.yaml`(部分加密,`key = ""` 表示解密整个文件给 mihomo 服务用);
  用户级 `secrets/cc-connect.enc.yaml`(整文件加密),声明在 `home-manager/user-secrets.nix`,由 flake.nix 里挂上的
  `sops-nix.homeManagerModules.sops` 提供。用户级密钥解出来在 `~/.config/sops-nix/secrets/<name>`
  (实际指向 `$XDG_RUNTIME_DIR` 下的 tmpfs,重启即失),写入者是 `sops-nix.service` 这个 user unit。
  加密规则在根目录 `.sops.yaml`:`.*\.enc\.yaml$` 那条是 mihomo 的部分加密,新文件要整文件加密就得
  在它**之前**加一条更具体的 `path_regex`(sops 取第一条匹配的规则)。

**新密钥一律走 sops-nix**,现存的 agenix 密钥(rclone 三把 + 系统级 restic_repository)不迁——
都在正常工作,迁移换不来任何功能。选 sops 的理由:一个 YAML 能装多个 key(按用途归档);
有 `sops.templates` 能渲染成 `KEY=VALUE` 喂 systemd 的 `EnvironmentFile`(cc-connect 靠这个),
agenix 没有;`sops <file>` 在仓库任何位置都能跑,而 `agenix -e` 必须在 `secrets/` 目录里
(它要读 `secrets/secrets.nix` 拿收件人)。

顺带区分两个同名的东西:`sops` 是 `home.packages` 里那个独立 CLI(getsops),只管你手动
加解密;sops-nix 是激活时解密的 home-manager/NixOS 模块,跑的是它自带的
`sops-install-secrets`,不调用 `sops` 二进制。两者只共用 `.sops.yaml` 的规则和那把 SSH 私钥。

### restic 备份(services.nix)

三个备份任务(cst / nutstore / infini)把同一个目录(就一个 21KB 的 KeePassXC 库)
备份到三个 WebDAV 网盘,**每 30 分钟一次**,`OnCalendar` 在周期内以 0/10/20 分钟错开
(remote 定义在 `home-manager/rclone.nix`)。**forget+prune 被刻意从备份任务中剥离**,
由单独的 `restic-prune` systemd timer 每周两次执行,仓库列表自动从
`services.restic.backups` 派生——增删备份仓库时无需同步改 prune 脚本。

#### 三条互相独立的教训(都是真出过事的)

**1. prune 跟着高频备份跑会死锁。** 最早的形态,已由上面的剥离解决。

**2. 剥离不清锁,而且失败是静默的。** 2026-07-25 / 07-28 各有一次 prune 被中断
(休眠或关机时 systemd 杀掉服务),留下的 **exclusive 锁**一直躺在仓库里,此后 08-10 到
09-03 共 9 次 prune 全部卡在 `repository is already locked`,每次白等 30 分钟。
备份任务毫发无损——它们用的是非独占锁,所以表面一切正常;而旧脚本的
`|| echo "!! prune 失败"` 让单元恒定 exit 0、永远显示 Finished,`systemctl --failed`
里永远看不到它。两者叠加,一个月零清理却无人察觉。现在的修复是循环里 prune 前先
`restic unlock`(只删同主机 PID 已死、或 >30min 未刷新的锁,不碰并发备份的活锁),
末尾 `exit $rc` 让单元真的变红。**`--retry-lock` 只是等,永远不会清陈旧锁**。

**3. 瓶颈是网盘后端,不是 restic,也不是数据量。** 2026-09-06 还这两个月的欠账:
13 小时 2 分,CPU 只烧了 89 秒——99.8% 在等 WebDAV。删掉 10668 个快照
(cst 5094 / infini 4847 / nutstore 727),清完后每个仓库只剩 30-50 KiB 有效数据,
其余全是元数据(每次备份都写一个 snapshot + 一个 index + 若干 tree blob)。
同样四千多个快照,三家的表现天差地别:

| 远端 | 结果 |
| --- | --- |
| infini | 10 分钟全程跑完,重建索引,干净收尾 |
| cst | 11.5 小时,repack 到 22/24 时 `unexpected EOF` 触发熔断退出;全程 429/500 不断 |
| nutstore | 删快照时 7 个撞 500,forget 判定失败,没进到 prune 阶段 |

**看到 `does not exist` 不要以为仓库坏了**:那是限流下的假 404,同一个对象换个时刻
就能读到(日志里能看到 `operation successful after 4 retries`)。**也不要因此重建仓库**。
prune 失败同样不必惊慌:forget 删掉的快照是落盘的,下次跑从十几个快照起步,只补做
没做完的 pack 清理,不会从头再来。restic 的设计是宁可 Fatal 也不带着残缺索引删数据。

为避免重演,备份周期从 10 分钟放宽到 30 分钟(每天 432 次往返 → 144 次),并加上
`--skip-if-unchanged`——内容和父快照一致就不生成新快照。**这一项要验证**:日志里每次都报
`Dirs: 2 changed`(`/home` 和 `/home/xpj` 的 mtime 被别的进程碰过),如果它破坏了判定、
日志里仍是 `snapshot saved` 而不是 `snapshot skipped`,就改用 `ExecCondition` 比对
kdbx 自身的哈希。

### 跨窗口查看活跃会话(cc-sessions,claude-code.nix)

`cc-sessions` 列出本机所有活跃的 Claude Code 会话,按 VS Code 窗口分组;`--watch` 就是 zellij
`cc` tab 里那个循环面板(layout 在 `home-manager/develop/zellij/dev.kdl`,pane 里写的是
`~/.nix-profile/bin/` 下的绝对路径,因为 zellij 的 command pane 不经过 shell)。
实现分两半:`develop/claude-sessions.sh` 只管取宽度/差分重绘/按键,进程枚举和 transcript
解析都在 `develop/claude-sessions.py`(纯标准库),渲染器的 store 路径由 Nix 注入 `RENDER_PY`
—— shell 那份是 `builtins.readFile` 进来的,自己没法插值。

判据是**进程**:插件里的每个会话都是所属窗口 extension host 的直接子进程,进程在就是活跃。
进程到窗口的映射只有一条路 —— extension host 继承的日志 fd 路径里带 `window<N>`;
父进程的 cwd 是 VS Code 主进程启动时的目录,所有窗口都一样,不能用。终端里的 `claude` 是
makeWrapper 的 bash 脚本,进程名是 `.claude-wrapped`,枚举时两个名字都要认。

标题(`aiTitle`)和状态都在 transcript 里,所以得先把 pid 映射到
`~/.claude/projects/<slug>/<sessionId>.jsonl`(slug 是 cwd 里的非字母数字全换成 `-`)。
resume 的会话命令行里直接带 sessionId;新会话没有,靠一条单向约束认领:transcript 一定由
某个 claude 进程创建,首条记录时间必然晚于该进程启动。同一 cwd 下按启动时间升序,每个进程
认领「首条时间晚于自己且尚未被认领」的最早那个,配不到就是"尚未对话"(panel 开着但一句话
没说)。已知错配:`/clear` 之后会留下两个都满足约束的文件,同 cwd 若还有个启动更晚的新会话,
它会认领到本该属于前者的第二个;罕见,没为它加复杂度。

状态只能看 assistant 行的 `message.stop_reason`(`tool_use`/`pause_turn`/`null` 算运行中),
**不能看这一行有没有 tool_use block**:一条 assistant 消息的每个 content block 是分行写的
(thinking 一行、text 一行、tool_use 一行),但同一条消息的所有行带同一个 stop_reason。
按 block 判的话,运行中的会话尾部常常正好停在 thinking 行,会误报成"等你回话",状态在
●/○ 之间反复跳,每跳一次还白触发一次重绘。

而且**尾部必须按行倒读,不能固定读尾部若干 KB**:transcript 里单条记录能到 100KB+
(整份 CLAUDE.md 的 attachment 行、大 tool_result),一条就把固定窗口吃光,一行都
`json.loads` 不出来,状态回落成 None——面板于是显示"尚未对话",哪怕这个会话正在跑。
现在 `tail_lines()` 从文件末尾按 64KB 块往前拼完整行(上限 4MB),配到 transcript 却
读不出状态时显示"? 状态未知",和真正配不到文件的"· 尚未对话"分开。

面板刷新是差分的:内容没变就一个字节都不往终端写 —— 这是能稳定框选复制的前提。全屏
`\033[2J` 清屏会插入一帧空屏,5s 一刷就是持续闪烁,所以改成逐行 `\033[K` 覆盖 + 末尾
`\033[J` 清残留。同理等待时长做成 5 分钟/1 小时的粗桶,精确到分钟就等于每分钟闪一次;
状态行显示的是"最后变化"而不是当前时间。`[空格]` 暂停(连检查一起停,方便复制),`[q]` 退出。
标题缓存在 `$XDG_RUNTIME_DIR/cc-sessions/`,不缓存就得每轮全文扫每个 jsonl 找 `ai-title` 行;
tmpfs,重启即失,自动重建。

跳回 VS Code 里的某个会话:`anthropic.claude-code` 扩展在运行时用 `registerUriHandler`
注册了深链(package.json 里查不到,`contributes.uriHandler` 不是合法字段,要在 `extension.js`
里 grep),支持

```
vscode://anthropic.claude-code/open?session=<sessionId>[&prompt=<text>]
```

`cc-sessions` 列出的 sessionId 直接能拼进去(和 `transcript_path` 的文件名一致)。扩展侧行为:
该 session 的 panel 已开着就 `reveal()` 激活那个 tab,没开就新建 panel 并 resume。
`x-scheme-handler/vscode` 已由 `code-url-handler.desktop` 注册,浏览器里点链接即可,
不需要额外 Nix 配置。已知局限:**URI 被派发给当前活跃的那个 VS Code 窗口**,不是 session
所属项目的窗口,开着多个窗口时就会开错地方。点击到 panel 出现约 1.5-2s,瓶颈是
`code --open-url` 每次都要起一个 Electron CLI(单独实测 1.3s);这台机器上没有
`vscode-ipc-*.sock`,没有更快的绕法。

顺带一个和 hooks 有关的事实:**hook 改动只对新开的会话生效**,当前会话加载的是旧的
`~/.claude/settings.json`。

### 飞书 bot 桥接(cc-connect,develop/cc-connect.nix)

把飞书消息接到本机 Claude Code 的桥(上游 <https://github.com/chenhg5/cc-connect>)。
事件走飞书 SDK 的 WebSocket 长连接,不需要公网 IP,也不用配回调 URL。

**为什么是 cc-connect 而不是 lark-channel-bridge**(后者一度部署过,已撤):cc-connect 的 TOML
配置里所有字符串值都支持 `${VAR}` 环境变量替换(`config/config.go` 的 `resolveEnvPlaceholders`,
反射遍历所有 string 字段),所以配置能整份由 Nix 生成成只读文件、凭证全部由 sops 注入环境变量——
真正的声明式。lark-channel-bridge 的 `config.json` 是运行时可变状态(`/config`、`/account`、
权限迁移都写回它),只能做到"启动前用 jq 改写密钥那一项"。另外 cc-connect 是单个 Go 二进制,
比 npm 包省掉手工维护 lockfile 的麻烦。

**构建用 `-tags no_web,goolm`**。web 管理界面(9820)要先 pnpm+vite 打出 `web/dist` 给
`//go:embed` 用,而它的功能是在浏览器里改 config.toml——这里配置是 store 里的只读文件,那个界面
一件事都干不成,不如不编。`goolm` 跟着上游 Makefile(matrix 的 olm 走纯 Go,免掉 libolm)。

**config.toml 是 store 的只读符号链接**(`home.file.".cc-connect/config.toml"`)。放在默认路径而不是
给服务传 `--config`,是为了让终端里直接敲 `cc-connect sessions` 看到同一份配置;数据目录
`~/.cc-connect` 由程序自己建(`cfg.DataDir` 默认就是它,和 config 位置无关)。代价:走管理 API
写配置的路径会失败——web admin(没开)、`/commands add`、`/alias add`。要加自定义命令就写进
`cc-connect.nix` 里的 `[[commands]]`。

**凭证经 sops → EnvironmentFile → `${VAR}`**。`sops.templates."cc-connect.env"` 渲染出
`CC_FEISHU_APP_ID=... / CC_FEISHU_APP_SECRET=...`(0400,tmpfs),systemd 的 `EnvironmentFile`
读它。用 template 而不是两个独立 secret 文件,是因为 EnvironmentFile 只吃 KEY=VALUE。
`ExecCondition` 会在凭证还是占位值时让 systemd 按"条件不满足"跳过启动——用 ExecCondition 而不是
ExecStartPre,因为后者失败会触发 `Restart=always` 空转刷日志。

**`allow_from` 默认是全放行,这里绝不能留空**。它控制谁能用这个 bot,而这个 bot 能在本机跑
claude(`core.AllowList`:空字符串或 `"*"` 一律放行,只在启动时打一条 warn)。当前租户是公司,
所以 `cc-connect.nix` 里 `allowFrom` 的初值是一个谁都不匹配的占位串,fail-closed。
`admin_from` 同理,它管 `/dir` `/shell` `/restart` 这些特权命令。

**不要用上游的 `cc-connect daemon install`**:它会自己往 `~/.config/systemd/user/` 写一份单元,
和声明式单元打架。启停一律 `systemctl --user {start,stop,restart} cc-connect`。

#### 首次引导(要扫码,没法声明式)

```bash
# 1. 扫码建飞书应用。config.toml 是只读的,所以给 setup 一份临时可写的副本
mkdir -p /tmp/cc-setup && cp ~/.cc-connect/config.toml /tmp/cc-setup/config.toml
chmod 600 /tmp/cc-setup/config.toml
cc-connect feishu new --config /tmp/cc-setup/config.toml    # 用飞书 App 扫码

# 2. 凭证进 sops(app_id/app_secret 在那份临时 config.toml 里)
grep -E 'app_id|app_secret' /tmp/cc-setup/config.toml
sops secrets/cc-connect.enc.yaml
rm -rf /tmp/cc-setup

home-manager switch --flake . -b backup -v
systemctl --user restart cc-connect && systemctl --user status cc-connect
```

`EnvironmentFile` 只在进程启动时读一次,所以**以后改凭证也必须 restart**,光 switch 不够。

扫码那一步的输出里如果有一行 `allow_from: ou_xxx` 且**没有**跟着"注册返回的 open_id 是机器人自身
的 ID"这条警告,直接拿它填即可,下面这段绕道就不用走了。

拿自己的 open_id 填 `allow_from`:飞书的 open_id 是**应用级**标识,别处(lark-cli)拿到的那个在这里
不通用;扫码流程返回的那个 open_id 往往是机器人自己的,也不能用(上游自己会警告)。而在
`allow_from` 放行之前给 bot 发消息只会收到"角色未授权",`/whoami` 也用不了。可靠做法是走 debug 日志,
全程 fail-closed:

```bash
# 把 cc-connect.nix 里 [log] level 临时改成 "debug",switch,然后在飞书私聊 bot 发一条消息
journalctl --user -u cc-connect | grep "unauthorized user"   # 日志里的 user=ou_xxx 就是你的 open_id
# 填进 cc-connect.nix 的 allowFrom,level 改回 "info",再 switch
```

bot 每一轮都是在本机 spawn `claude`,吃的是同一份 `~/.claude/settings.json`,所以桌面会弹
notify-send 通知、`cc-sessions` 里也会出现这些会话——不是 bug,是共用配置的必然结果。

`mode = "acceptEdits"`:文件编辑自动放行,其他工具仍在飞书里问一次。想全自动改
`"bypassPermissions"`,想更保守改 `"default"`。注意本仓库的 kubectl 守卫 hook 仍然生效
(它返回 `permissionDecision=ask`),生产集群的写操作会在飞书里弹确认。

### himalaya + QQ 邮箱(mail.nix)

配置文件**故意不走 home-manager 的 `programs.himalaya` 模块**,自己用 `pkgs.formats.toml`
生成 `xdg.configFile."himalaya/config.toml"`。原因是 schema 差了一个大版本:
hm 的模块(`modules/programs/himalaya.nix`)生成 v1 的 `backend.type = "imap"` /
`backend.auth.cmd` / `folder.aliases` / `message.send.backend.*`,而 nixpkgs 里已经是
himalaya 2.0.0,换成了 `imap.server` / `imap.sasl.plain.password.command` / `mailbox.alias.*`。
"绕过 accounts.email、只写 `programs.himalaya.settings`"这条路也是死的:模块里
`allConfig = globalConfig // { accounts = accountsConfig; }`,settings 里的 accounts
会被 accounts.email 派生出来的那份(没配就是空的)整体覆盖。

`imap.id.auto = true` 是 RFC 2971 的 ID 扩展开关,上游 `config.sample.toml` 点名
mail.qq.com 要求认证后立刻来一次 ID 交换。**但本机拿真实授权码实测过:去掉这项,
`mailbox list` / `envelope list` / `message read`(SELECT、SEARCH、FETCH)全部正常**
——所以它不是 QQ 邮箱能不能用的前提,别照抄"不开就 Unsafe Login"的说法。留着开是因为
代价只有认证后一条 ID 命令,而实测覆盖不到高频登录/大批量取信那类场景。这个开关在
v1.2.0 叫 `imap.extensions.id.send-after-auth`,v2 迁移时丢过一次,2.0.0 又恢复成
`imap.id.{auto,fields}`。

授权码(不是 QQ 密码)在 `secrets/qq-mail.enc.yaml`(sops 整文件加密),配置里只留
`password.command = "cat <sops 解出的路径>"`。**SASL username 没法进 secret**:v2 只给
密码留了 `.command` 变体,username 只能明文,所以 `mail.nix` 顶部的 `qqAddress` 是明文的。
改授权码要 `sops secrets/qq-mail.enc.yaml` 之后**重新 switch**——`.enc.yaml` 是 eval 期
复制进 store 的,光 `systemctl --user restart sops-nix` 拿不到新值。

v2 的两个行为变化:账户级的 `email`/`display-name` 配置项和 `[message.composer.*]` 整块
都被移除了(himalaya 变成低层工具,From 头写信时自己给,或交给 mml);裸跑 `himalaya`
是配置向导而不是列信件,列信件是 `himalaya envelope list`。子命令一律单数
(`mailbox` / `envelope` / `message` / `flag`)。

`mailbox.alias` 里 sent/drafts/trash 是手填的:v2 的 IMAP 只自动认 INBOX,其余
special-use 角色上游(io-imap)还没实现发现。改完拿 `himalaya mailbox list` 核对。

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
