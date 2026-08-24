---
name: local-diagram-env
version: 1.0.0
description: >
  本机（NixOS）画图工具链的环境事实：飞书画板 SVG 的本地渲染自查该用哪个工具、
  两个渲染器的差别、npx 的离线行为。当你要渲染 / 自查 / 写入飞书画板 SVG 时读本文件。
  不含任何绘图规范——那些一律以 lark-whiteboard skill 为准。
---

# 本机画图环境

> **边界声明**：本文件**只讲本机环境事实**（哪些工具已装、行为差异、坑）。
> 画板的绘图规范、路由选择、元素约束、编辑 workflow **一律以
> [`../lark-whiteboard/SKILL.md`](../lark-whiteboard/SKILL.md) 为准**，
> 与本文件无关，本文件也不复述。两者冲突时以 lark-whiteboard 为准。

## 两个渲染器，用途不同

| 工具 | 字体来源 | 用途 |
|---|---|---|
| `npx -y @larksuite/whiteboard-cli@...`（版本以 lark-whiteboard skill 里写的为准） | **自带** `dist/fonts/NotoSansSC-{Regular,Bold}.ttf` | **交付前的自查基准**。它用的就是飞书线上那套字体，与系统字体无关（实测：隔离掉系统字体后输出字节级一致），所以它的 PNG 和 `--check` 结论最贴近线上表现 |
| `resvg in.svg out.png` | 系统 fontconfig | 迭代期的快速预览。原生二进制、秒级、不碰网络，改一版看一眼很顺手 |

**结论：迭代用 `resvg` 快看，定稿前必须用 `whiteboard-cli` 复核一次**——只信 resvg 有偏差风险（字体虽同名同版本，但渲染引擎不同）。

## resvg 的坑：缺字族只警告，不失败

`resvg` 按字族名精确匹配、不解析 fontconfig 的 alias。字族缺失时它**只在 stderr 打一行
`Warning ... No match for '"XXX"' font-family`，退出码仍是 0**，产出一张没有文字的图。

所以用 resvg 时：**必须看 stderr 有没有 `No match for`，不能只看退出码**。
一个旁证是文件大小——同一张图无字版可能只有有字版的 1/4。

本机系统级已装精确族名 `Noto Sans SC`（Regular + Bold，随 `noto-fonts-cjk-sans` 同版本），
这正是飞书画板导出 SVG 里 `font-family` 用的名字，所以正常情况下不会触发上述警告。
真触发了，是系统字体配置退化，不是 SVG 的问题——报告给用户，别去改 SVG 的字体名绕过。

## npx 是离线优先的

`npm_config_prefer_offline=true` 已全局注入会话及子进程。所以 `npx -y @larksuite/whiteboard-cli@...`
在缓存命中时**不联网**、秒级启动（实测全程禁网也能跑通）。

推论：这条命令要是卡住或变慢，**基本不是网络问题**，别反复重试或换镜像——
先看是不是版本要求变了导致缓存未命中（此时它会正常回落联网拉取，等一次即可）。

## 工具都由 nix 管理

`lark-cli`、`resvg`、`node`/`npx`、系统字体全部由这台机器的 NixOS / home-manager 配置声明。
**不要用 npm / brew / curl 安装或升级它们**——装了也会被下次 rebuild 覆盖掉，
而且会绕过声明式配置（历史上手动 curl 装的字体就是这么变成隐患的）。
需要升级就告诉用户改配置，别自己动手装。
