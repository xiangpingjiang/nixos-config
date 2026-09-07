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
}
