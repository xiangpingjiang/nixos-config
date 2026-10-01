---
name: local-browser-env
version: 1.0.0
description: >
  本机（NixOS）用 Claude 操作浏览器的环境事实：只有一个 MCP server（工具前缀
  `mcp__plugin_hm_chrome__`），它连的是一个专用 profile 的 chromium，登录态持久保留。
  **调任何 `mcp__plugin_hm_chrome__*` 工具之前，先 `systemctl --user start chromium-agent`；
  整件事做完 `systemctl --user stop chromium-agent`。** 当任务涉及打开网页、点页面、
  抓网络请求或控制台、跑 Lighthouse、录性能 trace、取堆快照、截图页面时读本文件。
  也包含"不要做什么"——止住"去 chrome://inspect 勾开关"和"改连用户日常浏览器"的冲动。
---

# 本机浏览器环境

> **边界声明**：本文件**只讲本机怎么接、行为差异和坑**。
> 各个 MCP 工具自己的参数以它们的工具描述为准，本文件不复述。

## 先看这两条

**一、用之前先把浏览器拉起来。**

```bash
systemctl --user start chromium-agent
```

profile 是全新的那次（或刚删过）会弹一次 chromium 欢迎向导，关掉即可，不是起错了。

不拉起来的话，`mcp__plugin_hm_chrome__*` 的**每一个工具都会失败**（连接超时），
这是正常的，不是服务坏了。

**二、整件事做完把它关掉。**

```bash
systemctl --user stop chromium-agent
```

不是洁癖，理由在下面「安全边界」一节——这个端口没有任何认证。

## 只有一个 server，连的是专用 profile

| 东西 | 值 |
| --- | --- |
| MCP server | `plugin:hm:chrome`，工具前缀 `mcp__plugin_hm_chrome__` |
| systemd unit | `chromium-agent`（user service，不开机自启） |
| profile 目录 | `~/.local/share/chromium-agent` |
| CDP 端口 | `127.0.0.1:9223`（v4，已实测不是 `[::1]`） |
| 定义在 | `home-manager/develop/chrome-devtools-mcp.nix` |

它**不是**用户日常那个浏览器（那个的 profile 是 `~/.config/chromium`），
也**不是**每次全新的临时实例。是第三个东西：一个固定的、只给 Claude 用的 chromium。

2026-09-22 之前这里有两个 server（`chrome-devtools` 临时实例 / `chrome-live` 连日常浏览器），
它们跑同一个二进制、53 个工具描述一字不差，模型分辨不出该用哪个。现在只有一个，
**看到 `chrome-devtools` 或 `chrome-live` 这两个名字就是过时信息**。

## 登录态是持久的，但要先登一次

profile 固定 => cookie/session 落在 `~/.local/share/chromium-agent`，`stop` 掉也不清，
下次 `start` 还在。

**但它和日常浏览器不共享登录态**，这是隔离的代价，不是故障。第一次遇到某个要登录的站点，
按你是谁分两种做法：

- **主会话**：这个 service 起的是有头窗口、用户看得见，请用户在那个窗口里手动登一次，
  之后就一直带着。
- **子代理**：你没有和用户对话的通道。遇到登录页**直接返回"需要先登录 X"并停下**，
  不要自己去填表单、不要试图绕过。

别去 `cp ~/.config/chromium/Default` —— 那等于把用户全部账号复刻一份到这个暴露着 CDP 的
profile 里，正好废掉隔离。

## 生命周期：懒连接 + 自动重连（都已实测）

- **会话开着的时候再 `start`，直接就能用**。MCP server 进程在会话启动时就起，但要到
  第一次调用工具时才连浏览器（`ensureBrowserConnected` 在每次调用都走的 `#getContext()` 里）。
  所以**不需要重开会话，也不需要 `/mcp` 重连**。
- **浏览器中途关掉再开，下一次调用自动重连**，返回里会带 `"reconnected": true`。
- **会话结束不会带走浏览器**。它是 systemd 的服务，不是 MCP server 的子进程。
  所以"我这个会话结束了浏览器自然会关"是错的 —— 要自己 `stop`。

## 多会话共享同一个实例

本机同时开好几个 Claude 会话是常态。它们**连的是同一个浏览器**（CDP 支持多客户端，已实测）：

- 各自 `new_page` 开的页面**互相可见**，`list_pages` 会列出别人的页。不是 bug。
- `select_page` 只影响自己这一路。
- **只关自己开的页**：`close_page` 能关掉另一个会话正在用的页面。

要真正互不干扰的隔离实例，`chrome-devtools-mcp.nix` 末尾注释着一段现成的 `--isolated`
server 配置，取消注释再 switch 即可（代价是那个实例没有登录态）。

## 要一个没有登录态的干净环境

```bash
systemctl --user stop chromium-agent
rm -rf ~/.local/share/chromium-agent
systemctl --user start chromium-agent
```

测首次访问体验、未登录状态的页面时用这个。注意这会**删掉所有已登录的账号**，
删之前先确认用户不介意重登。

## 这里没有的能力

- **extensions / pwa 那 8 个工具不存在**（`list_extensions`、`install_extension`、
  `reload_extension`、`trigger_extension_action`、`uninstall_*`、`install_pwa`、`launch_pwa`）。
  上游说这两类只在 pipe 连接下可用；实测 `--browserUrl` 模式下 `list_extensions`
  **不报错但返回 `[{}]`**，装着 6 个扩展却拿不到任何元数据。所以干脆没注册。
  要装/重载扩展：让用户去这个实例的 `chrome://extensions` 手动 Load unpacked / reload。
- **操作用户日常那个浏览器**。那需要它自己开 CDP 端口，而 9222 不常驻（撤掉的理由见
  `apps.nix` 和 CLAUDE.md）。**不要主动提议让用户去 `chrome://inspect` 勾开关** ——
  专用 profile 就是为了不再需要那一步。除非用户明确说"我要调试我自己正在用的浏览器/
  我那个只在主账号下复现的问题"，那时才提这条路，并说明代价（那个端口开着时，
  任何能连 loopback 的进程都能完全驾驭他带全部登录态的浏览器）。

## 省上下文：snapshot 是最贵的读法

`take_snapshot` 返回整页的 a11y 树，一次几千到几万 token，而且会跟着会话后面的
每次请求被重发（2026-09-23 统计：7 次 snapshot 被放大成 712 万 token，是所有 MCP 工具里最贵的）。

- 只要一个值（文本、属性、元素在不在）时，用 `evaluate_script` 取，返回结果尽量压到最小，
  例如 `() => document.querySelector('.price')?.textContent`。
- 要点击或填表时需要 uid，这时才用 `take_snapshot`；同一页面没变就别重复拍。
- `list_network_requests` / `list_console_messages` 先用过滤参数缩小范围，再按 id 取单条详情。

## 安全边界

这个 profile 是**牺牲身份**，但它仍是 xpj 的进程：

- **别在这里登**公司 SSO、银行、主 Google 账号。用户要登什么由用户决定，
  但如果他让 Claude 去登某个敏感账号，提醒一句这个 profile 的 CDP 是无认证的。
- **账号隔离 ≠ 网络隔离**。VPN 开着时这个浏览器照样能翻 10.x 公司内网；flatpak 里
  `shared=network` 的应用（微信、腾讯会议）经 `127.0.0.1:9223` 能拿它当内网跳板
  —— flatpak 的文件系统沙箱挡不住端口。这就是"用完要 stop"的真正理由。
- 端口只绑 loopback，网页打不进来（chromium 自己会拒非 IP/localhost 的 `Host` 头和
  带 `Origin` 的 WebSocket 升级），所以威胁模型是**本机进程**，不是外网。

## 连不上时按这个顺序查

```bash
systemctl --user is-active chromium-agent          # 1. 服务在不在
curl -s -m 2 127.0.0.1:9223/json/version           # 2. 端口通不通
ss -tln | grep 9223                                # 3. 绑的是 127.0.0.1 还是 [::1]
systemctl --user status chromium-agent --no-pager  # 4. 起失败的原因
```

第 3 步要注意：`browserUrl` 钉死的是 `http://127.0.0.1:9223`，绑到 `[::1]` 就连不上。
另外 `ss` 显示的 backlog 是 `LISTEN 0 10`：多会话并发时每个 puppeteer 连接都要握手，
10 够用，但真出现"第 N 个会话偶发连不上"先怀疑这个，别又去查 v6 回落。
正常情况是 v4（已实测），出现 v6 说明 9223 被别的进程占了 —— 先看是谁占的，
不要改 nix 里的端口去绕。

**不要**因为连不上就去 `chrome://inspect` 勾开关：那是日常浏览器的 9222，
和这里完全是两回事，勾了也不会让 9223 通。
