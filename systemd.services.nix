{
  ...
}:

{
  # systemd.services.aliyunpan-sync = {
  #   description = "aliyunpan sync";
  #   wantedBy = [ "basic.target" ];
  #   # 脚本的绝对路径
  #   script = ''
  #     # 定义函数
  #     create_folder() {
  #         if [ ! -d "$1" ]; then
  #             mkdir -p "$1"
  #             echo "创建文件夹: $1"
  #         else
  #             echo "文件夹已存在: $1"
  #         fi
  #     }

  #     # 使用函数
  #     create_folder "/home/xpj/.config/aliyunpan/"
  #     create_folder "/home/xpj/Documents/sync"
  #     export ALIYUNPAN_VERBOSE=1
  #     # 配置环境变量
  #     export ALIYUNPAN_CONFIG_DIR=/home/xpj/.config/aliyunpan/
  #     #todo 第一次执行一定失败，需要先登录
  #     ${pkgs.aliyunpan}/bin/aliyunpan sync start -ldir "/home/xpj/Documents/sync" -pdir "/sync_drive/" -mode "upload"
  #   '';
  #   serviceConfig = {
  #     RestartSec = 5;
  #   };
  # };

}
