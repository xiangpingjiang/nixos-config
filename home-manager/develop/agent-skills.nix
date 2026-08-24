{ ... }:

# Agent Skills 的声明式管理(agent-skills-nix):
# 从任意仓库(flake input 或本地路径)发现含 SKILL.md 的目录并按需装到各 agent 的 skills 目录。
# 相比 programs.claude-code.skills 手写 attrset,这里能一次喂多个来源、多个 agent(codex/opencode/...),
# 并且 skills.enable 是白名单——不写进去的 skill 不会被装,避免上游新增 skill 悄悄进来。
# 文档:https://github.com/Kyure-A/agent-skills-nix
{
  programs.agent-skills = {
    enable = true;

    # dbx 官方 skill,直接取自 flake input 源码(钉死 rev,见 flake.nix 里 dbx 的注释)。
    # 前提:PATH 里的 dbx 是 CLI(见 home.nix 的 dbx-cli/dbx-desktop 命名安排)。
    sources.dbx = {
      input = "dbx";
      subdir = "skills";
    };

    # 飞书官方 skill,来自 larksuite/cli 仓库的 skills/ 目录(上游共 28 个,这里只挑用得上的)。
    # 前提:PATH 里要有 lark-cli(见 home.nix 的 lark-cli overrideAttrs)和 npx
    # (lark-whiteboard 会跑 npx @larksuite/whiteboard-cli)。
    # 不设 idPrefix:目录名必须和 SKILL.md frontmatter 里的 name 一致,加前缀会变成
    # lark/lark-doc 这种嵌套目录,同时打断 skill 之间 ../lark-xxx/ 形式的相对引用。
    sources.lark = {
      input = "lark-skills";
      subdir = "skills";
      # 上游 skill 全在一层,skill 内部的 references/scenes 等子目录不含 SKILL.md。
      # 限死深度只是让发现范围更明确,不影响已选 skill 的内部文件(整个目录都会进 bundle)。
      filter.maxDepth = 1;
    };

    # 本仓库自带的 skill(sourceType 支持 path 作为 input 的替代,见模块 modules/common.nix)。
    # 只放"本机环境事实"这类上游不可能知道的内容:画图工具链装了什么、两个渲染器的差别、
    # npx 的离线行为。绘图规范一律以上游 lark-whiteboard 为准,这里不复述——上游 skill 跟随
    # main 自动更新,自建同主题内容过时后会反向误导。
    # 之所以做成 skill 而不是写进 claude-code 的 context/CLAUDE.md:画图活是委派给 SubAgent 的,
    # 它们跑在隔离上下文里读不到对话和 memory,skill 是唯一能自动到达它们的通道。
    sources.local = {
      path = ./skills;
    };

    # 白名单:只装这里列出的 skill ID(ID 即 subdir 下的相对路径)。
    skills.enable = [
      "dbx"

      # 飞书文档正文操作:读取、创建、编辑,插图、思维笔记。
      "lark-doc"
      # 文档里作图:画板。scenes/ 下覆盖流程图、泳道、组织架构、鱼骨、漏斗、
      # 金字塔、柱状/折线图、treemap 等,routes/ 支持 mermaid 和 svg 输入。
      # lark-doc 的画板工作流直接引用它的 reference,是硬依赖。
      "lark-whiteboard"
      # 所有 lark-* skill 的底座(认证、user/bot 身份、权限、JSON 输出契约)。
      # lark-doc 的 metadata.requires.skills 明确列了它,每个 skill 开头也都写着
      # "MUST 先读 ../lark-shared/SKILL.md"——不装的话上面两个都跑不起来。
      "lark-shared"
      # 造自定义 skill 的脚手架。用来把画图的踩坑经验沉淀成项目级 skill
      # (design token、组件模板、画板 raw JSON 的写回约定),不再靠每次 prompt 口传。
      "lark-skill-maker"

      # 本机画图环境事实(见上方 sources.local)。名字故意不带 lark- 前缀:
      # 它不是飞书官方 skill,别让人误以为是上游文件的一部分。
      "local-diagram-env"
    ];

    targets.claude = {
      enable = true;
      # structure 用 link(走 home.file 逐文件符号链接),不用默认的 symlink-tree:
      # symlink-tree 在 home.activation 里跑 `rsync -a --delete`,会要求 ~/.claude/skills
      # 带 .agent-skills-managed.json 标记才肯接管已有的非空目录,且它与 home-manager 自己的
      # linkGeneration 都挂在 writeBoundary 之后、先后顺序不定。link 模式行为和原来一致,没这些问题。
      structure = "link";
      # link 模式要求静态路径。默认值 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" 会走模块里
      # 一段正则回退提取 fallback 并打 trace,这里直接写死(我们没用 CLAUDE_CONFIG_DIR)。
      dest = ".claude/skills";
    };
  };
}
