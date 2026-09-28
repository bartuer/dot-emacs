#!/usr/bin/env python3
"""orch-collect — one JSON row per GHCP CLI session on THIS box.

Plan 35 item 2.1 (schema: bin/sessions.schema.json, sources:
.github/REPL/fix.archive/session-telemetry.md).  Runs as root from
orch-collect.timer every 30s and writes /run/orch/sessions.json.

WHY PYTHON, NOT THE PLAN'S `orch-collect.sh`.  Every source here is JSON
(events.jsonl, *.response.json, server.jsonl); in shell that is a jq pipeline
per column, i.e. the "Python wearing a shell costume" the bin/ rule forbids.
It is ONE box, no fan-out, so it is not a fleet.py verb either -- the fleet
half is `recipes.sh sessions`, which only reads this file.

:*** PRIVATE.  0600 root.  NEVER the banner (33-D3). ***  Rows carry session
names (often the user's prompt verbatim) and HITL question text.

Sources, all MEASURED on cj07 2026-09-26:
  live      inuse.<pid>.lock exists AND /proc/<pid>/cmdline has "copilot"
            (a stale lock survives an abort -- the lock alone lies).
  tokens    L-server request file's system prompt holds
            "session-state/<uuid>" -> exact attribution (0.000% error over
            12 requests / 260k tokens, two concurrent sessions).  Usage is
            in the sibling *.response.json.  CLI's own modelMetrics are 0
            under BYOK, so L-server is the ONLY token source.
  hitl      ask_user tool.execution_start with no matching _complete, or a
            permission.requested not yet followed by permission.completed.
            The folder-trust prompt fires BEFORE events.jsonl exists, so a
            live NOLOG row reports hitl.pending = null (unknown), not false.
  commits   repo-scoped, NOT per session: headCommit (session.start) ..HEAD.

Bounded probes (28 1.1) without a timeout (R-AWAIT): every probe is a local
file read; the lserver liveness test reads /proc/net/tcp instead of dialling
the port, so a wedged listener cannot hang the tick.  The only subprocess is
local `git` with GIT_OPTIONAL_LOCKS=0, which takes no lock.

--watch (plan 39 A): stay resident, stat-sweep every 1s, fold only appended
events.jsonl bytes, refresh tokens + git every 30s, and print NDJSON on stdout:
{"t":"snap","host":..,"doc":<v1 doc>} at start and on change, {"t":"hb"} every
15s.  Writes NOTHING to disk.  Meant to be shipped over ssh on stdin:
    ssh -o BatchMode=yes <box>wsl python3 - --watch < bin/orch-collect.py
Test overrides: ORCH_STATE_GLOBS (':'-list), ORCH_TICK_S, ORCH_HB_S, ORCH_HEAVY_S.
"""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
import time

OUT = os.environ.get("ORCH_OUT", "/run/orch/sessions.json")
INDEX = os.environ.get("ORCH_INDEX", "/run/orch/lserver-index.json")
LDIR = os.environ.get("L_PROMPT_DIR", "/workspace/L-server")
LPORT = int(os.environ.get("ORCH_LSERVER_PORT", "11434"))
STATE_GLOBS = os.environ.get(
    "ORCH_STATE_GLOBS", "/root/.copilot/session-state:/home/*/.copilot/session-state").split(":")
SID_RE = re.compile(rb"session-state/([0-9a-f-]{36})")
SCHEMA = 1
# room.py SECRET (39-D13): copied, not imported -- this file ships over ssh
# on stdin with no repo beside it.  last_msg is scrubbed before output.
SECRET = re.compile(r"BEGIN [A-Z ]*PRIVATE KEY|\bgh[pousr]_[A-Za-z0-9]{30,}|"
                    r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.")


def iso(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def parse_ts(s: str | None) -> float | None:
    if not s:
        return None
    try:
        return time.mktime(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
    except ValueError:
        return None


def listening(port: int) -> bool:
    """Is anything LISTENing on :port?  File read, cannot hang."""
    want = f":{port:04X}"
    for f in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            for line in open(f).readlines()[1:]:
                p = line.split()
                if p[1].endswith(want) and p[3] == "0A":
                    return True
        except OSError:
            pass
    return False


# ---- L-server: incremental per-request index ------------------------------
LIDX_STATE: dict = {}  # --watch only: {"mtime": LDIR mtime_ns, "pending": bool}


def lserver_index(idx: dict | None = None) -> dict:
    """{reqid: [sid|None, in, out, model, ok, ts, errmsg]}; parse only NEW
    pairs.  A full reparse is 191MB on cj08 -- once per boot, not per tick.
    --watch passes its in-memory idx back in: no reload, no disk write (39-D2)."""
    persist = idx is None
    if not persist:
        # --watch: a new *.response.json bumps the dir mtime.  A file skipped
        # as half-written sets _pending so the next call globs regardless.
        try:
            m = os.stat(LDIR).st_mtime_ns
        except OSError:
            m = None
        if m == LIDX_STATE.get("mtime") and not LIDX_STATE.get("pending"):
            return idx
        LIDX_STATE.update(mtime=m, pending=False)
    if idx is None:
        try:
            idx = json.load(open(INDEX))
        except (OSError, ValueError):
            idx = {}
    for rf in glob.glob(os.path.join(LDIR, "*.response.json")):
        rid = os.path.basename(rf)[:-len(".response.json")]
        if rid in idx:
            continue
        try:
            r = json.load(open(rf))
        except (OSError, ValueError):
            LIDX_STATE["pending"] = True
            continue  # being written right now; next tick picks it up
        sid = None
        try:
            m = SID_RE.search(open(os.path.join(LDIR, rid + ".json"), "rb").read())
            sid = m.group(1).decode() if m else None
        except OSError:
            pass
        u = (r.get("output") or {}).get("tokenUsage") or {}
        err = ((r.get("error") or {}).get("message") or "")[:200]
        idx[rid] = [sid, u.get("inputToken") or 0, u.get("outputToken") or 0,
                    u.get("model") or r.get("model"), bool(r.get("success")),
                    r.get("ts"), err]
    if persist:
        atomic_write(INDEX, idx)
    return idx


def lserver_box(cache: dict | None = None) -> dict:
    """ERROR count + last ERROR in server.jsonl.  With `cache` (--watch) only
    the bytes appended since the last call are scanned; truncation or a new
    inode rescans from 0 (same contract as read_events)."""
    c = cache if cache is not None else {}
    p = os.path.join(LDIR, "server.jsonl")
    try:
        with open(p, "rb") as f:
            st = os.fstat(f.fileno())
            if c.get("ino") != st.st_ino or st.st_size < c.get("off", 0):
                c.update(ino=st.st_ino, off=0, n=0, last=None)
            f.seek(c["off"])
            buf = f.read()
            end = buf.rfind(b"\n") + 1
            for line in buf[:end].splitlines():
                if b'"level":"ERROR"' in line:
                    c["n"] += 1
                    c["last"] = line
            c["off"] += end
    except OSError:
        c.clear()
    n, last = c.get("n", 0), c.get("last")
    le = None
    if last:
        try:
            j = json.loads(last)
            le = {"ts": j.get("ts"), "msg": j.get("msg"),
                  "error": str(j.get("error") or "")[:200]}
        except ValueError:
            pass
    return {"up": listening(LPORT), "errors": n, "last_error": le}


# ---- CLI session state -----------------------------------------------------
def pid_alive(pid: str) -> bool:
    try:
        return b"copilot" in open(f"/proc/{pid}/cmdline", "rb").read()
    except OSError:
        return False


def _new_ev() -> dict:
    return {"start": None, "turns": 0, "last": None, "last_ts": None,
            "tools": {}, "perm": None, "model": None, "msg": None}


QUIET = {f"session.{x}" for x in ("compaction_start", "compaction_complete", "context_changed",
                                   "permissions_changed", "model_change", "mode_changed", "info",
                                   "task_complete", "truncation")}


def _fold(ev: dict, line: bytes) -> None:
    try:
        e = json.loads(line)
    except ValueError:
        return
    t, d = e.get("type"), e.get("data") or {}
    if t not in QUIET:   # 41 G.1: bookkeeping after a turn_end is not work (41-F10)
        ev["last"], ev["last_ts"] = t, e.get("timestamp")
    if t == "session.start":
        ev["start"] = d
        ev["model"] = d.get("selectedModel")
    elif t == "session.model_change":
        ev["model"] = d.get("newModel") or ev["model"]
    elif t == "user.message":
        ev["turns"] += 1   # its content is never kept: prompts may hold pasted secrets
    elif t == "assistant.message" and isinstance(d.get("content"), str) and d["content"].strip():
        # 39-D13: scrub BEFORE the cut, so a token split at 160 cannot slip the regex.
        # Tool-only turns have content "" -> the last real text is kept.
        ev["msg"] = SECRET.sub("[redacted]", d["content"].strip())[:160]
    elif t == "tool.execution_start" and d.get("toolName") == "ask_user":
        ev["tools"][d.get("toolCallId")] = (d.get("arguments") or {}).get("message")
    elif t == "tool.execution_complete":
        ev["tools"].pop(d.get("toolCallId"), None)
    elif t == "permission.requested":
        pr = d.get("permissionRequest") or {}
        ev["perm"] = pr.get("fullCommandText") or pr.get("kind") or "permission"
    elif t == "permission.completed":
        ev["perm"] = None


# {path: [inode, offset, ev]} -- 39 A.1.  Survives across --watch ticks so a
# tick folds only the bytes appended since the last one.  The one-shot timer
# path passes no cache and pays the full parse, as before.
EV_CACHE: dict = {}


def read_events(path: str, cache: dict | None = None) -> dict:
    """Fold events.jsonl.  With `cache`, seek to the last offset and fold only
    NEW complete lines; a trailing partial line is held back (offset stays
    before it).  Truncation (size < offset) or a new inode resets the entry.
    :trap: no tail-N shortcut -- turns and hitl need the whole history."""
    cache = {} if cache is None else cache
    try:
        f = open(path, "rb")
    except OSError:
        cache.pop(path, None)
        return {}
    with f:
        st = os.fstat(f.fileno())
        ent = cache.get(path)
        if not ent or ent[0] != st.st_ino or st.st_size < ent[1]:
            ent = cache[path] = [st.st_ino, 0, _new_ev()]
        if st.st_size > ent[1]:
            f.seek(ent[1])
            buf = f.read()
            end = buf.rfind(b"\n") + 1  # 0 => only a partial line so far
            for line in buf[:end].splitlines():
                _fold(ent[2], line)
            ent[1] += end
        return ent[2]


def yaml_name(d: str) -> str | None:
    try:
        for line in open(os.path.join(d, "workspace.yaml")):
            if line.startswith("name:"):
                return line[5:].strip().strip("'\"") or None
    except OSError:
        pass
    return None


def git_since(cwd: str | None, head: str | None) -> tuple[int | None, str | None]:
    if not (cwd and head and os.path.isdir(cwd)):
        return None, None
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")

    def g(*a):
        p = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True, env=env)
        return p.stdout.strip() if p.returncode == 0 else None
    n = g("rev-list", "--count", f"{head}..HEAD")
    return (int(n) if n and n.isdigit() else None), g("diff", "--shortstat", head)


def token_agg(idx: dict) -> dict:
    """Per-session token/error totals from the L-server index.  O(requests):
    --watch computes it on the 30s heavy tick only, not on every rebuild."""
    agg: dict[str, dict] = {}
    for rid, (sid, ti, to, model, ok, ts, err) in idx.items():
        if not sid:
            continue
        a = agg.setdefault(sid, {"requests": 0, "tokens_in": 0, "tokens_out": 0,
                                 "model": None, "errors": 0, "last_error": None, "_ts": ""})
        a["requests"] += 1
        a["tokens_in"] += ti
        a["tokens_out"] += to
        if (ts or "") >= a["_ts"]:
            a["_ts"], a["model"] = ts or "", model or a["model"]
        if not ok:
            a["errors"] += 1
            if not a["last_error"] or (ts or "") >= (a["last_error"]["ts"] or ""):
                a["last_error"] = {"ts": ts, "error": err}
    return agg


def sessions(now: float, idx: dict, evc: dict | None = None,
             gitc: dict | None = None, agg: dict | None = None) -> list[dict]:
    """evc = read_events cache, gitc = {(cwd, head): (commits, diff)}; both
    None on the one-shot path.  --watch clears gitc every 30s (39-D4)."""
    agg = token_agg(idx) if agg is None else agg
    rows = []
    for lock in locks():
        d = os.path.dirname(lock)
        uuid, pid = os.path.basename(d), lock.rsplit(".", 2)[-2]
        evp = os.path.join(d, "events.jsonl")
        ev = read_events(evp, evc)
        st = ev.get("start") or {}
        ctx = st.get("context") or {}
        started = parse_ts(st.get("startTime"))
        live = pid_alive(pid)
        last = ev.get("last")
        if not ev or not last:
            state = "NOLOG"
        elif last == "assistant.turn_end":
            state = "WAIT"
        elif last == "session.error":
            state = "ERR"
        else:
            state = "BUSY"
        ask = next(iter(ev.get("tools", {}).values()), None) if ev else None
        if ev.get("tools"):
            hitl = {"pending": True, "kind": "ask_user", "question": (ask or "")[:500]}
        elif ev.get("perm"):
            hitl = {"pending": True, "kind": "permission", "question": ev["perm"][:500]}
        elif state == "NOLOG" and live:
            hitl = {"pending": None, "kind": "unknown", "question": None}
        else:
            hitl = {"pending": False, "kind": None, "question": None}
        if hitl["pending"] and live:
            state = "HITL"
        if not live:
            state = "DEAD"  # stale lock after abort/kill: the log's last word is not the truth
        gk = (ctx.get("cwd"), ctx.get("headCommit"))
        if gitc is None:
            commits, diff = git_since(*gk)
        else:
            if gk not in gitc:
                gitc[gk] = git_since(*gk)
            commits, diff = gitc[gk]
        a = agg.get(uuid, {})
        try:
            idle = int(now - os.stat(evp).st_mtime)
        except OSError:
            idle = None
        rows.append({
            "uuid": uuid, "name": yaml_name(d), "pid": int(pid), "live": live,
            "state": state, "last_event": last,
            "started": iso(started) if started else None,
            "age_s": int(now - started) if started else None, "idle_s": idle,
            "turns": ev.get("turns", 0), "cwd": ctx.get("cwd"),
            "model": a.get("model") or ev.get("model"),
            "requests": a.get("requests", 0), "tokens_in": a.get("tokens_in", 0),
            "tokens_out": a.get("tokens_out", 0),
            "commits_repo": commits, "diffstat_repo": diff,
            "lserver_errors": {"count": a.get("errors", 0), "last": a.get("last_error")},
            "hitl": hitl,
            "last_msg": ev.get("msg"),
        })
    rows.sort(key=lambda r: r["started"] or "")
    return rows


def atomic_write(path: str, obj) -> None:
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = f"{path}.tmp.{os.getpid()}"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    os.replace(tmp, path)  # rename within one fs is atomic: readers never see half


# ---- --render: the FLEET half, fed by `recipes.sh sessions` --------------
def human(n: int) -> str:
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}k" if n >= 1e3 else str(n)


def dur(s) -> str:
    if s is None:
        return "-"
    return f"{s//86400}d{s%86400//3600}h" if s >= 86400 else \
        f"{s//3600}h{s%3600//60}m" if s >= 3600 else f"{s//60}m{s%60}s" if s >= 60 else f"{s}s"


def render(inp, color: bool) -> int:
    """stdin = fleet-ssh.sh -R records `box<TAB>j<TAB><json>`.  One row per
    SESSION (R-FLEET); a box with none still gets one row so it cannot vanish."""
    R, Y, Z = ("\033[31m", "\033[33m", "\033[0m") if color else ("", "", "")
    boxes, docs = [], {}
    for line in inp:
        p = line.rstrip("\n").split("\t", 2)
        if p[0] == "#BOXES" and len(p) > 1:
            boxes = [b for b in p[1].split(",") if b]
        elif len(p) == 3 and p[1] == "j":
            try:
                docs[p[0]] = json.loads(p[2])
            except ValueError:
                docs[p[0]] = None
    now = time.time()
    hdr = ["BOX", "NAME", "STATE", "AGE", "IDLE", "TURNS", "REQ", "TOK_IN", "TOK_OUT",
           "MODEL", "COMMITS", "DIFF", "LSERVER", "HITL"]
    rows, paint = [], []
    for b in boxes or sorted(docs):
        d = docs.get(b, "unreach")
        if d == "unreach":
            rows.append([b, "(unreachable)"] + [""] * 12); paint.append({}); continue
        if not d:
            rows.append([b, "(no collector)"] + [""] * 12); paint.append({}); continue
        ls = d["lserver"]
        stale = now - (parse_ts(d["collected_at"]) or 0) > 90
        lcell = ("DOWN" if not ls["up"] else "up") + f"/{ls['errors']}e"
        if stale:
            lcell += "/STALE"
        lred = not ls["up"] or stale
        for s in d["sessions"] or [None]:
            if s is None:
                rows.append([b, "-", "-", "", "", "", "", "", "", "", "", "", lcell, ""])
                paint.append({12: R if lred else ""}); continue
            h = s["hitl"]
            hc = "-" if h["pending"] is False else "?" if h["pending"] is None else \
                f"{h['kind']}: {(h['question'] or '').splitlines()[0][:40] if h['question'] else ''}"
            le = s["lserver_errors"]["count"]
            ds = s["diffstat_repo"] or ""
            m = re.findall(r"(\d+) (?:file|ins|del)", ds)
            rows.append([b, re.sub(r"\S*/", "", s["name"] or "(unnamed)")[:40], s["state"], dur(s["age_s"]),
                         dur(s["idle_s"]), str(s["turns"]), str(s["requests"]),
                         human(s["tokens_in"]), human(s["tokens_out"]), s["model"] or "-",
                         "-" if s["commits_repo"] is None else str(s["commits_repo"]),
                         "f{} +{} -{}".format(*(m + ["0"] * 3)[:3]) if m else "-",
                         lcell + (f" s{le}e" if le else ""), hc])
            paint.append({2: R if s["state"] in ("ERR", "HITL") else Y if s["state"] == "DEAD" else "",
                          12: R if lred else Y if le else "", 13: R if h["pending"] else ""})
    w = [max(len(r[i]) for r in rows + [hdr]) for i in range(len(hdr))]
    print("  ".join(h.ljust(w[i]) for i, h in enumerate(hdr)).rstrip())
    for r, pc in zip(rows, paint):
        print("  ".join((pc.get(i, "") + c.ljust(w[i]) + (Z if pc.get(i) else ""))
                        for i, c in enumerate(r)).rstrip())
    return 0


# ---- --watch: 39 A.2, NDJSON on stdout (39-D5) ----------------------------
HEAVY_S = float(os.environ.get("ORCH_HEAVY_S", "30"))  # tokens + git (39-D4)
HB_S = float(os.environ.get("ORCH_HB_S", "15"))
TICK_S = float(os.environ.get("ORCH_TICK_S", "1"))
# Clock-derived fields: they change every second with nothing happening, so
# they are excluded from the "did the doc change" test.  A viewer ages them
# itself: value + (now - collected_at).
VOLATILE = ("age_s", "idle_s")


def locks() -> list[str]:
    """Every <state>/<uuid>/inuse.<pid>.lock.  scandir, not glob: MEASURED on
    c01 (28 session dirs) glob cost ~6.6ms per sweep, 10x the rest of it."""
    out = []
    for root in STATE_GLOBS:
        for r in glob.glob(root) if glob.has_magic(root) else [root]:
            try:
                dirs = [e.path for e in os.scandir(r) if e.is_dir()]
            except OSError:
                continue
            for d in dirs:
                try:
                    out += [os.path.join(d, n) for n in os.listdir(d)
                            if n.startswith("inuse.") and n.endswith(".lock")]
                except OSError:
                    pass
    return sorted(out)


def sweep() -> tuple:
    """The 1s stat sweep (39-F3: ~0.8ms): every lock, its pid's liveness, and
    the (inode, size, mtime) of events.jsonl + workspace.yaml.  Equal tuples
    => nothing a row depends on moved, so rows are not rebuilt."""
    sig = []
    for lock in locks():
        d = os.path.dirname(lock)
        item = [lock, pid_alive(lock.rsplit(".", 2)[-2])]
        for f in ("events.jsonl", "workspace.yaml"):
            try:
                st = os.stat(os.path.join(d, f))
                item.append((st.st_ino, st.st_size, st.st_mtime_ns))
            except OSError:
                item.append(None)
        sig.append(tuple(item))
    return tuple(sig)


def change_key(doc: dict) -> str:
    d = dict(doc, collected_at=None,
             sessions=[{k: v for k, v in s.items() if k not in VOLATILE} for s in doc["sessions"]])
    return json.dumps(d, sort_keys=True)


def watch() -> int:
    host = os.uname().nodename
    out = sys.stdout
    evc: dict = {}
    gitc: dict = {}
    idx = lserver_index()  # one disk load (plan 35 cache); in memory after this
    idx = lserver_index(idx)  # arms LIDX_STATE (dir mtime) for later ticks
    agg = token_agg(idx)
    unattr = sum(1 for v in idx.values() if not v[0])
    heavy_at = time.monotonic()
    lbc: dict = {}
    lbox = lserver_box(lbc)
    sig, rows, last_key = None, None, None
    last_out = 0.0
    while True:
        t0 = time.monotonic()
        now = time.time()
        heavy = t0 - heavy_at >= HEAVY_S
        if heavy:
            heavy_at = t0
            n0 = len(idx)
            idx = lserver_index(idx)
            if len(idx) != n0:
                agg = token_agg(idx)
                unattr = sum(1 for v in idx.values() if not v[0])
            gitc.clear()
            lbox = lserver_box(lbc)
        s = sweep()
        if heavy or s != sig or rows is None:
            sig, rows = s, sessions(now, idx, evc, gitc, agg)
            live = {os.path.join(os.path.dirname(l[0]), "events.jsonl") for l in s}
            for p in [p for p in evc if p not in live]:
                del evc[p]  # session gone: drop its fold, keep memory flat
        doc = {"schema": SCHEMA, "host": host, "collected_at": iso(now),
               "lserver": lbox, "unattributed_requests": unattr,
               "sessions": rows}
        key = change_key(doc)
        line = None
        if key != last_key:
            last_key = key
            line = {"t": "snap", "host": host, "doc": doc}
        elif t0 - last_out >= HB_S:
            line = {"t": "hb", "host": host, "ts": iso(now)}
        if line:
            try:
                out.write(json.dumps(line, separators=(",", ":")) + "\n")
                out.flush()
            except BrokenPipeError:  # viewer went away (ssh closed): exit quietly
                os.dup2(os.open(os.devnull, os.O_WRONLY), out.fileno())  # no flush error at exit
                return 0
            last_out = t0
        time.sleep(max(0.0, TICK_S - (time.monotonic() - t0)))


def main() -> int:
    if "--watch" in sys.argv[1:]:
        try:
            return watch()
        except KeyboardInterrupt:
            return 0
    if "--render" in sys.argv[1:]:
        return render(sys.stdin, sys.stdout.isatty() or bool(os.environ.get("FORCE_COLOR")))
    now = time.time()
    if "--rows" in sys.argv[1:]:
        # no lserver_index: tokens are not shown, and helix's 175k L-server
        # files made the scan outlast cli's 15s ssh timeout (MEASURED)
        rows = sessions(now, {}, agg={})
        # 39 G2.1: `cli -r` ships this file in its PROBE ssh.  One line per live
        # session, @box|pid|hitl kind|question|last_msg; writes NOTHING to disk.
        box = (sys.argv[sys.argv.index("--rows") + 1:] or [os.uname().nodename])[0]
        cl = lambda v: re.sub(r"[|\s]+", " ", v or "").strip()[:160]
        for r in rows:
            if r["live"]:
                h = r["hitl"] if r["hitl"]["pending"] else {}
                print("@" + "|".join([box, str(r["pid"]), h.get("kind") or "-",
                                      cl(h.get("question")), cl(r["last_msg"])]))
        return 0
    idx = lserver_index()
    rows = sessions(now, idx)
    host = os.uname().nodename
    doc = {"schema": SCHEMA, "host": host, "collected_at": iso(now),
           "lserver": lserver_box(),
           "unattributed_requests": sum(1 for v in idx.values() if not v[0]),
           "sessions": rows}
    atomic_write(OUT, doc)
    if "-p" in sys.argv[1:]:
        print(json.dumps(doc, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
