"""cc-sessions 的渲染器:枚举活跃的 Claude Code 进程,配上标题和状态,输出整块面板文本。

进程 → sessionId 的配对有两条路,优先走前者:

1. Claude Code 2.1.266 起自己在 ~/.claude/sessions/<pid>.json 写了边车文件,里面
   直接有 sessionId / cwd / status,`procStart`(= /proc/<pid>/stat 的 starttime)
   可以用来防 pid 复用。确定性映射,没有猜的成分。
2. 旧版本没有那个文件,退回下面这条单向约束的启发式认领。

启发式(fallback)靠的是:
transcript(~/.claude/projects/<slug>/<sessionId>.jsonl)一定由某个 claude 进程创建,
所以它的首条记录时间必然晚于该进程的启动时间。于是同一 cwd 下按启动时间升序,
每个进程认领「首条时间晚于自己、且还没被别人认领」的最早那个文件即可。
resume 出来的会话命令行里直接带 sessionId,先占位,不参与这轮认领。
已知错配:一个会话 /clear 之后会留下两个都满足约束的文件,若同 cwd 还有个启动更晚的
新会话,它会认领到本该属于前者的第二个文件。罕见,不为它加复杂度。
"""

import json
import os
import re
import sys
import time
import unicodedata
from datetime import datetime

CLK = os.sysconf("SC_CLK_TCK")
PROJECTS = os.path.expanduser("~/.claude/projects")
# Claude Code 2.1.266 起每个会话在这里写一份 <pid>.json(sessionId / cwd / status / procStart)
SESSIONS = os.path.expanduser("~/.claude/sessions")
# 标题缓存在 tmpfs 上,重启即失。aiTitle 一旦生成基本不变,不缓存就得每轮全文扫每个 jsonl
CACHE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "cc-sessions")

DIM = "\033[2m"
BOLD = "\033[1m"
OFF = "\033[0m"
GREEN = "\033[32m"
YELLOW = "\033[33m"


def dwidth(s):
    """终端显示宽度:中日韩字符占两列,不算这个右对齐会歪。"""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def trunc(s, limit):
    if dwidth(s) <= limit:
        return s
    out, used = "", 0
    for c in s:
        cw = 2 if unicodedata.east_asian_width(c) in "WF" else 1
        if used + cw > limit - 1:
            break
        out += c
        used += cw
    return out + "…"


def pad(s, limit):
    return s + " " * max(0, limit - dwidth(s))


def boot_epoch():
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("btime "):
                return int(line.split()[1])
    return 0


def iso_epoch(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def read_small(path, size=4096):
    """读 /proc 下的小文件。1s 一刷时这条路径被走近 2000 次,内建 open() 的
    TextIOWrapper + 缓冲 + 解码开销在这个量级上很显眼(实测慢一倍)。"""
    fd = os.open(path, os.O_RDONLY)
    try:
        return os.read(fd, size)
    finally:
        os.close(fd)


_WIN_CACHE = {}


def tty_of(pid):
    """终端会话的 tty,用来在一堆"终端"里定位是哪个 pane。"""
    try:
        target = os.readlink("/proc/%d/fd/0" % pid)
    except OSError:
        return None
    if target.startswith("/dev/pts/") or target.startswith("/dev/tty"):
        return target[len("/dev/"):]
    return None


def window_of(pid):
    """extension host 继承的日志 fd 路径里带 window<N>,这是进程到 VS Code 窗口的唯一映射。

    父进程的 cwd 是 VS Code 主进程启动时的目录,所有窗口都一样,不能用。
    """
    if pid in _WIN_CACHE:
        return _WIN_CACHE[pid]
    d = "/proc/%d/fd" % pid
    try:
        names = os.listdir(d)
    except OSError:
        return None
    for n in names:
        try:
            target = os.readlink(os.path.join(d, n))
        except OSError:
            continue
        m = re.search(r"/logs/[^/]+/window(\d+)", target)
        if m:
            _WIN_CACHE[pid] = m.group(1)
            return m.group(1)
    return None


def sidecar(pid, jiffies):
    """读 ~/.claude/sessions/<pid>.json。拿不到就返回 None,由调用方退回启发式认领。

    进程退出时这个文件不一定被清掉,而 pid 是会复用的,所以必须核对 procStart
    (json 里是字符串形式的 /proc/<pid>/stat starttime)——只按 pid 取会张冠李戴。
    另外别拿这个文件的 mtime 当心跳:实测卡在启动对话框的会话 updatedAt 三小时没动。
    """
    try:
        with open(os.path.join(SESSIONS, "%d.json" % pid), errors="replace") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if str(d.get("procStart")) != str(jiffies):
        return None
    return d


def procs(boot):
    out = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            comm = read_small("/proc/%d/comm" % pid, 64).strip()
            # 终端里装出来的是 makeWrapper 的 bash 脚本,进程名成了 .claude-wrapped
            if comm not in (b"claude", b".claude-wrapped"):
                continue
            exe = os.readlink("/proc/%d/exe" % pid)
            cwd = os.readlink("/proc/%d/cwd" % pid)
            argv = (
                read_small("/proc/%d/cmdline" % pid, 65536)
                .decode("utf-8", "replace")
                .split("\0")
            )
            stat = read_small("/proc/%d/stat" % pid, 4096).decode("utf-8", "replace")
        except OSError:
            continue  # 进程在读的过程中退出了

        # comm 本身可能含空格和括号,只能从最后一个 ')' 之后切;starttime 是去掉 pid/comm 后的第 20 项
        fields = stat.rpartition(")")[2].split()
        if fields and fields[0] == "Z":
            continue  # 僵尸进程:/proc 条目还在,人已经没了
        try:
            ppid = int(fields[1])
            jiffies = int(fields[19])
            start = boot + jiffies / CLK
        except (IndexError, ValueError):
            continue

        sid = None
        for a in argv:
            if a.startswith("--resume="):
                sid = a.split("=", 1)[1]
                break

        # 边车文件是确定性的,压过命令行和启发式:新会话的命令行里本来就没有 sessionId
        car = sidecar(pid, jiffies)
        if car:
            sid = car.get("sessionId") or sid
            # transcript 目录的 slug 用的是 Claude 自己记下的 cwd,以它为准
            cwd = car.get("cwd") or cwd

        vscode = "anthropic.claude-code" in exe
        out.append(
            {
                "pid": pid,
                "cwd": cwd,
                "start": start,
                "sid": sid,
                # 只有 entrypoint 为 cli 的会话有 status,VS Code 那些一律没有,
                # 所以状态仍然以 transcript 的 stop_reason 为主,这里只兜"读不出来"的情况
                "car_status": (car or {}).get("status"),
                "vscode": vscode,
                "win": window_of(ppid) if vscode else None,
                "tty": None if vscode else tty_of(pid),
            }
        )
    return out


def slug(cwd):
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


# 首条真实记录之前有若干没有 timestamp 的元数据行(mode / permission-mode /
# atis-latch / bridge-session / file-history-snapshot ...),行数不固定、随版本增加,
# 实测首条带 timestamp 的记录已经退到第 6 行。窗口写死过小的后果是 first_epoch 返回 None、该 transcript
# 压根不进认领池,新会话(命令行里没有 sessionId)于是永远显示"尚未对话"。
# 元数据行都只有几百字节,所以放宽行数很便宜;字节上限只为兜住畸形文件。
FIRST_SCAN_LINES = 40
FIRST_SCAN_BYTES = 256 * 1024


def first_epoch(path):
    """首条带 timestamp 的记录时间。前面的元数据行没有 timestamp,一律跳过。"""
    try:
        with open(path, errors="replace") as f:
            seen = 0
            for _ in range(FIRST_SCAN_LINES):
                line = f.readline()
                if not line:
                    break
                try:
                    d = json.loads(line)
                except ValueError:
                    d = {}
                got = iso_epoch(d.get("timestamp"))
                if got:
                    return got
                seen += len(line)
                if seen > FIRST_SCAN_BYTES:
                    break
    except OSError:
        pass
    return None


def title_of(sid, path):
    cf = os.path.join(CACHE, sid + ".title")
    try:
        with open(cf) as f:
            cached = f.read().strip()
        if cached:
            return cached
    except OSError:
        pass

    found = None
    try:
        with open(path, errors="replace") as f:
            for line in f:
                # 先按字符串预筛,绝大多数行都不用解析
                if '"ai-title"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("aiTitle"):
                    found = d["aiTitle"]  # 标题会更新,取最后一条
    except OSError:
        pass

    if found:
        try:
            os.makedirs(CACHE, exist_ok=True)
            with open(cf, "w") as f:
                f.write(found)
        except OSError:
            pass
    return found


# 单条记录能到 100KB+,倒读的窗口上限得远大于它;超了还没找到就认作状态未知
TAIL_CAP = 4 * 1024 * 1024

# 按 ESC 打断时落盘的 user 行。整行只有这个标记 = Claude 停在这儿了(进程还在,
# 但轮次已经结束),必须判成"等你回话"。
INTERRUPT_MARKER = re.compile(r"^\[Request interrupted by user( for tool use)?\]$")


def tail_lines(path):
    """从文件尾部往前产出完整行(bytes)。

    不能像原先那样固定读尾部 16KB:一条 attachment(整份 CLAUDE.md)或大 tool_result
    单行就有 100KB+,窗口全被它吃掉,一行都解析不出来 —— 状态误报成"尚未对话"就是这么来的。
    """
    with open(path, "rb") as f:
        size = f.seek(0, 2)
        pos = size
        carry = b""  # 块边界切开的半行,拼到下一轮(更靠前的块)末尾
        while pos > 0 and size - pos <= TAIL_CAP:
            step = min(65536, pos)
            pos -= step
            f.seek(pos)
            parts = (f.read(step) + carry).split(b"\n")
            carry = parts[0]
            for line in reversed(parts[1:]):
                if line:
                    yield line
        if pos == 0 and carry:
            yield carry


def user_text(d):
    """user 行里的纯文本(拼接所有 text block)。content 可能是 str,也可能是
    block 列表;tool_result 行没有 text block,自然拼出空串。"""
    content = (d.get("message") or {}).get("content")
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    return "".join(
        b.get("text") or ""
        for b in content
        if isinstance(b, dict) and b.get("type") == "text"
    ).strip()


def state_of(path):
    """从尾部倒推谁的回合。跳过 attachment / ai-title / tool_result 这类噪音行。"""
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        return None, None

    try:
        for raw in tail_lines(path):
            # 按字节子串预筛:尾部大多是 attachment / ai-title,不必为它们 parse 100KB
            if b'"type":"user"' not in raw and b'"type":"assistant"' not in raw:
                continue
            try:
                d = json.loads(raw)  # 直接喂 bytes;块边界切碎的半行解析失败即丢
            except ValueError:
                continue
            kind = d.get("type")
            if kind not in ("user", "assistant"):
                continue
            if kind == "assistant":
                # 一条 assistant 消息的每个 content block 是分行写的(thinking 一行、
                # text 一行、tool_use 一行),但同一条消息的所有行带同一个 stop_reason。
                # 所以只能看 stop_reason:按"这一行有没有 tool_use block"判的话,
                # 运行中的会话尾部常常正好停在 thinking / text 那一行,会误报成"等你回话",
                # 状态在 ●/○ 之间反复跳,每跳一次还白触发一次重绘。
                reason = (d.get("message") or {}).get("stop_reason")
                if reason in (None, "tool_use", "pause_turn"):
                    return "running", mtime  # None = 还在流式落盘
                return "waiting", mtime
            # user 行大多是真实输入或 tool_result,都算 Claude 的回合;唯一的例外是
            # 打断标记。判定必须是"整行文本恰好等于标记"——打断后立刻又输入时,标记
            # 和新输入落在同一条 user 消息里(`[Request interrupted by user] 还在干活吗`),
            # 那种是真的在跑,用子串/前缀匹配就会把它误判成等你回话。
            if INTERRUPT_MARKER.match(user_text(d)):
                return "waiting", mtime
            return "running", mtime
    except OSError:
        pass
    return None, mtime


def age(secs):
    """粒度刻意做粗:面板靠内容比对决定要不要重绘,每分钟一变就等于每分钟闪一次。

    刷新频率(1s)和这个粒度是两件事:前者决定状态变化多快被看到,后者决定重绘多频繁。
    """
    m = int(secs // 60)
    if m < 1:
        return ""
    if m < 5:
        return "1m"
    if m < 60:
        return "%dm" % (m // 5 * 5)
    return "%dh" % (m // 60)


def resolve(sessions):
    """给每个进程配上 sessionId。sessions 是同一个 cwd 下的进程列表。"""
    d = os.path.join(PROJECTS, slug(sessions[0]["cwd"]))
    try:
        files = [f for f in os.listdir(d) if f.endswith(".jsonl")]
    except OSError:
        return

    taken = {s["sid"] for s in sessions if s["sid"]}
    pool = []
    for name in files:
        sid = name[: -len(".jsonl")]
        if sid in taken:
            continue
        ts = first_epoch(os.path.join(d, name))
        if ts:
            pool.append((ts, sid))
    pool.sort()

    for s in sorted(sessions, key=lambda x: x["start"]):
        if s["sid"]:
            continue
        for i, (ts, sid) in enumerate(pool):
            if ts >= s["start"]:
                s["sid"] = sid
                pool.pop(i)
                break


MARK_W = 16  # 状态列的显示宽度,最长的是"○ 等你回话 10h"(14 列)


def mark_of(p, now):
    """返回(带色, 纯文本)两份:前者拿去打印,后者拿去算宽度。"""
    if p["state"] == "running":
        return GREEN + "●" + OFF + " 运行中", "● 运行中"
    if p["state"] == "waiting":
        waited = age(now - p["mtime"]) if p["mtime"] else ""
        text = "○ 等你回话" + ((" " + waited) if waited else "")
        return YELLOW + "○" + OFF + text[1:], text
    if p["talked"]:
        # 配到了 transcript 却读不出状态,和"没配到"是两件事,分开显示
        return DIM + "? 状态未知" + OFF, "? 状态未知"
    # 没有 transcript:panel 开着但一句话都还没说
    return DIM + "· 尚未对话" + OFF, "· 尚未对话"


def main():
    width = int(os.environ.get("CC_WIDTH") or 100)
    now = time.time()
    procs_all = procs(boot_epoch())

    print(BOLD + "Claude Code 会话" + OFF, end="")
    if not procs_all:
        print("\n\n  没有活跃的会话")
        return

    by_cwd = {}
    for p in procs_all:
        by_cwd.setdefault(p["cwd"], []).append(p)
    for group in by_cwd.values():
        resolve(group)

    for p in procs_all:
        p["title"] = p["state"] = None
        p["mtime"] = None
        p["talked"] = False
        if not p["sid"]:
            continue
        path = os.path.join(PROJECTS, slug(p["cwd"]), p["sid"] + ".jsonl")
        # 边车给了 sessionId 但 transcript 还没落盘 —— 会话真的一句话都没说过
        # (实测卡在启动期对话框的会话就是这样)。这种要算"尚未对话",不是"状态未知"
        if not os.path.exists(path):
            continue
        p["talked"] = True
        p["title"] = title_of(p["sid"], path)
        p["state"], p["mtime"] = state_of(path)
        # transcript 读不出状态时,cli 会话还能退回边车里的 status(vscode 那些没有这个字段)
        if p["state"] is None:
            p["state"] = {"busy": "running", "waiting": "waiting"}.get(p["car_status"])

    groups = {}
    for p in procs_all:
        groups.setdefault((p["cwd"], p["win"], p["tty"]), []).append(p)

    print(
        "  %s%d 个会话 / %d 处%s"
        % (DIM, len(procs_all), len(groups), OFF)
    )

    # 右侧固定列:pid(7) + 空格 + sessionId 前 8 位 + 空格 + 起始 HH:MM
    tail_w = 7 + 1 + 8 + 1 + 5
    for key in sorted(groups, key=lambda k: (os.path.basename(k[0]), k[1] or "", k[2] or "")):
        cwd, win, tty = key
        head = "%s%s%s" % (BOLD, os.path.basename(cwd) or cwd, OFF)
        if win:
            tag = "(window%s)" % win
        else:
            tag = "(终端 %s)" % tty if tty else "(终端)"
        print("\n%s %s%s %s%s" % (head, DIM, tag, os.path.dirname(cwd), OFF))

        for p in sorted(groups[key], key=lambda x: x["start"]):
            colored, plain = mark_of(p, now)
            # mark 里混了 ANSI 转义,dwidth 只能拿纯文本那份算,再按差额补空格
            mark = colored + " " * max(1, MARK_W - dwidth(plain))

            room = max(10, width - 2 - MARK_W - tail_w - 2)
            if p["title"]:
                title = pad(trunc(p["title"], room), room)
            else:
                title = DIM + "—" + OFF + " " * (room - 1)

            since = time.strftime("%H:%M", time.localtime(p["start"]))
            sid_short = (p["sid"] or "").split("-")[0] or "        "
            print(
                "  %s%s  %s%7d %s %s%s"
                % (mark, title, DIM, p["pid"], sid_short, since, OFF)
            )


if __name__ == "__main__":
    sys.exit(main())
