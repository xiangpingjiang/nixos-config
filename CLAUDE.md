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
- `homeConfigurations.xpj` — standalone home-manager,入口 `home-manager/home.nix`,imports `plasma.nix`(plasma-manager)、`rclone.nix`、`user-secrets.nix`、`apps.nix`(浏览器 + ssh)、`mail.nix`(himalaya)、`netloc.nix`(mihomo 地点切换 + tun 看门狗)及 `develop/` 下的开发工具配置(claude-code、codex、pi、vscode、chrome-devtools-mcp、shell 等)。故意做成 standalone 而非 NixOS module,只改用户配置时 rebuild 更快。

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

唯一用了 router 的是 **`claude-gpt`**:ChatGPT/Codex 订阅没有原生 Anthropic 端点,正是上面
说的例外。它是 `ccr ChatGPT cli` 的薄包装(CCR 取自 llm-agents,nixpkgs 那版还是 2.0.0,
不支持导入 `~/.codex/auth.json` 的 OAuth)。CCR 的 profile 必须叫 `ChatGPT`,profile 和
provider 存在 CCR 自己的 `config.sqlite` 里——含 OAuth 派生凭据,所以**不声明进 Nix store**,
首次配置步骤看运行 `claude-gpt` 时的报错提示。

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
haiku/sonnet/opus 委派子代理,fable 虽然已没有配置主动用到,手动 `/model fable` 时漏了照样撞未知模型。要清楚兜底状态下这套
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

### 浏览器 MCP(develop/chrome-devtools-mcp.nix)

把 Chrome DevTools 接成 MCP server(上游 <https://github.com/ChromeDevTools/chrome-devtools-mcp>),
Claude 能直接开浏览器、点页面、抓网络请求/控制台、录性能 trace、拿堆快照。

**操作步骤全部写在 `local-browser-env` skill 里**(`develop/skills/local-browser-env/SKILL.md`),
本节只讲架构和为什么是这样。日常要用直接看 skill,别从这里抄命令 —— 两份操作指南必然漂。

一句话架构:**一个 MCP server(`chrome`),连一个专用 profile 的 chromium**,
由 systemd user service `chromium-agent` 按需拉起(`systemctl --user start/stop`),
CDP 在 `127.0.0.1:9223`,profile 在 `~/.local/share/chromium-agent`,登录态持久保留。

**自打包,但不用 `buildNpmPackage`。** nixpkgs 里没有这个包(只有 mozilla 那个
`firefox-devtools-mcp`),而 npm 发布的 tarball 是 rollup bundle 过的 ——
`package.json` 的 `dependencies` 是空的,puppeteer/yargs/lighthouse 全打进了 `build/`。
所以既不需要 lockfile 也不需要 `npmDepsHash`:`stdenvNoCC` 解压 + 一个 node wrapper 就能跑
(实测没有 `node_modules` 时 `node build/src/bin/chrome-devtools-mcp.js --help` 正常)。
`package.json` 必须跟着装进 `$out`——它带 `"type": "module"`,漏了 node 会按 CommonJS 解析当场
SyntaxError。drv 里没有编译,`nix flake update` 之后重建就是一次复制。
升级:改 `version`,再跑文件注释里那行 `nix store prefetch-file` 换 hash。

**接法走 `programs.claude-code.mcpServers`**,home-manager 模块会把它渲染成一个合成插件
(manifest 名 `hm`)的 `.mcp.json`,落在 `~/.claude/skills/claude-code-home-manager/`。由此:

- `/mcp` 里显示为 `plugin:hm:chrome`,工具名是
  `mcp__plugin_hm_chrome__<tool>`(写 permissions 规则按这个匹配);
- 终端 `claude` 和 VS Code 插件共用 `~/.claude`,**两个入口都吃得到**。前提是两边都
  ≥ 2.1.157:低于这个版本模块会退回 `--plugin-dir` wrapper,那条路只包住终端的 `claude`,
  插件那份二进制永远拿不到(本机两处都钉在 2.1.286);
- 和 hooks 一样**只对新开的会话生效**,switch 完已开着的会话不会凭空多出这个服务。

#### 为什么只有一个 server(2026-09-22 重构)

在此之前注册了两个:`chrome-devtools`(`--isolated` 临时实例)和 `chrome-live`
(`--browserUrl` 连日常浏览器)。**这个安排本身就是 bug 的来源**:两个 server 跑同一个
二进制,53 个工具的描述一字不差,模型在工具列表里**分辨不出该用哪个** —— MCP 的 stdio
server 配置没有能让客户端展示的 `description` 字段,工具描述来自上游硬编码。
于是默认挑了名字更"正统"的 `chrome-devtools`,用户看到的现象是
"Claude 老是新开一个空浏览器,不用我正在用的那个"。

选择规则当时只写在本文件里,而本文件**只在 `nixos-config` 目录下开会话才加载** ——
调试浏览器这类活儿基本都发生在别的项目里,等于没写。

翻 transcript 统计真实调用(按 `tool_use` 数,不是工具定义在上下文里的出现次数):

| server | 真实调用 |
| --- | --- |
| `chrome-live`(日常浏览器) | 72(另有 9 次 `claude mcp add` 时代的) |
| `chrome-devtools`(isolated) | 35 |
| extensions / pwa 那 8 个工具 | **各 1 次**,而且就是发现"返回 `[{}]`"那次实测 |

结论是两条:真正在用的是"有登录态的真实浏览器";isolated 的独占能力(extensions/pwa)
实际产出为零。所以收敛成一个 —— **选错这件事在结构上就不可能发生**。

**专用 profile 同时解掉了原来两难的两头**:临时实例没有登录态(要登录才能看的页面全废),
连日常浏览器则要先去 `chrome://inspect` 手动勾开关、且那个端口一开就把用户全部账号
暴露给任何能连 loopback 的进程。固定 `--user-data-dir` 让登录态持久(一次性手动登一次,
之后 `start` 就带着),而暴露出去的只是这个 profile 里的账号。

**代价有三条,都已实测、写进 skill**:

- **并发不再隔离**。多个会话连同一个浏览器实例(CDP 支持多客户端),各自 `new_page`
  的页面互相可见,A 的 `close_page` 能关掉 B 正在用的页。真需要隔离时,
  `chrome-devtools-mcp.nix` 末尾注释着一段现成的 `--isolated` server 配置,
  取消注释即可(**那段里 `--executablePath` 不能删**:puppeteer 在 Linux 上按
  `/opt/google/chrome/chrome` 这类 FHS 路径找浏览器,NixOS 上一个都不存在,
  不指定就会去下载一份动态链接的跑不起来)。
- **没有 extensions / pwa 那 8 个工具**。上游说这两类只在 pipe 连接下可用;实测
  `--browserUrl` 下 `list_extensions` **不报错但返回 `[{}]`**,装着 6 个扩展却拿不到
  任何元数据。所以那两个 flag 在 args 里干脆没写。要装/重载扩展去这个实例的
  `chrome://extensions` 手动 Load unpacked / reload。
- **和日常浏览器不共享登录态**。别去 `cp ~/.config/chromium/Default` 过来 —— 那等于
  把全部账号复刻进一个暴露着 CDP 的 profile,正好废掉隔离。chromium 自己的多 Profile
  (`chrome://profile-picker`)也不行:同一 user-data-dir 下的多个 Profile 共享一个
  浏览器进程,而 **CDP 是浏览器级的**,连上去能看到所有 Profile 的 target。

#### 生命周期:懒连接 + 自动重连(都已实测)

`ensureBrowserConnected` 开头是 `if (browser?.connected) return browser`,而它在每次工具
调用都走的 `#getContext()` 里(`build/src/browser.js` / `index.js`)。由此三条性质:

- **会话开着的时候再 `systemctl --user start`,直接就能用**,不必重开会话或 `/mcp` 重连。
  (这条决定了 skill 里写的是"用前 start"而不是"start 完重开会话"。)
- 浏览器中途关掉再开,下一次调用自动重连,返回里带 `"reconnected": true`。
- **MCP server 退出不带走浏览器**:它是 systemd 的服务,不是 server 的子进程。
  所以"会话结束浏览器自然会关"是错的,要自己 `stop`。

service 刻意不写 `wantedBy`(不开机自启)、`Restart=no`(用户关掉窗口就是关掉)。
显示变量不用自己塞:`systemctl --user show-environment` 里
`WAYLAND_DISPLAY`/`DISPLAY`/`XDG_SESSION_TYPE` 都在,实测能正常起图形窗口。

`ExecStart` 用未 override 的 `pkgs.chromium`,**不是** `apps.nix` 里那个 —— 后者带着
`--class=chromium-browser`,和这里的 `--class=chromium-agent` 撞名,KDE 的 Alt+Tab
会把两个实例合成一项(`TabBox.ApplicationsMode=1` 下尤其明显,见后面那节)。
三处 class 各不相同:`chromium-browser`(日常)/ `chromium-agent`(这个)/ `code`(VS Code)。

端口用 9223 而不是 9222,好让日常浏览器的运行时开关能同时存在。实测 chromium 153 在
9223 绑的是 `127.0.0.1`(v4),和 `--browserUrl` 里写的一致 —— 本文件后面记过
"127.0.0.1:9222 被占时会退到 `[::1]:9222`",那是**同端口**被占时的地址回落,换端口不会发生。

**`--autoConnect` 这条路仍然不通**:它要读 `<userDataDir>/DevToolsActivePort`,而
chromium 153 **无论用运行时开关还是命令行 `--remote-debugging-port` 都不写这个文件**
(2026-09-22 用本 service 的 profile 再次实测,文件不存在)。只能继续用 `--browserUrl`。

#### 其余 flag:开了什么、刻意没开什么

默认关着的 `--experimentalDevtools` / `--experimentalVision` / `--memoryDebugging` /
`--experimentalStructuredContent` / `--experimentalIncludeAllPages` 全部打开,
`--experimentalScreencast` 配 `--experimentalFfmpegPath` 钉死 `ffmpeg-headless`
(上游只说"确保 ffmpeg 在 MCP server 的 PATH 里",钉路径免得依赖调用方环境)。
`--experimentalIncludeAllPages` 的副作用是 DevTools 自己的页面也进 `list_pages`,别当成 bug。

**唯一没开的是 `--categoryExperimentalThirdParty`**:它把"被检查页面自己声明的开发者工具"
暴露成 MCP 工具 —— 等于让被访问的网页往 Claude 的工具列表里塞东西,而本机是
`bypassPermissions`。要用就在 args 里加一行。

**两项外发默认关掉**:`--no-usage-statistics`(Google 的使用统计,关掉不损失功能)、
`--no-performance-crux`(performance 工具默认把 trace 里的 URL 提交给 Google 的 CrUX API
换真实用户性能数据 —— 本机常测 10.x 内网和公司域名,不该出境;要 CrUX 数据就删这行)。

**刻意没加 `--workspace`/`--filesystemRoot`,已实测不需要。** 客户端协商了 MCP roots 时,
写文件类工具(截图/trace 落盘)按 roots 放行,Claude Code 2.1.203+ 实现了 roots(会话启动
目录 + `--add-dir` 加的目录)。实测在 `~/cdm-roots-test` 下 `claude -p` 调 `take_screenshot`
带 `filePath`,文件确实落在该目录 —— **验证时注意别在 `/tmp` 下测**:默认限制本来就放行
OS temp 目录,在那儿测等于没测(第一次就踩了这个,scratchpad 恰好在 `/tmp` 下)。

不带 `--headless`,所以会开真窗口 —— 这是特性:要登录某个站点时用户看得见、能自己操作。

#### 安全边界:账号隔离不等于网络隔离

专用 profile 是**牺牲身份**,所以别在里面登公司 SSO、银行、主 Google 账号。
但它仍是 xpj 的进程:**VPN 开着时照样能翻 10.x 公司内网**,flatpak 里 `shared=network`
的应用经 `127.0.0.1:9223` 能拿它当内网跳板(flatpak 的文件系统沙箱挡不住端口)。
这就是"用完 `stop`"的真正理由,不是洁癖。

端口只绑 loopback,网页打不进来:chromium 自己有两道,`Host` 头不是 IP 或 localhost 直接被拒
(`Host header is specified and is not an IP address or localhost.`),WebSocket 升级带
`Origin` 返回 `403 Rejected an incoming WebSocket connection from the ... origin`。
所以威胁模型是**本机进程**,不是外网。

**不要再往 `~/.claude.json` 里 `claude mcp add` 一份。** 那条记的是
`/nix/store/...-chrome-devtools-mcp-<版本>/bin/...` 的绝对路径,而 `~/.claude.json` 不是
GC root:版本一 bump、gc 一跑,server 就静默起不来。一度这么加过(2026-09-17),
已经删掉改成声明式的写法。

#### 日常浏览器的 9222:撤掉了常驻,现在基本不需要碰

`apps.nix` 的 `programs.chromium.commandLineArgs` 里曾有一条 `--remote-debugging-port=9222`
全天候提供,2026-09-21 撤掉,改成要用时去 `chrome://inspect/#remote-debugging` 勾
"Allow remote debugging for this browser instance"。**专用 profile 出现之后,这条路
几乎没有用武之地了** —— 只有"必须复现用户主账号下才出现的问题"这一种情况才值得开,
而且 `.mcp.json` 里已经没有连它的 server(要加回来就是复制一段 `--browserUrl` 到 9222)。

先说**不成立**的那半,免得下次又从头查:网页打不进来(两道防线同上)。所以 DNS rebinding
那类"点个网页就被接管"在这里不成立,外网更不用说(只绑 loopback)。

真正的暴露面是**本机进程**,而且要害不是"任何进程都能连"这句空话。以 xpj 身份跑的普通
进程本来就能直接读 `~/.config/chromium` 的 cookie 库,9222 对它们只是省事。**9222 真正
打穿的是沙箱**:

- **flatpak**。WeChat 的权限里有 `shared=network`(`flatpak info --show-permissions`),
  即不给独立 network namespace、直接用宿主的,于是沙箱里的 `127.0.0.1` 就是宿主的。
  文件系统那半挡住了(读不到 `~/.config/chromium`),但实测
  `flatpak run --command=sh com.tencent.WeChat -c '...'` 用 `/dev/tcp/127.0.0.1/9222`
  直接拿到 `200` —— 沙箱堵死的那条路被这个端口原样绕开,而且能力更强(除了 cookie
  还能 `Page.navigate`、注入 JS、翻内网站点)。flatpak 没有"允许外网但禁止 loopback"
  的粒度,只能从端口这边收。
- **本机的 claude 会话**。`bypassPermissions` 下一条 `curl 127.0.0.1:9222` 就从隔离的
  空实例跳进日常浏览器 —— 常驻的 9222 让那种隔离名存实亡。

nix 构建(`sandbox = true`)在独立 netns,够不着。

运行时开关的实际行为(chromium 153 实测,和文档/UI 文案都不一致,别照抄上游说法):

- **它就在 9222 起服务**,不是随机端口。退到 IPv6 只会发生在 127.0.0.1:9222 已被占用时。
- **没有认证,也没有授权对话框。** Chrome 官方博客写的"每次 MCP 请求会弹框问用户"
  在这个 build 上不存在,外部 `curl` 直接 200。
- **开关会持久化进 profile**,UI 上 "for this browser instance" 是误导:实测同一
  profile 重开浏览器,勾还在、服务也自动起来了。**用完要自己取消勾选**(即时生效,
  不用重启浏览器),否则等于退回常驻状态。
- 持久化位置是 `~/.config/chromium/Local State` 里的 `"remote_debugging":{"user-enabled":...}`。
  只能拿来**读**状态:chromium 运行时把 pref 存在内存里定期写回,改文件会被覆盖。

排查这个开关时注意两个会污染结论的陷阱(都踩过):已经带着 `--remote-debugging-port`
的实例点开开关,它只是**显示**那个已有的 server,证明不了它能自己起一个;
而 puppeteer 用 `--remote-debugging-pipe` 拉起的实例点开后会长时间停在 `starting…`。
干净的测法是自己用 pipe(fd 3/4,JSON 以 `\0` 分隔)起一个新 profile 的 chromium。

**改完 switch 端口不会马上消失**:chromium 单进程多窗口,必须整个退出再启动,
`chrome://restart` 也不行(它用当前命令行 relaunch)。重启前先跑本文件后面那段
`/json/list` 导出标签,`--restore-last-session` 实测靠不住。

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
  用户级 `secrets/qq-mail.enc.yaml`、`secrets/llm-keys.enc.yaml`(整文件加密),声明在 `home-manager/user-secrets.nix`,由 flake.nix 里挂上的
  `sops-nix.homeManagerModules.sops` 提供。用户级密钥解出来在 `~/.config/sops-nix/secrets/<name>`
  (实际指向 `$XDG_RUNTIME_DIR` 下的 tmpfs,重启即失),写入者是 `sops-nix.service` 这个 user unit。
  加密规则在根目录 `.sops.yaml`:`.*\.enc\.yaml$` 那条是 mihomo 的部分加密,新文件要整文件加密就得
  在它**之前**加一条更具体的 `path_regex`(sops 取第一条匹配的规则)。

**新密钥一律走 sops-nix**,现存的 agenix 密钥(rclone 三把 + 系统级 restic_repository)不迁——
都在正常工作,迁移换不来任何功能。选 sops 的理由:一个 YAML 能装多个 key(按用途归档);
有 `sops.templates` 能渲染成 `KEY=VALUE` 喂 systemd 的 `EnvironmentFile`(当前没有用户,
但只有 sops 给得了这个),agenix 没有;`sops <file>` 在仓库任何位置都能跑,而 `agenix -e` 必须在 `secrets/` 目录里
(它要读 `secrets/secrets.nix` 拿收件人)。

顺带区分两个同名的东西:`sops` 是 `home.packages` 里那个独立 CLI(getsops),只管你手动
加解密;sops-nix 是激活时解密的 home-manager/NixOS 模块,跑的是它自带的
`sops-install-secrets`,不调用 `sops` 二进制。两者只共用 `.sops.yaml` 的规则和那把 SSH 私钥。

### restic 备份(services.nix)

三个备份任务(cst / nutstore / infini)把同一个目录(就一个 21KB 的 KeePassXC 库)
备份到三个 WebDAV 网盘,**每 30 分钟一次**,`OnCalendar` 在周期内以 0/10/20 分钟错开
(remote 定义在 `home-manager/rclone.nix`)。**forget+prune 被刻意从备份任务中剥离**,
由单独的 `restic-prune` systemd timer 每周两次执行,仓库列表自动从
`resticRepos` 派生(标了 `prune = false` 的跳过,目前只有 kp_nutstore)——增删备份仓库时无需同步改 prune 脚本。
`initialize = false`:仓库都已建好,而模块的 pre-start 是「读 config 失败就 init」,
后端限流返回假 404/500 时不该去碰 init。要重建仓库就手动 `restic init`。

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
整棵树只要一个请求),然后手动 `restic init` 重建(`initialize` 已关);或者干脆把这个远端去掉。

在那之前它被排除在 prune 之外(`services.nix` 里 `prune = false`):prune 每次必败,
留着的话 `restic-prune` 单元永远是红的(9/14 起连续 6 次),cst/infini 真坏了也看不出来。
备份照跑——低频请求不触发封禁。修好之后删掉那一行。

#### 备份侧的两项预防

周期从 10 分钟放宽到 30 分钟(每天 432 次往返 → 144 次),并加上
`--skip-if-unchanged`——内容和父快照一致就不生成新快照。**已验证生效**(2026-10-01):
三个仓库的日志都是 `skipped creating snapshot`,只有 kdbx 真改过那次才 `saved`,
父目录的 `Dirs: 2 changed` 没有破坏判定。哪天又变回每次都 saved,就改用 `ExecCondition`
比对 kdbx 自身的哈希。

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

**后台子代理运行期间是 `● 子代理`,信息来自 hook 而不是 transcript。** 主 agent 派完后台
子代理就结束了本轮(`stop_reason: end_turn`),子代理完成时再把会话唤醒接着跑 —— 这中间
transcript 里一点痕迹都没有,只看 `stop_reason` 必然判成"等你回话"(2026-09-13 实测一个
94s 的子代理,面板有 55s 显示 ○)。**`background_tasks` 只出现在 hook 的输入 JSON 里,
是唯一的权威源**,所以 `claude-code.nix` 的 Stop hook 把它的快照落到
`$XDG_RUNTIME_DIR/cc-sessions/bg/<sessionId>.json`(和标题缓存同一处 tmpfs),面板按
sessionId 查。写的是整份快照、每次 Stop 都重写,所以自愈:漏删一次下一次 Stop 就纠正。

判据和通知抑制共用同一个计数,**收窄到 `type == "subagent"`**,不写
`background_tasks | length > 0`:后台 shell 可以是 dev server 这种不退出的进程,
那样会话既再也收不到完成通知、面板也会永远显示运行中。

三条陈旧兜底(缺一就会反过来变成常驻误报):

- **SessionEnd hook 删文件** —— 正常退出这条路。
- **文件比进程还老就不认**(`bg_active` 比 mtime 和 `/proc` 的 starttime)。`kill -9`
  走不到 SessionEnd,而 resume 沿用同一个 sessionId,只能按时间分辨;新进程自己那轮的
  Stop 必定晚于它启动,所以这条不会误杀正在跑的。
- **打断那一轮不认标记** —— 所以 `state_of` 把打断单独返回 `interrupted` 而不是并进
  `waiting`:按 ESC 打断不触发 Stop,残留的标记再没有东西来清它。

刻意**不设超时**:后台子代理跑几十分钟是常事,按时长砍反而会在长任务上砍回误报。

两侧靠 `XDG_RUNTIME_DIR` 对齐,写入方是 claude 进程的环境、读取方是面板的环境,
不一致就会一边写 `/tmp` 一边读 `/run/user/1000`、全程静默失效。实测两个入口
(`claude-vscode` 的 extension host 子进程、终端 CLI)都是 `/run/user/1000`,所以没做
按 uid 钉死;哪天换了 login manager 要重新核对(`tr '\0' '\n' < /proc/<pid>/environ`)。

**不要解析 transcript 配对 `agentId:` 和 `<task-id>`** —— 看着可行(两个 id 确实相同),
但 `SendMessage` 续跑同一个子代理时不写 launch 标记,那一轮照样漏判。

注意 **hook 改动只对新开的会话生效**(见本节末),所以改完 switch,已经开着的会话仍然
不写标记,得等它们重开。

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

### mihomo 的双地点切换(一个 OUT 开关)

> **mihomo 两地都常开**(2026-09-20 到 09-30 在新加坡关过,因为 tun 打死了公司 VPN,
> 见下面「fake-ip 与 VPN 的 remote 地址」)。现在两地的 VPN 域名都在 `fake-ip-filter` 里:
> 国内 `vpn1.corp.rockflow.ai`、新加坡 `globalvpn.rockflow.ai`。`claude-code.nix` 的 `env`
> 里 `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` **目前是注释掉的**:带上 proxy 会影响公司 VPN 连接。
> 代价是 Claude 只靠 tun 分流,tun 掉了 API 请求会直连出去(fail-open),开 Claude 前用 `netloc` 确认 tun 在。
>
> **回国切换顺序**(目标是 Claude 的出口 IP 只变一次,2026-09-18 那封 suspicious
> activity 就是出口在国家间反复跳引起的):
> 1. 关电脑出发前 `netloc cn --quick`,核对 `claude` 组是 `claude_cn`。出口在新加坡就换成日本,
>    落地后不再变。日本节点从新加坡连不通也没关系(select 是 fail-closed),落地再核对。
> 2. 落地先跑 `netloc`(tun 在、claude=`claude_cn`)再开 Claude;VS Code 里的会话出发前关掉。
> 3. 回新加坡时 `netloc sg`。
>
> 本节其余内容描述的是开着时的行为。

常驻新加坡、间歇回国,两地需要的东西**是相反的**,所以出境规则全部走一个
`OUT` selector(成员 `[MESL, DIRECT]`),切地点只改这一个:

```bash
netloc cn          # 回国:OUT=MESL + MESL=MESL_low + claude=claude_cn,然后逐项核对
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

#### 订阅拉取要先去控制台授权,只有十分钟窗口(不支持自动拉取)

**看到 `[Provider] mesl_providers pull error: 403 Forbidden` 不是故障,是常态。**
MESL 要求在网页控制台点一次授权,之后**十分钟内**才允许拉订阅;过了窗口一律 403。
`proxy-providers` 里那个 `interval: 3600` 因此每小时白撞一次 403,日志里成片出现,
不用管它——但也**不能指望它自动更新节点列表**。

判断节点列表有多旧:

```bash
curl -s 127.0.0.1:9097/providers/proxies | jq -r '.providers.mesl_providers.updatedAt'
```

要更新就走这个流程(授权完立刻手动触发,别等 interval):

```bash
# 1. 浏览器打开机场控制台点授权
# 2. 十分钟内手动让 mihomo 拉一次
curl -X PUT http://127.0.0.1:9097/providers/proxies/mesl_providers
# 3. 核对 updatedAt 变成刚才
```

2026-09-12 00:42 到 09-13 20:00 之间 57 次 403、节点列表冻结 44 小时就是漏了这一步。
冻结本身不会立刻断网(已有节点照常能连),但机场换一批节点地址就会静默死一批。

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

##### 外层**必须是 select**:fallback 在这里是 fail-open(真漏过)

```yaml
claude:     select   [claude_cn, DIRECT]                  # 地点开关,netloc 切
claude_cn:  fallback [MESL_Claude_low, MESL_Claude]       # 降级只在机场层内部发生
```

一度写成单层 `fallback [DIRECT, MESL_Claude_low, MESL_Claude]`,想着「新加坡 DIRECT
能过健康检查就直连,中国 Google 被墙则自动降级」。**这个设计漏 IP,而且真漏了**:
mihomo 的 fallback 在**所有成员探测都失败**时回落 `proxies[0]`
(`adapter/outboundgroup/fallback.go` 的 `findAliveProxy`),而 DIRECT 在国内对
`gstatic.com/generate_204` 恒 Timeout。2026-09-13 19:33 两个代理层碰巧同时探测失败,
整组落到 DIRECT,**21 条 `using claude[DIRECT]` 带着中国 IP 打到 api.anthropic.com**。

两层为什么会同时死:那会儿 `MESL_Claude` 和 `MESL_Claude_low` 的 url-test **挑中了同一个
节点**(台湾 01 既是 33 个里最快的、也是 3 个 0.3X 里最快的),一个节点抖动就判死两层。
所以 `MESL_Claude` 加了 `exclude-filter: 0\.3X`,两层不再共享成员。

`select` 不做健康检查、只认手动选择,最坏情况是停在机场节点上连不通(fail-closed)。
`netloc cn` 切的是 `claude_cn`,`claude_guard` 的判据也从「不是 DIRECT 就算过」改成
**「必须是 `claude_cn`」**——黑名单换白名单。

**另外有个启动窗口期。** `store-selected` 会先恢复上次存的选择,收敛要几十秒到两三分钟
(rebuild 后实测在旧值上停了 2-3 分钟)。落地时存的可能是 `DIRECT`,所以顺序必须是
**先切、后用**,开 Claude 之前核对一次:

```bash
curl -s 127.0.0.1:9097/proxies/claude | grep -o '"now":"[^"]*"'   # 国内必须是 claude_cn
```

顺带,`claudeusercontent.com`(Artifacts/用户内容)**不在 gfw 列表里**,漏配就落到
`MATCH` 直连——实测 57 条 `bridge.claudeusercontent.com ... using DIRECT`。规则里单独加一条。

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

#### DNS:gfw 名单的解析跟着 OUT 走(`#OUT` 后缀)

```yaml
nameserver-policy:
    rule-set:gfw:
        - "https://1.1.1.1/dns-query#OUT"
        - "https://dns.google/dns-query#OUT"
```

`#组名` 是 mihomo 的 DNS-over-proxy 语法,让这条查询本身经该组出去。于是 DNS 路径和它
服务的流量走同一个 selector:新加坡 `OUT=DIRECT` 直连 DoH,国内 `OUT=MESL` 经机场查。

**这里踩过一次,教训是 TCP 和 UDP 的解析路径不一样。** 最初写成不带 `#OUT` 的裸
`1.1.1.1`,理由是「国内这些域名走代理、fake-ip 直接返回,策略不触发」——**那只对 TCP 成立**:
TCP 把主机名交给 anytls 节点,解析在节点侧完成。**UDP(QUIC/HTTP3)mihomo 必须先在本地
解析出真实 IP 再拨给代理**,于是撞上在国内本就被墙的 `1.1.1.1`,20 分钟里 11 次:

```
[UDP] dial OUT (match RuleSet/gfw) --> www.youtube.com:443
error: can't resolve ip: requesting https://1.1.1.1:443/dns-query: context deadline exceeded
```

症状不是打不开而是**慢**:QUIC 超时后回落 TCP,`youtube.com` 实测 5.45s。日志里全是 `[UDP]`,
没有一条 `[TCP]` —— 这个比例本身就是判据。

**不能改回国内 DoH,也不能加它做兜底。** 国内 DoH 在国内确实返污染结果(2026-09-12 实测):

| | www.youtube.com | polymarket.com |
| --- | --- | --- |
| alidns | 31.13.92.37(Facebook) | 108.160.163.102(Dropbox) |
| doh.pub | 69.171.235.22(Facebook) | 真实 IP |

而 mihomo 对 policy 列表是**并发取最快**,国内那个每次都会先返回污染结果赢掉,所以列进去
等于没配。(在新加坡查这两个 DoH 拿到的结果干净得多,别拿那时的采样下结论——递归路径不同。)

#### 低倍率(0.3X)优先:省流量,而且出口更干净

`MESL` 是 `fallback [MESL_low, MESL_no_low]`,`claude_cn` 是
`fallback [MESL_Claude_low, MESL_Claude]` —— 都把 0.3X 放前面,low 组整体不可用时自动回落。
(原先 `MESL` 末尾还挂着 `Reality`,实测 `alive=false`、delay 0,TCP 能连上但握手层失败,
是个假兜底,已从组里移除;`Reality` 那个 select 组也已删掉(没有任何引用),
`Reality-节点` 的定义还留着,修好了可以加回。)
用 `fallback` 而不是 `select` 就是为了这个自动回落;它同样接受手动 PUT,想强制某一层随时可以。

**但光改顺序不会让 0.3X 生效。** `fallback` 只在「当前选择失效」时才换人,不会因为排在
前面的那个更优先就主动切回去;而 `store-selected` 开机先恢复上次存的值。于是改完成员顺序、
rebuild 之后,只要旧选择还活着,新顺序就永远轮不上 —— 2026-09-13 就是这样:配置里
`claude` 已经是 `[DIRECT, MESL_Claude_low, MESL_Claude]`,实际却一直停在 `MESL_Claude`。
**必须 PUT 一次**,所以 `netloc cn` 现在切三个而不是两个:`OUT` / `MESL` / `claude`。

顺带:判断有没有走 0.3X **不能只看顶层**。`OUT = MESL` 什么也说明不了,`MESL` 自己是
fallback,底下还有两层。`netloc` 的状态行因此展开到叶子:
`OUT = MESL → MESL_low → 🇨🇳 台湾 01 [0.3X]`。

省流量是显然的(按 30% 计费),**反直觉的是低倍率节点的风控画像反而更好**(2026-09-12 国内实测):

| 节点 | IP | proxy | hosting | ISP |
| --- | --- | --- | --- | --- |
| 台湾 01 [0.3X] | 103.208.196.123 | false | true | Sky Digital |
| 日本 01 [0.3X] | 31.223.184.105 | **false** | **false** | G-Core Labs |
| 新加坡 01 [0.3X] | 116.251.216.10 | true | true | OneAsiaHost |
| 对照:no_low 日本 06 | 103.62.49.147 | true | true | GSL Networks |

`MESL_Claude_low` 现在**只留日本**:`filter: 日本.*0\.3X`,外加 `tolerance: 10000`。
**filter 用正向而不是 exclude**:原先写的是 `filter: 0\.3X` + `exclude-filter: 香港`,反向写法
只挡住了已知的坏地区——机场以后新增一个不支持地区的 0.3X 节点就会自动混进 Claude 的链路。
正向 filter 是白名单,加地区要显式改这一行。

为什么从「台湾/日本/新加坡」缩到只剩日本:三个候选只差几十毫秒,url-test 会频繁换
出口 IP,风控看到的是同一会话在数据中心之间反复跳(2026-09-18 那封 suspicious activity)。
`tolerance: 10000`(新节点要快 10s 以上才切)压住了抖动,但日本 01 恰好最慢(121ms vs 台湾 77ms),
只加 tolerance 会把链路锁死在画像更差的台湾上,所以候选也得缩到只剩画像最好的日本。
当前节点真死了仍会立刻换(`urltest.go` 里 `!AliveForTestUrl` 是独立判据)。
`MESL_Claude` 同理也只留日本(`filter: 日本` + `exclude-filter: 0\.3X`),low 层挂了回落时
出口仍不跨国。

#### 规则层面清过一轮死配置(2026-09-13)

- **那七条 `IP-CIDR` 绝对不能加 `no-resolve`**,原因见下一节。曾经加过,当场断掉公司 VPN。
- **`RULE-SET,applications` 删了**:98 条全是 `PROCESS-NAME`,而 `find-process-mode: "off"`
  → 永远不匹配。
- **七个 rule-provider 定义了但规则里从没引用**(`apple` / `icloud` / `google` / `proxy` /
  `direct` / `cncidr` / `lancidr`),合计约 14.8 万条,每天白下载还常驻内存,一并删掉。
  `rule-providers` 从 11 个降到 5 个(`gfw` / `private` / `reject` / `telegramcidr` /
  `tld-not-cn`)。增删时用这条核对有没有漏:`curl -s 127.0.0.1:9097/providers/rules | jq keys`
  比对规则里实际出现的 `RULE-SET,<name>`。

#### 公司 VPN 与外网代理共存:按解析结果路由,不要按域名

两层各管一半,都要留着:

| 层 | 位置 | 管什么 |
| --- | --- | --- |
| `route-exclude-address` | tun | **裸 IP 访问**。这些网段的包压根不进 mihomo,`ssh 10.129.x` 零开销 |
| `IP-CIDR,...,RFvpn` | rules | **域名访问**。fake-ip 把流量拉进 tun,mihomo 解析出真实 IP 再匹配 |

`RFvpn` 是 `type: direct` + `interface-name: tunRFvnp` + `routing-mark: 123` —— 出站绑死在
VPN 网卡上。不能指望 `DIRECT`:tun 模式下它走物理网卡,10.x 根本不可达。也不要为了图省事
改 `mode: direct`,那会连带废掉这几条路由。

**不要"优化"成 `DOMAIN-SUFFIX,<公司域名>,RFvpn`。** 看着更直接,实际两头都错:

- **公司内网域名不止一个后缀**(除 `bobby.ai` 外还有阿里云 RDS 那种
  `...mysql.singapore.rds.aliyuncs.com`),按域名写就变成一份要追着公司变更手工维护的清单。
- **同一个后缀下公网和内网是混着的**(2026-09-14 实测):

  ```
  bobby.ai                    -> 47.57.191.191 47.57.244.238   公网(阿里云香港)
  bobby-pro-console.bobby.ai  -> 10.129.250.83 10.129.254.159   内网
  ```

  `DOMAIN-SUFFIX,bobby.ai,RFvpn` 会把公司的公网站点一起塞进 VPN。

按解析结果路由则两种情况自动分流,且**自维护**:新开的内网机器、换的域名、任何后缀,只要
解析进已列网段就走 VPN。查真实解析别用 `getent`(fake-ip 只会给 198.18.x),问 mihomo 自己:

```bash
curl -s -H "Authorization: Bearer $(cat /run/secrets/mihomo_secret)" \
  "http://127.0.0.1:9097/dns/query?name=bobby-pro-console.bobby.ai&type=A" | jq -r '.Answer[]?.data'
```

**代价是这条链依赖"谁来解析公司域名"**,所以有两条铁律:

- **绝不能加 `no-resolve`。** 2026-09-13 加过一次,当场断掉全部公司内网域名访问约两小时:
  跳过解析就不匹配 IP-CIDR,一路落到 `tld-not-cn`(第 10 行就是 `+.ai`)被推去机场。
  当时误判的证据是"49 条连接里 42 条 `destinationIP` 为空"—— 那些空值里混着内网域名,
  是**故障本身**,不是省掉白解析的成效。
- **别让公司域名落进 `nameserver-policy` 的 gfw 分支。** 现在能解析出 10.x,是因为公司把
  RFC1918 地址挂在公网 DNS 上、而 `bobby.ai` 不在 gfw 名单里,走的是默认的国内 DoH。
  一旦进了那个分支,解析会变成 `https://1.1.1.1/dns-query#OUT` —— 公司内网域名的解析跨境
  经机场出去,不管返回什么都不该发生。(VPN 自己不推送 DNS,`nmcli` 里 RFvpn 没有 IP4.DNS,
  所以没有"用 VPN 的 DNS"这个选项。)

##### fake-ip 与 VPN 的 remote 地址:域名必须进 `fake-ip-filter`

上面那条链的前提是 VPN 本身连得上,而 **fake-ip 会把 VPN 自己的传输层打死**。
2026-09-20 实测(服务器已从 `vpn1.corp.rockflow.ai` 换成 `globalvpn.rockflow.ai`,
而 `fake-ip-filter` 里只有前者):

1. openvpn 解析 remote,拿到 fake-ip `198.18.0.12`,并把它记成服务器地址
   (日志里 `Preserving recently used remote address: [AF_INET]198.18.0.12:18443`)。
2. NetworkManager 按惯例给"VPN 服务器"加一条绕行主机路由,免得 VPN 自己的流量
   走进自己的隧道 —— 于是主表里多出 `198.18.0.12 via <LAN 网关> dev wlp1s0 metric 50`。
3. mihomo 的策略路由**压不住这条**:`ip rule` 里那条
   `not from all dport 53 lookup main suppress_prefixlength 0` 只屏蔽主表的默认路由,
   `/32` 照样命中。包于是发给家里的路由器 → 黑洞。

症状极具迷惑性:`nmcli` 一直显示 `VPN connected`、`tunRFvnp` 网卡和 10.129/10.130/10.131
的路由全都在,但整个内网一个都不通,openvpn 每 2 分钟
`connect to 198.18.0.12:18443 failed: Connection timed out` 重来一次。判据是
**mihomo 日志里根本没有那条连接**(它压根没进 tun),以及:

```bash
ip route get <VPN 服务器地址>      # 走 wlp1s0 而不是 Mihomo,就是它
```

修法是把 VPN 域名加进 `dns.fake-ip-filter`(`secrets/mihomo.enc.yaml`),让它拿到真实 IP,
NM 那条绕行路由才指得对。**换 VPN 服务器域名时必须同步改这里** —— filter 里那行
`vpn1.corp.rockflow.ai #这个必须加上` 就是为这个坑加的,但域名换了没跟上,于是又踩一次。
临时脱困(不改配置):`nmcli con down/up` 只能撑到下一次解析,真正让它恢复的是 tun 消失。

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

### chromium 被 KDE 当成 VS Code(Alt+Tab 里找不到窗口)

症状是 Alt+Tab 切不到 VS Code:chromium 和 VS Code 在切换器里合成一项,翻过去拿到的是浏览器窗口。
**根因不在 KDE,在一个从 VS Code 泄漏出来的环境变量。**

VS Code 是 Electron,启动时给自己 `setenv CHROME_DESKTOP=code.desktop`,这个变量被**所有子进程继承**
——集成终端、extension host、Claude Code 起的 MCP server 全都带着它。而 chromium 正是读它来决定
"我对应哪个 .desktop",进而决定 Wayland 的 `app_id`(X11 下是 WM_CLASS 的 class 那半)。于是从
VS Code 里以任何方式启动的 chromium,`app_id` 都变成 `code`,KWin 按 `desktopFileName` 判定
"是不是同一个应用"就把它和编辑器归成一组。

**两个坑在查证这件事时会挡路**:

- **VS Code 主进程自己的 `/proc/<pid>/environ` 是干净的** —— 那是启动快照,而 Electron 是运行时 setenv,
  只有子进程才有。要看链上的子进程(extension host、claude、MCP server)。
- **chromium 主进程的 `environ` 读出来是空的**(它自己清掉了),所以别指望从浏览器进程本身取证。

判据是 KWin 里的窗口属性,`resourceName` 还是 `chromium`、只有 `resourceClass`/`desktopFileName` 变成
`code` —— 而 KWin 用的恰好是后者。取法(KWin script 没有别的入口,输出去 journal):

```bash
cat > /tmp/dump.js <<'EOF'
workspace.windowList().forEach(function(w) {
  if (!w.normalWindow) return;
  print("WINDOW|" + w.resourceClass + "|" + w.resourceName + "|" + w.desktopFileName + "|" + w.pid + "|" + w.caption);
});
EOF
n=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /tmp/dump.js "d$RANDOM")
qdbus org.kde.KWin /Scripting/Script$n org.kde.kwin.Script.run
journalctl --user -b --since "-10s" | grep 'WINDOW|'
```

同一个脚本名只能 run 一次,复查要换名字重新 load(所以上面用了 `$RANDOM`)。

三组对照实测(同一个 chromium 二进制),确认那个变量是唯一变量、且 `--class` 的优先级更高:

| 启动环境 | app_id |
| --- | --- |
| `CHROME_DESKTOP=code.desktop` | `code` |
| 同上 + `--class=chromium-browser` | `chromium-browser` |
| `env -u CHROME_DESKTOP` | `chromium-browser` |

**不是全局泄漏**,`systemctl --user show-environment` 和 plasmashell 的 environ 里都没有这一项 ——
从 KDE 菜单正常启动本来就是干净的,中招的只有"从 VS Code 里启动"这条路(集成终端手敲、点链接走 xdg-open)。
顺带纠正一个看着像证据的东西:**chromium 会自己建 systemd scope 并 reparent 到 `systemd --user`**,
所以"进程在 `app-org.chromium.Chromium-<pid>.scope` 里、父进程是 systemd"**不能**用来判断它是从菜单启动的。

修法分两处,因为两条路径用的不是同一个 chromium wrapper:

- **日常 chromium** —— `apps.nix` 的 `commandLineArgs` 里 `--class=chromium-browser`。一行覆盖全部启动路径。
- **Claude 用的那个** —— 现在由 systemd user service `chromium-agent` 拉起
  (`develop/chrome-devtools-mcp.nix`),`ExecStart` 里直接写 `--class=chromium-agent`。
  **这条链已经不会中招了**:service 的环境来自 `systemd --user`,不是 VS Code 的后代,
  实测 `systemctl --user show-environment` 里没有 `CHROME_DESKTOP`。
  2026-09-22 之前是 MCP server 自己拉浏览器(server 是 extension host → claude 的后代,
  整条链继承那个变量),只能靠 `env.CHROME_DESKTOP` 覆盖 —— `--class` 到不了它,
  因为 `chrome-devtools-mcp` 没有透传浏览器参数的 flag。那段配置现在注释在文件末尾,
  真要启用 `--isolated` server 时**连 `env.CHROME_DESKTOP` 一起取消注释**。

**`--class` 只改 app_id,不改 chromium 内部认定的 desktop file**,所以网页通知的 `desktop-entry` 提示
还会挂在 VS Code 名下。要治那半只能覆盖环境变量,而 `commandLineArgs` 到不了环境变量层,没为此去包
一层 wrapper。

**症状被 `kwinrc.TabBox.ApplicationsMode = 1` 放大了**(plasma.nix,值 `1` 是 KCM 里的
"Only one window per application",`0` 是 "All windows")。八个 VS Code 窗口加两个 chromium 窗口
本来就各自只占一项,分组一错就压成**一项**,于是"VS Code 从 Alt+Tab 里消失"。这个设置本身是刻意的,
在同一应用的窗口之间切用 ``Alt+` ``(Walk Through Windows of Current Application)。

#### 改完之后要重启浏览器,而且有两个坑

`app_id` 在进程启动那一刻定死,**新开窗口不算重启** —— chromium 是单进程多窗口,新窗口继承进程的值。
必须让所有窗口关掉、进程真的退出再启动。**`chrome://restart` 也不行**,它用当前进程的命令行 relaunch,
拿不到新参数。核对:

```bash
ps -eo pid,args | grep '[l]ibexec/chromium/chromium ' | grep -v -- '--type=' | grep -o -- '--class=[^ ]*'
```

**`--restore-last-session` 靠不住,关之前先自己导出 URL。** 实测(2026-09-18)优雅 SIGTERM 退出、
`exit_type` 确实写成 `SessionEnded`、Session 文件也有 900KB,但重启后只恢复回 1 个窗口 8 个标签,
原本是 2 个窗口 37 个去重 URL。而且这台机器的 `restore_on_startup` 是 `1`(打开特定网页)且
`startup_urls` 为空,所以不加那个 flag 连一个标签都不会回来。先备份(9222 已不常驻,
先去 `chrome://inspect/#remote-debugging` 勾上开关,导完再取消):

```bash
curl -s 127.0.0.1:9222/json/list | python3 -c "
import json,sys
print('\n'.join(dict.fromkeys(t['url'] for t in json.load(sys.stdin) if t.get('type')=='page')))
" > /tmp/tabs-backup.txt
```

补回去用 `chromium --new-window <url>...`(会转发给已有实例,开成一个新窗口)。
`chrome-extension://` 那类页面命令行打不开,只能从扩展图标手动点。

**这份备份只覆盖"已加载"的标签。** CDP 的 `/json/list` 列的是 page target,chromium 会把长期没点过的
标签卸载掉(恢复出来的标签在第一次点开前也是未加载),那些拿不到 —— 实测补完 34 个标签之后再查,
同一个命令只剩 21 个。所以导出时间点越接近"刚用过这些标签"越全,别指望它是完整的标签清单。

另外 **MCP 那半的改动只对新开的 Claude 会话生效**(和 hooks 一样),已经开着的会话仍用旧 server。

## 约定

- 注释使用中文,新增配置保持这一风格。
- `mihomo_test_config.yaml`(根目录)是 mihomo 的明文测试配置,真实配置在 `secrets/mihomo.enc.yaml`(sops 加密)。
