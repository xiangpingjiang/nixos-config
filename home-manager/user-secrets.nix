{
  ...
}:
{
  age.secrets.rclone_kp_cst.file = ../secrets/rclone_kp_cst.age;

  age.secrets.rclone_kp_nutstore.file = ../secrets/rclone_kp_nutstore.age;

  age.secrets.rclone_kp_infini.file = ../secrets/rclone_kp_infini.age;

  # sops-nix(用户级)——与 agenix 共用同一把 SSH 私钥解密。
  # 解出来的明文落在 ~/.config/sops-nix/secrets/<name>(实际是 $XDG_RUNTIME_DIR 下的
  # tmpfs,重启即失),由 sops-nix.service 在登录/激活时写入。
  sops.age.sshKeyPaths = [ "/home/xpj/.ssh/id_ed25519" ];

  # cc-connect 的飞书自建应用凭证,见 develop/cc-connect.nix
  sops.secrets.cc_feishu_app_id = {
    sopsFile = ../secrets/cc-connect.enc.yaml;
    key = "feishu_app_id";
  };
  sops.secrets.cc_feishu_app_secret = {
    sopsFile = ../secrets/cc-connect.enc.yaml;
    key = "feishu_app_secret";
  };

  # QQ 邮箱的 IMAP/SMTP 授权码(不是 QQ 密码),给 himalaya 用,见 mail.nix。
  # 改这个值要 `sops secrets/qq-mail.enc.yaml` 之后重新 switch:
  # .enc.yaml 是在 eval 期被复制进 store 的,不 switch 只 restart sops-nix 拿不到新值。
  sops.secrets.qq_mail_authcode = {
    sopsFile = ../secrets/qq-mail.enc.yaml;
    key = "qq_mail_authcode";
  };
}
