let
  my_user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzxijLWHR3Xpf1r/xcmqhCkVUh5F62VbBNLdNuDE7oF xpj@nixos";
in
{
  "rclone_kp_cst.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "rclone_kp_nutstore.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "rclone_kp_infini.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "restic_repository.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "openclaw_channel_telegram.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "zai_api_key.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

  "deepseek_api_key.age" = {
    publicKeys = [ my_user ];
    armor = true;
  };

}
