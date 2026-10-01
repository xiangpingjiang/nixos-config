{
  ...
}:
{
  age.identityPaths = [ "/home/xpj/.ssh/id_ed25519" ];
  age.secrets.restic_repository.file = ./secrets/restic_repository.age;

  # sops-nix：用与 agenix 相同的 SSH 私钥解密
  sops.age.sshKeyPaths = [ "/home/xpj/.ssh/id_ed25519" ];
  # 部分加密的 YAML（# sops:enc），key = "" 表示解密整个文件供 mihomo 使用
  sops.secrets.mihomo_config = {
    sopsFile = ./secrets/mihomo.enc.yaml;
    format = "yaml";
    key = "";
  };
  # 同一份文件里单独再取 secret 这一个 key，给 netloc 读控制接口用。
  # 这样密钥只有一个来源（mihomo 配置本身），不需要两处同步。
  # mihomo 服务跑在 DynamicUser 下、通过 LoadCredential 拿整份配置，与这条互不影响。
  sops.secrets.mihomo_secret = {
    sopsFile = ./secrets/mihomo.enc.yaml;
    format = "yaml";
    key = "secret";
    mode = "0400";
    owner = "xpj";
  };
}
