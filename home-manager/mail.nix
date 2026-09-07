{
  config,
  pkgs,
  ...
}:

let
  # QQ 邮箱地址(主地址,数字@qq.com)。IMAP/SMTP 的 SASL username 必须明文写在配置里
  # ——himalaya v2 只给密码留了 command 变体(password.command),username 没有,
  # 所以这一项没法进 sops。真正的凭证(授权码)在 secrets/qq-mail.enc.yaml。
  # foxmail 别名 / 英文别名收信没问题,但登录用的仍是这个主地址。
  qqAddress = "825717414@qq.com";

  # 授权码从 sops 解出的文件里读。这是"IMAP/SMTP 服务授权码",不是 QQ 密码:
  # QQ 邮箱设置 → 账户 → IMAP/SMTP 服务 → 生成授权码。
  # 用 coreutils 的绝对路径:这个字符串由 himalaya 交给 shell 执行,不保证 PATH 里有什么。
  authcodeCmd = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.qq_mail_authcode.path}";

  tomlFormat = pkgs.formats.toml { };
in
{
  # 故意不用 home-manager 的 programs.himalaya 模块,配置文件自己生成。原因:
  # 那个模块(modules/programs/himalaya.nix)生成的是 himalaya v1 的 schema
  # ——`backend.type = "imap"` / `backend.auth.cmd` / `folder.aliases` /
  # `message.send.backend.*`,而 nixpkgs 里的 himalaya 已经是 2.0.0,schema 换成了
  # `imap.server` / `imap.sasl.plain.password.command` / `mailbox.alias.*`,两边对不上。
  # 连"绕过 accounts.email、只写 programs.himalaya.settings"这条路也是死的:模块里
  # `allConfig = globalConfig // { accounts = accountsConfig; }`,settings 里写的
  # accounts 会被 accounts.email 派生出来的(这里是空的)整体覆盖掉。
  #
  # v2 的另外两个变化(用之前要知道):
  #   - 账户级的 `email` / `display-name` 配置项没了,[message.composer.*] 整块也被移除。
  #     himalaya 现在是低层工具,From 头由写信时自己给(或交给 mml 之类的工具)。
  #   - 裸跑 `himalaya`(不带子命令)是配置向导,不再是列信件;列信件用 `himalaya envelope list`。
  # 发信要自己给完整的 RFC 5322:himalaya 一个头都不补(它也不写 X-Mailer /
  # User-Agent),QQ 只补 Message-ID 和 Received,所以少写就是真的没有——漏了 Date
  # 会让 Sent 列表的 DATE 列空着,漏 MIME-Version 还会在收件方的反垃圾评分上扣分。
  # 用 python 的 email 库而不是 printf 拼:中文主题要按 RFC 2047 编码、正文要挑
  # base64/quoted-printable,手拼很容易发出裸 UTF-8 的不合规邮件,EmailMessage
  # 这些连 MIME-Version / Content-Type 一起自动补齐。显示名固定用 Pingjiang Xiang。
  #
  #   python3 - <<'PY' | himalaya message send
  #   from email.message import EmailMessage
  #   from email.utils import formatdate
  #   m = EmailMessage()
  #   m['From'] = 'Pingjiang Xiang <825717414@qq.com>'
  #   m['To'] = 'someone@example.com'
  #   m['Subject'] = '主题'
  #   m['Date'] = formatdate(localtime=True)
  #   m.set_content('正文\n')
  #   print(m.as_string(), end='')
  #   PY
  #
  # Message-ID 不用自己给:QQ 会补一个 <tencent_...@qq.com>,自己生成反而会把本机
  # 主机名写进去。
  home.packages = [ pkgs.himalaya ];

  xdg.configFile."himalaya/config.toml".source = tomlFormat.generate "himalaya-config.toml" {
    accounts.qq = {
      default = true;

      # 裸 host[:port] 会被当成 imaps://,这里把 scheme 写全免得靠默认值猜。
      # QQ 邮箱只提供隐式 TLS 的 993,没有 143+STARTTLS,所以不配 starttls。
      imap = {
        server = "imaps://imap.qq.com:993";
        sasl.plain = {
          username = qqAddress;
          password.command = authcodeCmd;
        };
        # RFC 2971 的 ID 扩展。上游 config.sample.toml 点名 mail.qq.com 要求认证后
        # 立刻来一次 ID 交换。不过本机拿真实授权码实测过:去掉这项,mailbox list /
        # envelope list / message read(SELECT、SEARCH、FETCH)全都正常,所以它不是
        # QQ 邮箱能不能用的前提。留着是因为代价只有认证后多一条 ID 命令,而"不发 ID
        # 被 QQ 拒登"是外界常见报告,实测覆盖不到高频登录/大批量取信那类场景。
        id.auto = true;
      };

      # QQ 邮箱的 465 是隐式 TLS(smtps),587 也开着但走 STARTTLS;这里用 465。
      smtp = {
        server = "smtps://smtp.qq.com:465";
        sasl.plain = {
          username = qqAddress;
          password.command = authcodeCmd;
        };
      };

      # 邮箱别名。v2 里 IMAP 只会自动认 INBOX(其余 special-use 角色上游还没实现发现),
      # 所以 sent/drafts/trash 得手填。下面这几个已用 `himalaya mailbox list` 对着
      # QQ 的实际列表核对过。`inbox` 这里写 INBOX、而服务器报的 id 是 "Inbox":
      # INBOX 是 IMAP 的保留名、大小写不敏感(RFC 3501),实测两种写法都选中同一个。
      # 剩下一个中文的"其他文件夹/QQ邮件订阅"没起别名,要用就 -m 传全名。
      mailbox.alias = {
        inbox = "INBOX";
        sent = "Sent Messages";
        drafts = "Drafts";
        trash = "Deleted Messages";
        junk = "Junk";
      };
    };
  };
}
