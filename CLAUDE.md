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

### 密钥管理(agenix + sops-nix 双方案)

两套方案共用同一把 SSH 私钥 `/home/xpj/.ssh/id_ed25519` 解密:

- **agenix**:`.age` 文件放 `secrets/`,接收者公钥定义在 `secrets/secrets.nix`。系统级声明在根 `secrets.nix`,用户级声明在 `home-manager/secrets.nix`。编辑密钥:在 `secrets/` 目录下 `agenix -e <name>.age`。
- **sops-nix**:用于部分加密的 YAML(目前只有 `secrets/mihomo.enc.yaml`,`key = ""` 表示解密整个文件给 mihomo 服务用)。

### restic 备份(services.nix)

三个备份任务(cst / nutstore / infini)每 10 分钟一次,`OnCalendar` 分别以 0/3/6 分钟错开,通过 rclone WebDAV 后端(remote 定义在 `home-manager/rclone.nix`)。**forget+prune 被刻意从备份任务中剥离**,由单独的 `restic-prune` systemd timer 每周两次执行,仓库列表自动从 `services.restic.backups` 派生——增删备份仓库时无需同步改 prune 脚本。历史教训:prune 跟着高频备份跑曾造成长达数月的仓库死锁。

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
