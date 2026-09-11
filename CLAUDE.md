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

#### 说「升级 Claude Code 到最新」时照这个做

版本号不要问用户,也不要凭记忆填,两条命令各查各的(实测 2026-09-12 两边都返回 `2.1.268`):

```bash
# CLI(官方 GCS 分发,llm-agents 打包的上游就是它)
curl -s "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest"
# VS Code 插件(marketplace,和 CLI 的版本号通常同步但不保证)
curl -s -X POST 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
  -H 'Content-Type: application/json' -H 'Accept: application/json;api-version=3.0-preview.1' \
  -d '{"filters":[{"criteria":[{"filterType":7,"value":"anthropic.claude-code"}],"pageSize":1}],"flags":950}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['extensions'][0]['versions'][0]['version'])"
```

拿到版本号之后:改两个 `claudeCodeVersion`,各跑一次 `nix store prefetch-file`(命令写在两个文件的注释里)
换 hash,然后 `home-manager switch --flake . -b backup -v`(这两处都在 home-manager 侧,不用 nixos-rebuild)。
两个查询返回的版本不一致就各钉各的,不要为了对齐把某一边往回压。

想知道这版改了什么(用户问起、或升级后行为有变时再查,不是每次都要):

- <https://code.claude.com/docs/en/changelog>
- <https://github.com/anthropics/claude-code/releases>

插件那份**必须手动钉**(已脱离 nix4vscode,见下一节)。CLI 那份严格说可以只 `nix flake update llm-agents`
等上游追上,但"升级到最新"通常意味着现在就要用上,所以默认直接钉版本号 —— `lib.versionAtLeast`
会在 llm-agents 追上之后自动让路,钉了不用记着撤。

### 官方 API 连不上时的兜底入口(claude-ds,claude-code.nix)

`claude-ds` 把 Claude Code 接到 DeepSeek 的 Anthropic 兼容端点
(`https://api.deepseek.com/anthropic`),官方 API 不通时用它,平时照常用 `claude`。
**端点在进程启动那一刻定死**:开着的会话切不过去,`/model` 也只能在当前端点的别名里选,
要换就重开一个会话。降级顺序(先查 mihomo 的 claude 选择器、再查节点存活,最后才动模型)
写在 README 的 “Falling back to a Chinese model” 一节。
选 DeepSeek 而不是 claude-code-router 这类协议转换层:DeepSeek、智谱、Moonshot 都直接
提供原生 Anthropic 端点,router 只在 provider 没有原生端点、或要按难度在多家之间路由时
才值得引入 —— 多一跳还多一处 tool_use 保真风险。加别的 provider 就再调一次
`mkFallbackClaude`(一个 attrset 的事)。

**切换必须走 `claude --settings`,不能靠 export。** settings 文件的 `env` 块会**替换**
从 shell 继承的同名变量(文档原文,实测也是),所以 `ANTHROPIC_BASE_URL=... claude` 在本机
会被 `~/.claude/settings.json` 压掉。`--settings` 这一层优先级仅次于 managed settings、
高于用户级,而且是叠加不是替换 —— hooks、permissions、全局 CLAUDE.md 全部照常生效,
只有 JSON 里列出的键被换掉。为此把 settings.env 里那行
`ANTHROPIC_BASE_URL = "https://api.anthropic.com"` 删了:它填的是默认值,留着唯一的效果
就是堵死手动 export 这条救急路径。

**密钥走 shell,不进 JSON。** store 全局可读,所以 wrapper 里 `export ANTHROPIC_AUTH_TOKEN`
(值来自 sops 的 `secrets/llm-keys.enc.yaml`),而那份 settings **不写这个键**——
只有没被列出的变量才轮得到 shell 的值。顺带一个安全性质:`ANTHROPIC_AUTH_TOKEN` 一旦设了
就压过已登录的 OAuth(实测请求头是 `Bearer <你的 key>`),不会把公司账号的 token 发给第三方。
反过来说,**拿第三方端点做实验时务必先确认这一点**,否则一次 `-p hi` 就把 OAuth token
写进了对方的日志。

**四个模型别名都要映射,包括 DeepSeek 官方没写的 `FABLE`。** 全局 CLAUDE.md 让主模型按
haiku/sonnet/fable 委派子代理,漏掉 fable 那条路会当场撞未知模型。要清楚兜底状态下这套
分工只剩形式:四个别名指向同一个模型,委派省不下钱,唯一还成立的作用是隔离上下文。

**`[1m]` 只在本地解析。** 模型名不在 Claude Code 的 catalog 里时它按 200k 假设窗口、据此
提前 auto-compact;后缀 `[1m]` 声明真实窗口,实测**发出去的 `model` 字段已经把后缀剥掉**,
不会污染 provider 那边的模型名。`CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432` 再把 compact
阈值抬到窗口的 3/4(这三项都抄自 DeepSeek 官方集成文档)。

**第三方端点下会静默少掉一批功能**,别当成 bug:Remote Control 和 server-managed settings
由 Claude Code 自己关掉(只要 `ANTHROPIC_BASE_URL` 不是 `api.anthropic.com`);Advisor
要求网关原样转发到 Anthropic API,DeepSeek 上会打一行 `no advisor rank` 然后自动禁用
(不用去改 `advisorModel`);MCP 的 tool search 默认关(`ENABLE_TOOL_SEARCH=true` 能开回来);
claude.ai connectors、Artifacts、`/schedule`、Channels、web/mobile/Slack 那些一律不可用。
hooks、skills、subagents、checkpoints 这些纯本地的东西不受影响。

DeepSeek 那边的兼容边界(官方兼容表):`cache_control` **全部忽略**——它有自己的自动前缀
缓存(命中价 ¥0.02-0.04/M,低一到两个数量级),所以不是没缓存,是断点你管不了;
`thinking` 支持但 `budget_tokens` 忽略;`document`(PDF 输入)和 `redacted_thinking` 不支持;
`anthropic-version` 忽略;未知模型名一律被服务端映射到 `deepseek-flash`,所以配错不会 400。

改 key:`sops secrets/llm-keys.enc.yaml` 之后**重新 switch**(`.enc.yaml` 是 eval 期复制进
store 的)。还是占位值 `REPLACE_ME` 时 wrapper 直接退出并打印引导,不会带着空 token 去撞 401。

**VS Code 插件那个入口 `--settings` 管不到**(它自己起进程,只认 `claudeCode.environmentVariables`
和 `~/.claude/settings.json`)。想让插件也走兜底,只能改用户级 settings 的 `env`+`apiKeyHelper`,
那是个全局开关、翻过去官方路径就关了 —— 目前没做。

验证整条链路(不需要真 key,也不会把 OAuth token 发出去):起一个打印请求头的本地 HTTP
server,把 wrapper 那份 settings 的 base URL 换成它,看请求里的 `authorization` 是不是
shell 给的值、`model` 有没有被映射成 provider 的名字:

```bash
sf=$(grep -o '/nix/store/[^ ]*claude-ds-settings.json' ~/.nix-profile/bin/claude-ds | head -1)
python3 -c "import json;d=json.load(open('$sf'));d['env']['ANTHROPIC_BASE_URL']='http://127.0.0.1:8089';print(json.dumps(d))" > /tmp/probe.json
ANTHROPIC_AUTH_TOKEN=fake claude --settings /tmp/probe.json -p hi
```

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

#### 五条互相独立的教训(都是真出过事的)

排查过程横跨 2026-07-25 到 09-07,每一条都是前一条修好之后才暴露出来的,
所以下面的顺序就是它们被发现的顺序。改这段脚本前先看完,坑都在这儿。

**1. prune 跟着高频备份跑会死锁。** 最早的形态,已由上面的剥离解决。

**2. 剥离不清锁,而且失败是静默的。** 2026-07-25 / 07-28 各有一次 prune 被中断
(休眠或关机时 systemd 杀掉服务),留下的 **exclusive 锁**一直躺在仓库里,此后 08-10 到
09-03 共 9 次 prune 全部卡在 `repository is already locked`,每次白等 30 分钟。
备份任务毫发无损——它们用的是非独占锁,所以表面一切正常;而旧脚本的
`|| echo "!! prune 失败"` 让单元恒定 exit 0、永远显示 Finished,`systemctl --failed`
里永远看不到它。两者叠加,一个月零清理却无人察觉。修复是循环里 prune 前先
`restic unlock`(只删同主机 PID 已死、或 >30min 未刷新的锁,不碰并发备份的活锁),
末尾 `exit $rc` 让单元真的变红。**`--retry-lock` 只是等,永远不会清陈旧锁**。

**3. 瓶颈是网盘后端,不是 restic,也不是数据量。** 2026-09-06 还这两个月的欠账:
13 小时 2 分,CPU 只烧了 89 秒——99.8% 在等 WebDAV。删掉 10668 个快照,清完后每个
仓库只剩 50 KiB 左右有效数据,其余全是元数据(每次备份都写一个 snapshot + 一个 index
+ 若干 tree blob)。同样四千多个快照,infini 10 分钟跑完,cst 花了 11.5 小时还失败。

**看到 `does not exist` 不要以为仓库坏了**:那是限流下的假 404,同一个对象换个时刻
就能读到(日志里能看到 `operation successful after 4 retries`)。**也不要因此重建仓库**。
prune 失败同样不必惊慌:forget 删掉的快照是落盘的,下次跑从十几个快照起步,不会从头再来。
restic 的设计是宁可 Fatal 也不带着残缺索引删数据。

**4. 不要用 `forget --prune`,拆成两条命令。** restic 只在这一次 forget 真的删掉了
快照时才接着跑 prune。快照被上一轮删干净后(remove 0),prune 阶段被整个跳过、命令
还返回 0——2026-09-07 就这么假成功过一次:待删的 4098 个 blob 原封不动、远端 2051 个
pack 一个没少,脚本却判定成功。拆开之后 prune 每次都真的执行。
顺带把 forget 失败改成不阻断 prune:某个仓库删快照失败时,pack 该清还是能清。

**5. 有读不回的 pack 时,靠 `--max-repack-size 0` 降级,`repair index` 治不了。**
kp_cst 上有两个 pack,索引里记着 21983 / 22047 字节,实际是 22060 / 22124(各多 77 字节)。
服务端的 PROPFIND 和 GET 都返回真实值、内容也完好(下载下来 sha256 与文件名一致),
失真的是 restic 自己的索引。restic 按索引里的短长度去取 → rclone 用它声明
Content-Length → 实际数据写超 → http2 断开 → `unexpected EOF` → 重试十次后熔断。
症状固定:每次都停在 repack 阶段的同两个文件上。两条走不通的路,别再试:

- **`repair index` 无效**:实测重建 2034 个索引之后,下一轮请求的长度还是 21983。
- **只加 `--max-unused unlimited` 不够**:它管的是「为回收空间而 repack」,restic 还会
  为合并过小的 pack 而 repack,那条路径照走不误(实测降级后仍 14/16 packs repacked
  然后撞上第二个坏 pack)。

有效的是 `--max-repack-size 0`(总共只准 repack 0 字节),两个一起加各堵一条路径。
只在降级重试里用,健康仓库仍走完整清理。代价极小:实测 `to delete` 一个不少(4104 个
blob 全在完全无引用的 pack 里,删它们只需 DELETE、不读内容),只是留下十几个部分使用
的 pack,`unused size after prune: 1.761 KiB`。kp_cst 由此从 2053 个 pack / 1.448 MiB
降到 20 个 / 56.9 KiB。

#### 坚果云(kp_nutstore)是坏的,不要在它身上重复排查

它有**频率封禁**:低频操作正常(单个文件的 rclone delete 确实生效),但 restic 那种
半小时内几百次连续 DELETE 会撞上 `503 BlockedTemporarily: Too many requests are
received recently`,而封禁窗口里的删除请求**返回成功却不生效**。四轮 prune 各报告
"删掉七百多个快照",远端始终是 750 个文件,第四轮的 `remove 734` 和第一轮一模一样。
对照组:同样操作下 cst 和 infini 都只剩十几个文件。

现在它陷在死循环里:750 个快照 → 任何 restic 操作都要几百次请求 → 触发封禁 →
删除失效、读取返回假 404(prune 会直接 `Fatal: failed loading snapshot`)→ 快照继续涨。
连 `rclone size` 都会超时。**restic 这条路进不去**,别再试限速、重试或 repair。
要救只能绕过 restic 一次性清空(WebDAV 对目录的 DELETE 是递归的,`rclone purge` 删
整棵树只要一个请求),然后靠 `initialize = true` 重建;或者干脆把这个远端去掉。

#### 备份侧的两项预防

周期从 10 分钟放宽到 30 分钟(每天 432 次往返 → 144 次),并加上
`--skip-if-unchanged`——内容和父快照一致就不生成新快照。**后一项要验证**:日志里每次都报
`Dirs: 2 changed`(`/home` 和 `/home/xpj` 的 mtime 被别的进程碰过),如果它破坏了判定、
日志里仍是 `snapshot saved` 而不是 `snapshot skipped`,就改用 `ExecCondition` 比对
kdbx 自身的哈希。

### 跨窗口查看活跃会话(cc-sessions,claude-code.nix)

`cc-sessions` 列出本机所有活跃的 Claude Code 会话,按 VS Code 窗口分组;`--watch` 就是 zellij
`cc` tab 里那个循环面板(layout 在 `home-manager/develop/zellij/dev.kdl`,pane 里写的是
`~/.nix-profile/bin/` 下的绝对路径,因为 zellij 的 command pane 不经过 shell)。
实现分两半:`develop/claude-sessions.sh` 只管取宽度/差分重绘/按键,进程枚举和 transcript
解析都在 `develop/claude-sessions.py`(纯标准库),渲染器的路径由 Nix 注入
—— shell 那份是 `builtins.readFile` 进来的,自己没法插值。

**面板是长命进程,不会自己换代码。** bash 在启动那一刻就把当时那份 store 脚本读进去了,
之后 `home-manager switch` 换代它完全不知道(pane 里写的是 `~/.nix-profile/bin/` 下的绝对
路径,但那只在 exec 时解析一次)。2026-09-09 报的"session 检测又不准"就是这么来的:两个
`--watch` 面板分别停在 09-04 和 09-08 起的进程上,少了 09-08 那次 `first_epoch` 修复,
终端会话永远显示"尚未对话" —— 代码早修好了,面板没跟上。
自动换代(见下)之后这种情况不该再出现,再出现先怀疑 `maybe_reexec` 自己坏了。查法(不一致就是它):

```bash
ps -eo pid,lstart,args | grep '[c]c-sessions'
readlink /proc/<pid>/fd/255          # bash 实际在跑的那份脚本
readlink -f ~/.nix-profile/bin/cc-sessions
```

**现在两半都能自己换代,面板不再需要手动重启。** 分工:

- **渲染器**单独成包(`ccSessionsRender`,装到 profile 的 `share/cc-sessions/render.py`),
  `render()` 每轮优先解析 `~/.nix-profile/share/cc-sessions/render.py`,注入的 store 路径只兜底。
  用 `~` 不用 `$HOME`:脚本开着 `nounset`,HOME 万一没设就是第一行 unbound variable 直接死;
  波浪号展开不走参数展开,HOME 缺失时 bash 自己回落 passwd。
- **驱动那半**(现在这个 sh 文件)改不了内存里已经读进去的自己,只能 `exec` 换掉:
  `maybe_reexec()` 每轮拿 `readlink -f /proc/$$/fd/255`(bash 执行脚本时把脚本开在 fd 255,
  内核已经把符号链接解开,拿到的就是 store 路径)和 `readlink -f ~/.nix-profile/bin/cc-sessions`
  比一下,不同就 `exec "$live" --watch "$interval"`。同一个 pid 原地换代,实测改动 + switch 后
  下一轮(1s 内)就跟上了,回滚也一样跟。`exec` 不跑 EXIT trap,所以换之前要自己 `\033[?25h`
  把光标放回来(新进程起来会再藏一次)。

注意判自身路径不能用 `$0`/`$BASH_SOURCE`:那是**调用时**用的 `~/.nix-profile/bin/cc-sessions`,
`readlink -f` 会解析到当前代,永远等于 live,比不出差异。也不要用 `pgrep -f cc-sessions` 找面板
——`bash -c` 那层包装的命令行里也含这个串,`pkill -f` 会连发起命令的 shell 一起杀掉(踩过)。

判据是**进程**:插件里的每个会话都是所属窗口 extension host 的直接子进程,进程在就是活跃。
进程到窗口的映射只有一条路 —— extension host 继承的日志 fd 路径里带 `window<N>`;
父进程的 cwd 是 VS Code 主进程启动时的目录,所有窗口都一样,不能用。终端里的 `claude` 是
makeWrapper 的 bash 脚本,进程名是 `.claude-wrapped`,枚举时两个名字都要认。

标题(`aiTitle`)和状态都在 transcript 里,所以得先把 pid 映射到
`~/.claude/projects/<slug>/<sessionId>.jsonl`(slug 是 cwd 里的非字母数字全换成 `-`)。

**这个映射现在由 Claude Code 自己给出**:2.1.266 起每个会话在
`~/.claude/sessions/<pid>.json` 写一份边车文件,里面有 `sessionId` / `cwd` / `procStart` /
`entrypoint`(`cli` 还是 `claude-vscode`)/ `messagingSocketPath`。确定性映射,没有猜的成分。
两个用法上的坑:

- **必须核对 `procStart`**(就是 `/proc/<pid>/stat` 的第 22 项 starttime,json 里是字符串)。
  进程退出时文件不保证被清掉,而 pid 会复用 —— 只按 pid 取会张冠李戴。
- **`updatedAt` 不是心跳**:实测卡在启动期对话框的会话,`updatedAt`/`statusUpdatedAt`
  停在启动后 2 秒,三小时没动过。别拿它或文件 mtime 当活跃度。

存活判据仍然是 `/proc` 里的进程枚举,边车只按 pid 做补充查找 —— 反过来从
`~/.claude/sessions/` 目录枚举会把崩溃残留当成活会话。

边车文件不存在(旧版本二进制)时退回原来的启发式认领:transcript 一定由某个 claude 进程创建,
首条记录时间必然晚于该进程启动。同一 cwd 下按启动时间升序,每个进程认领「首条时间晚于自己
且尚未被认领」的最早那个。已知错配:`/clear` 之后会留下两个都满足约束的文件,同 cwd 若还有个
启动更晚的新会话,它会认领到本该属于前者的第二个;罕见,没为它加复杂度。

**拿到 sessionId 但 transcript 文件不存在 = "尚未对话",不是"状态未知"。**
会话开着对话框(边车里 `status: "waiting"`、`waitingFor: "dialog open"`)时一条 transcript
都不会落盘,全盘也搜不到那个 sessionId 的任何痕迹(没 todos、没 file-history)。
2026-09-09 的 `claude-config/finance` 就是这个状态,面板显示"尚未对话"是对的。

**下面这段 `first_epoch` 的教训只对 fallback 那条路适用了**,但别删:找"首条时间"的窗口不能写死几行:jsonl 开头有一串没有 timestamp 的元数据行
(`mode` / `permission-mode` / `atis-latch` / `bridge-session` / `file-history-snapshot` ...),
数量随版本增加,实测首条带 timestamp 的记录已经退到第 6 行。窗口只有 5 行时 `first_epoch()` 返回 None、该 transcript
根本不进认领池,于是新会话(命令行里没有 sessionId)永远显示"尚未对话",标题和状态全丢——
2026-09-08 终端会话就是这么"没被检测到"的。现在扫到第一条带 timestamp 的行为止
(40 行 / 256KB 兜底),元数据行都只有几百字节,放宽几乎没有代价。

状态仍然以 transcript 为准,**边车里的 `status` 只有 `entrypoint: cli` 的会话有**
(VS Code 那些连字段都没有,包括正在跑的),所以它只用来兜"transcript 读不出状态"这一种情况。
`stop_reason` 那套是唯一对两种入口都成立的判据:状态只能看 assistant 行的 `message.stop_reason`(`tool_use`/`pause_turn`/`null` 算运行中),
**不能看这一行有没有 tool_use block**:一条 assistant 消息的每个 content block 是分行写的
(thinking 一行、text 一行、tool_use 一行),但同一条消息的所有行带同一个 stop_reason。
按 block 判的话,运行中的会话尾部常常正好停在 thinking 行,会误报成"等你回话",状态在
●/○ 之间反复跳,每跳一次还白触发一次重绘。

**user 行也不能一律当成"Claude 的回合"**:按 ESC 打断时落盘的是一条 user 行,内容就是
`[Request interrupted by user]`(拒工具调用那次是 `...by user for tool use]`)。Claude 已经
停在这儿了,panel 还开着、进程还在,只按"末行是 user 行"判就永远显示运行中。判定必须是
**整行文本恰好等于标记**:打断后立刻又输入的话,标记和新输入落在同一条 user 消息里
(`[Request interrupted by user] 还在干活吗`),那种是真的在跑,用子串/前缀匹配会反过来误判。
抽样确认过 API 出错停下不需要单独处理:那条 `isApiErrorMessage` 的 assistant 行
`stop_reason` 是 `stop_sequence`,本来就落在"等你回话"一侧。

**后台子代理运行期间会显示"等你回话",刻意不修。** 主 agent 派完后台子代理就结束了本轮
(`stop_reason: end_turn`),子代理完成时再把会话唤醒接着跑 —— 这中间面板显示 ○,但它马上
会自己继续。不修的理由是代价不对等:通知是 push,误报打断你手上的事(所以 `claude-code.nix`
的 Stop hook 按 `background_tasks` 压掉了那几条);面板是 pull,扫一眼白切一次窗口而已,
而且它回答的本来就是"Claude 在不在跑",没承诺回答"它会不会自己接着跑"。
真觉得烦要修的话走 hook → `$XDG_RUNTIME_DIR` 文件那条(`background_tasks` 是权威源),
并把陈旧兜底一起做(文件带 `prompt_id`、进程死了不认、SessionEnd 删);
**不要解析 transcript 配对 `agentId:` 和 `<task-id>`** —— 看着可行(两个 id 确实相同),
但 `SendMessage` 续跑同一个子代理时不写 launch 标记,那一轮照样漏判。

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

### mihomo 的双地点切换(一个 OUT 开关)

常驻新加坡、间歇回国,两地需要的东西**是相反的**,所以出境规则全部走一个
`OUT` selector(成员 `[MESL, DIRECT]`),切地点只改这一个:

```bash
netloc cn          # 回国:OUT=MESL + claude=MESL_Claude,然后逐项核对
netloc sg          # 回新加坡:两个都 DIRECT
netloc             # 只看状态,不做改动
netloc cn --quick  # 跳过节点健康检查(那一步 1-2 分钟)
netloc --fix-tun   # tun 掉了就顺手开回来
```

`--fix-tun` **是显式开关,不做成默认**:tun 在 mihomo 没重启的情况下静默消失过两次
(2026-09-12 的 00:36 和 01:57,journal 里都没有关闭记录,01:51 前后有一串
`[TUN] Auto detect interface ... failed, return '<invalid>'`)。每次都默默修掉就看不出
它多久掉一次了,所以不带这个 flag 时脚本只报告。PATCH 只改运行时,配置里本来就是
`enable: true`。

`netloc` 在 `home-manager/netloc.nix`(打包)+ `netloc.sh`(主体,`writeShellApplication`
会对它跑 shellcheck)。**两个 selector 都得切**,所以没做成"一条 PUT 完事":claude 组的
判据是账号安全而不是速度,不能跟着 OUT 走。

脚本刻意**不开 errexit、不在中途 exit**:每步失败都记下来继续跑完、最后统一非 0 退出,
一次输出看清所有线索——半路退出会让人少看到后面的失败。它在两条 PUT 之外还查四处:
读回值是否真的生效(PUT 返回 204 但没生效 = 目标不是该组成员)、tun 网卡在不在、
订阅里有多少节点从当前网络可达、以及 claude 组有没有停在危险的那一侧。连通性自检按
地点选目标:国内测 google(被 GFW 封,能验证出境链路),新加坡测 polymarket
(被本地 DNS sinkhole,只有 DNS 被接管且拿到真实 IP 才通)。

节点存活统计里那句 `alive and (history[-1].delay > 0)` 两个条件都要:`alive` 字段在
从没测过的节点上也是 true(`updatedAt` 是 `0001-01-01` 的那些),只看它会把一整个
未测过的订阅报成"全可用"。仓库列表从 `/providers/proxies` 里按 `vehicleType == "HTTP"`
派生,增删机场不用改脚本。

`profile.store-selected: true` 让选择跨重启保留,所以这是每趟一次的操作,不是每次开机。
不要改成 `mode: direct`:那会连带废掉 `IP-CIDR 10.x → RFvpn` 那几条公司内网路由,
而且 rules/DNS 都没法在运行时 PATCH,只有 selector 能。

#### 两地的墙不是一回事(2026-09-12 实测)

| | 中国 | 新加坡 |
| --- | --- | --- |
| 机制 | GFW:DNS 污染 + IP 封 | **纯 DNS sinkhole,IP 层不封** |
| 需要 | 真代理出境 | 直连即可,只要 DNS 干净 |

新加坡这边 `polymarket.com` 和 `bet365.com` 被本地 DNS 解析到同一个 AWS sinkhole
(`13.248.219.95` / `76.223.70.70`),连上去 0.06s 就失败;而强制用真实 IP
(`104.18.34.205`)直连是 200 / 0.4s,clob API 也返回完整数据。**所以在新加坡不需要任何
代理,只要 DNS 是干净的。**受限辖区是 "The US, Ontario, GB, and OFAC",新加坡不在内。

反过来,机场(MESL)是**国内中转型**:172 个节点只挂在两个入口上,都在中国大陆——
`cl-188` → `106.75.239.109`(上海联通),`cl-199` → `106.75.129.72`(广州电信)。
从新加坡看:上海那个通但 ping 341ms,广州那个 ICMP 100% 丢包、TCP 超时。挂在 cl-199 的
132 个节点(**包括全部 12 个新加坡 + 15 个香港**)因此全废,能用的 39 个全在 cl-188。
于是出现反直觉的现象:人在新加坡,连不上新加坡节点——它们的入口机在广州。

cl-199 到底是路径问题还是机场故障,**在新加坡分辨不出来**(裸 IP 会落到 `MATCH,DIRECT`,
组延迟测试也不会对 anytls 端口说 HTTP)。回国落地后第一件事跑一次,活了就是跨境路径问题:

```bash
curl -s "http://127.0.0.1:9097/providers/proxies/mesl_providers/healthcheck"
```

#### claude 组的目的是账号安全,不是速度

这组存在的理由是给 Claude 一个干净且合规的出口。**曾经的配置(钉在 `MESL_Claude_low`)
起的是反作用**,实测两个出口的风控画像:

```
机场日本节点 103.62.49.148   proxy=True  hosting=True   GSL Networks Pty LTD
本机 Singtel 119.234.106.181  proxy=False hosting=False  mobile=True
```

机场出口是被打上 proxy + hosting 双标记、且机场几百个订阅用户共享的数据中心 IP;自己的
移动 IP 两项标记全 false 且独享。更糟的是 `MESL_Claude_low` / `MESL_Claude` 都是
`url-test`、`interval: 60`,每分钟换节点——一个账号的请求来自不断变化、还跨国跳的数据中心
IP,比任何单个数据中心 IP 都更像异常信号。所以在支持地区(新加坡在列)**直连才是最干净的**。

中国大陆和香港**都不在 Anthropic 支持地区列表**,政策条款是禁止
"Access or facilitate account or API access to Claude ... in violation of our Supported
Regions Policy",后果写的是 "throttle, suspend, or terminate"。所以回国那周必须走代理,
落地点要在支持地区(日本/美国/新加坡都在列)。`MESL_Claude` 实测有 10 个日本节点对
`api.anthropic.com` 可用(354-436ms)。

组类型是 `fallback`、成员顺序 `[DIRECT, MESL_Claude, MESL_Claude_low]`,健康检查用
`gstatic.com/generate_204`——新加坡 DIRECT 能过就直连,中国 Google 被墙则自动降级。
代理层优先 `MESL_Claude`(33 节点)而不是 `MESL_Claude_low`(3 节点):账号安全场景不该
为了 0.3X 倍率把自己锁在 3 个节点上。

**但有个启动窗口期,回国那天要当回事。** `store-selected` 会先恢复上次存的选择,健康检查
才纠正它。纠正确实会发生(把 claude 钉到已知 Timeout 的组,之后它自己回到了 DIRECT),
但**收敛耗时没测准,实测范围是几十秒到两三分钟**——rebuild 后它就在存的旧值上停了 2-3 分钟。
落地时存的是 `DIRECT`(在中国就是中国 IP),所以别指望自动纠正,顺序必须是
**先切、后用**,开 Claude 之前核对一次:

```bash
curl -s 127.0.0.1:9097/proxies/claude | grep -o '"now":"[^"]*"'
```

另外 `sentry.io` 不要挂在 claude 组里(曾经是):它不是 Anthropic 专属的域名,而是几千家
服务共用的错误上报后端,挂在这儿只会把无关遥测推到 Claude 的出口上。

#### tun 是 DNS 那半的前提,`/configs` 的 tun 字段不可信

tun 是唯一劫持系统 DNS 的环节。关掉它,解析回落到本地 resolver——在新加坡就是直接吃
sinkhole(实测 tun 关时 `polymarket.com` 解析到 `76.223.70.70`、浏览器 `http=000`,
而经 `127.0.0.1:7897` 同时刻是 200)。

判断 tun 有没有起来**看 `ip -br addr | grep Mihomo`**,不要看 `/configs` 的
`tun.enable`:实测它报 `false` 的同时,日志里 `Tun adapter listening at:
Mihomo([198.18.0.1/30])` 且 fake-ip 流量正在转发。

还有一个坑:**tun 开着而 `OUT=MESL` 在新加坡会让人以为"网络坏了"**——出境流量全被推去
广州入口,日志里是成片的
`dial OUT (match RuleSet/gfw) ... dial tcp 106.75.129.72:35101: i/o timeout`。
遇到这个先查 `OUT` 指向哪儿,别去动 tun。

#### DNS:gfw 名单在直连时走境外 DoH

`nameserver-policy` 给 `rule-set:gfw` 配了 `1.1.1.1` / `dns.google`。国内场景这些域名
走代理、fake-ip 直接返回,这条策略不触发;新加坡场景它们走 DIRECT 才需要本地真实解析,
此时用境外 DoH。日志确认生效:
`[DNS] polymarket.com --> [104.18.34.205 ...] A from https://1.1.1.1:443/dns-query`。

回国时(`OUT=MESL`)本地 DoH 仍是国内那两个,但这不影响:gfw 域名走代理,主机名交给
anytls 节点、解析在节点侧完成,本地拿到的污染结果无关(2026-09-12 实测
`polymarket 200 via OUT[日本 02]`)。

这条是**消除不确定性,不是必需项**:国内 DoH 实测有一次把 polymarket 解析成 Twitter 的 IP
(`192.133.77.59`),但几分钟后又正常了,去掉这条策略的对照组也能通。DoH 传输本身不可被
中间人污染,可国内递归器向上游走明文,缓存有被污染的窗口。

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
