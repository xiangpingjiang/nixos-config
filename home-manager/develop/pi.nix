{
  config,
  inputs,
  pkgs,
  ...
}:

# pi coding agent(https://pi.dev,badlogic/pi-mono)。和 codex 一样取 llm-agents 的包,
# 不用 nixpkgs 的 pi-coding-agent:llm-agents 跟上游更紧,且有 cache.numtide.com 的 binary cache。
# settings / models / keybindings 都没写:留空时模块不生成对应文件,
# ~/.pi/agent/settings.json 保持可变,pi 里 /model 切换默认模型之类的操作才能落盘。
# 登录态在 ~/.pi/agent/auth.json(pi 自己写),不归这里管。
#
# OpenRouter 免费模型:key 在 sops(secrets/llm-keys.enc.yaml 的 openrouter_api_key),
# wrapper 启动时读进 OPENROUTER_API_KEY。不走 auth.json 的 `"key": "!cat ..."`:
# 那个文件 pi 自己会改写(/login /logout),声明式管它会和 pi 抢。
# 这把 key 累计充值过 $10,免费模型每天 1000 次、20 RPM,整个账号共用。
# 默认模型写在可变的 settings.json 里(手动设成 nemotron-3-ultra:free),没在这里钉:
# 钉成 --model 参数会让 /model 切换永远被启动参数盖掉。
# 别把默认模型设成 openrouter/free:它随机路由,实测会落到 inkling:free 这类
# "only available on agentic harnesses" 的模型直接 403。
let
  piUnwrapped = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  piWrapped = pkgs.symlinkJoin {
    name = "pi-${piUnwrapped.version}";
    inherit (piUnwrapped) version meta;
    paths = [ piUnwrapped ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    # 已经 export 过就不覆盖;sops-nix 还没解密(文件不存在)时静默跳过,其它 provider 照常用。
    postBuild = ''
      wrapProgram $out/bin/pi --run '
        if [ -z "''${OPENROUTER_API_KEY:-}" ] && [ -r ${config.sops.secrets.openrouter_api_key.path} ]; then
          OPENROUTER_API_KEY=$(< ${config.sops.secrets.openrouter_api_key.path})
          export OPENROUTER_API_KEY
        fi'
    '';
  };
in
{
  programs.pi-coding-agent = {
    enable = true;
    package = piWrapped;
  };

  # MCP 直接复用 Claude Code 那份声明(programs.claude-code.mcpServers),pi 的 mcp.json 和它
  # 同一个 mcpServers 形状,不用转换。hm 的 pi 模块没有 mcp 选项,所以自己写 home.file。
  # 代价:文件是只读的 store 链接,pi 里 /mcp 切 exposure、启用/禁用这类会写回 mcp.json 的操作
  # 存不下来;`pi mcp add` 同理。要加 server 就加在 claude-code 那边,两边一起生效。
  # 工具名在 pi 里是 `mcp__chrome__<tool>`,不是 Claude Code 的 `mcp__plugin_hm_chrome__<tool>`。
  home.file.".pi/agent/mcp.json".text = builtins.toJSON {
    mcpServers = config.programs.claude-code.mcpServers;
  };
}
