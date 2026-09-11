---
name: local-pdf-env
version: 1.0.0
description: >
  本机（NixOS）PDF 工具链的环境事实：装了哪些工具、各管哪一段、该抄哪条命令、
  哪些操作在无图形会话里做不了。当任务涉及读取、抽取、转换、渲染、拆分、合并、
  旋转、删页、加解密、检查修复、批注或签名 PDF 文件时读本文件。
  也包含"不要装什么"——止住"我来装个 PDF 库"的冲动。
---

# 本机 PDF 环境

> **边界声明**：本文件**只讲本机装了什么、行为差异和坑**。
> 具体某个工具的完整参数以它自己的 `--help` / man 为准，本文件不复述。

## 先看这条：读 PDF 内容优先用 Read 工具

`Read` 工具能直接翻 PDF 页（`pages` 参数，如 `"1-5"`，单次最多 20 页；超过 10 页的
PDF 必须传 `pages`）。**要理解文档内容时先用它**，不要习惯性 shell out。

`pdftotext` 是这几种情况才用：需要**保留版面**（`-layout`）、要对**全文 grep**、
页数多到不适合逐页读、或者要把文本落成文件给后续步骤。

## 五段职责，彼此不重叠

按交互范式分层：三个 GUI 各自的鼠标语义互斥（选文本 / 画笔 / 搬页面），两个 CLI 要求无界面。

| 工具 | 管什么 | 来源 |
|---|---|---|
| `okular` | 阅读 + 标准注释（高亮、便笺、图章、内嵌文本框）、填 AcroForm 表单、查验数字签名。也是 EPUB / DjVu / CBZ / PS / TIFF 的查看器 | **随 plasma6 进系统 profile**，不在 `home.packages` |
| `xournalpp` | 手写笔迹、手签名。把 PDF 当背景纸，导出时把笔迹压平进 PDF | `home.packages` |
| `pdfarranger` | 页面级操作的交互式版本：缩略图里拖拽删页、调序、旋转、裁剪、拆分、拼接 | `home.packages` |
| `qpdf` | 页面级操作的脚本化版本 + 结构层维护。页面内容按字节无损搬运 | `home.packages` |
| `poppler-utils` | 把内容取出来：`pdftotext` / `pdftoppm` / `pdfimages` / `pdfinfo` / `pdftocairo` | `home.packages` |
| `mutool`（`mupdf-headless`） | 救援与补位。见下方"qpdf 读不进来时" | `home.packages` |

## 能直接抄的命令

```bash
pdfinfo in.pdf                          # 页数、页面尺寸、是否加密、元信息
pdftotext -layout in.pdf out.txt        # 保留版面抽文本（去掉 -layout 是纯文本流）
pdftotext -f 3 -l 5 in.pdf -            # 只抽第 3-5 页，输出到 stdout
pdftoppm -r 150 -png in.pdf page        # 每页渲成 page-01.png…（给视觉检查用）
pdfimages -all in.pdf img               # 抽出内嵌原图，不做重编码
pdftocairo -svg -f 1 -l 1 in.pdf o.svg  # 单页转 SVG

qpdf --check in.pdf                     # 诊断结构：哪里坏、坏成什么样（可读性最好的诊断）
qpdf --json in.pdf                      # 内部结构导出成 JSON
qpdf in.pdf --pages . 1-3,7 -- out.pdf  # 取第 1-3 和第 7 页
qpdf --empty --pages a.pdf b.pdf -- out.pdf   # 合并
qpdf --rotate=+90:2 in.pdf out.pdf      # 只转第 2 页
qpdf --decrypt --password=xx in.pdf out.pdf   # 去密码（需知道密码）
qpdf --linearize in.pdf out.pdf         # 线性化，网页首屏快

mutool clean broken.pdf fixed.pdf       # 救援：重写整份文件（不要带 -g，见下）
mutool clean -ggg in.pdf out.pdf        # -ggg 是「整理压缩」（去未引用对象、合并重复），
                                        # 不是修复开关，而且会重排对象编号 → 救援时别用
mutool bake in.pdf out.pdf              # 把表单字段和已有注释压平进页面内容
```

**`Syntax Warning: Invalid Font Weight` 之类的 poppler 警告是噪音**，忽略即可。
`pdftotext` / `pdftoppm` 在正常文件上也常打这一行，退出码仍是 0、输出完好，
**不代表文件有问题，不要拿它当错误去排查**。判断成不成功看退出码和产出物。

**qpdf 报读不进来时**：换 `mutool clean` 试一次。分工是
**mutool 擅长把坏文件读进来，qpdf 擅长告诉你它哪里坏了**——两个都试，不是二选一。
mutool 另有 `draw` / `convert` / `merge` / `extract` / `show` / `grep` / `sign` /
`poster` / `recolor` / `trim` / `audit` 等子命令，功能上覆盖 poppler-utils 全部和 qpdf 大半，
但**选项晦涩、上游手册薄**，所以默认走 qpdf + poppler-utils，mutool 只作救援和补位。

## 三个 GUI 需要图形会话

`okular` / `xournalpp` / `pdfarranger` 都要 Wayland/X 会话。**在子代理、`cc-connect`
（飞书 bot）这类没有桌面的上下文里不要调用**——会挂住或直接失败。那些场合只用
`qpdf` / `poppler-utils` / `mutool`。

需要给用户看渲染结果时：`pdftoppm -png` 出图，再用 `Read` 看那张 PNG，不要试图开 GUI。

## okular 的三个事实

**1. 批注默认不写进 PDF。** 存在 `~/.local/share/okular/docdata/`，文件发给别人他看不到。
要嵌进去必须在 okular 里走「文件 → 另存为」。所以**用户说"我批注过了"但 PDF 里没有注释时，
先怀疑这个，不要怀疑文件坏了**。

**2. 命令行参数只管怎么打开，不做任何处理。** 全部选项：`-p <页码>` / `--find <串>` /
`--presentation` / `--print` / `--print-and-exit` / `--unique` / `--noraise`，以及 `-` 读 stdin。
**没有任何导出/转换选项**——想要无头输出一律走 CLI 工具。

**3. 有 D-Bus，能操控已开着的窗口。** 服务名 `org.kde.okular-<pid>`，对象 `/okular`，
接口 `org.kde.okular`：

```bash
# 注意进程名是 .okular-wrapped（makeWrapper 的产物），pgrep -x okular 抓不到
svc=org.kde.okular-$(pgrep -x .okular-wrapped | head -1)
busctl --user call $svc /okular org.kde.okular currentDocument   # 当前打开的文件
busctl --user call $svc /okular org.kde.okular pages             # 总页数
busctl --user call $svc /okular org.kde.okular goToPage u 12     # 跳页
busctl --user call $svc /okular org.kde.okular reload            # 外部改写后重载
```

`reload` 配合 `qpdf` 改完立刻刷新视图很顺手。还有 `openDocument s <path>`、`currentPage`、
`documentMetaData s Title`、`slotNextPage` 等。**`openDocument` 会换掉用户正在看的文档**，
动手前先 `currentDocument` 看清楚。

## 本机没有的能力：改正文文字和排版

这台机器上**没有**能改 PDF 正文文字/重排版面的工具，Linux 上也没有好的免费方案。
用户提这类需求时说清现状，给这两条将就路线，然后**停下**：

- `libreoffice`（未装）的 Draw 能把 PDF 当矢量图逐段改，但字体一定会重排，只适合改几个字。
- 真要排版级编辑只有商业软件。

**不要做这些事**（一半的价值在这里）：

- 不要提议装 `masterpdfeditor`——unfree，且免费版保存会打水印。
- 不要提议装 `stirling-pdf`——它是个常驻 web 服务（nixpkgs 里有 `services.stirling-pdf`），
  内部调的就是 qpdf / ghostscript / LibreOffice / tesseract，是这些工具的前端而不是替代品。
  为偶发的本机需求养一个服务不值。
- 不要用 `ghostscript` 做日常处理——它会重新解释并重编码页面内容（有损、字体可能被替换）。
  只在压体积和救顽固文件时考虑，且要说明代价。
- 不要 `pip install pypdf` / `npm i pdf-lib` 之类临时装库。需要脚本化就用上面的 CLI；
  真需要库，让用户加进 `home.packages`。

## OCR 未装

扫描件转可搜索文本要 `ocrmypdf`，**当前没装**。需要时告诉用户加进 `home.packages`，
并提醒它的中文识别依赖 tesseract 的 `chi_sim` 语言包，装完先跑一次
`ocrmypdf -l chi_sim` 验证语言包是否到位。

## 工具都由 nix 管理

上面每个工具都由 `home-manager/home.nix` 的 `home.packages` 声明，`okular` 由
`services.nix` 的 plasma6 带入。**不要用 pip / npm / brew / curl 安装或升级它们**——
装了会被下次 rebuild 覆盖，而且绕过声明式配置。需要新工具就告诉用户改配置。

顺带：给 okular 补装 `kdePackages.okular` 是错的，会装第二份。
