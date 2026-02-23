{
  config,...
}:
{

  programs.rclone = {
    enable = true;
    remotes = {
      "kp_cst" = {
        config = {
          type = "webdav";
          url = "https://data.cstcloud.cn/dav"; # WebDAV 服务器地址
          vendor = "other";
          user = "xpj1";
        };
        secrets = {  pass = config.age.secrets.rclone_kp_cst.path;};
      };
      "kp_nutstore" = {
        config = {
          type = "webdav";
          url = "https://dav.jianguoyun.com/dav"; # WebDAV 服务器地址
          vendor = "other";
          user = "825717414@qq.com";
        };
        secrets = {  pass = config.age.secrets.rclone_kp_nutstore.path;};
      };
    };
  };
}
