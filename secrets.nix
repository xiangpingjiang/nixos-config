{
  ...
}:
{ 
  age.identityPaths = [ "/home/xpj/.ssh/id_ed25519" ];
  age.secrets.restic_repository.file = ./secrets/restic_repository.age;
  age.secrets.mihomo_config.file = ./secrets/mihomo_config.age;
}
