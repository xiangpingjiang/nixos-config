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
          user = "rclone_kp";
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

      "kp_infini" = {
        config = {
          type = "webdav";
          url = "https://hakata.infini-cloud.net/dav/"; # WebDAV 服务器地址
          vendor = "other";
          user = "cola_xiang";
        };
        secrets = {  pass = config.age.secrets.rclone_kp_infini.path;};
      };
    };
  };
}
