#!/usr/bin/env python3
"""room.py -- one chat room for every CLI session and its humans (plan 36).

The room is ONE append-only JSONL file on ONE hub box, reached over the ssh
mesh.  No daemon, no port, no broker: the hub is a file, so moving it is
`rsync` of one file and setting ROOM_HUB.

  room.sh post KIND BODY [--to WHO] [--reply-to ID] [--plan P] [--wi W]
                                     -> prints the new message id
  room.sh read [--all] [--peek]     -> messages since MY cursor (sessions)
  room.sh wait ID                   -> block until a reply_to==ID arrives
  room.sh tail [--all]              -> human view, live; hitl/issue/desire/review
                                       and anything to=human (plan 36 1.3)

  room.sh tasks [--open]            -> every task + its DERIVED state (B.1)
  room.sh next                      -> claim the next open task I can do (B.1)
  room.sh bridge                    -> pipe each new review/hitl/to=human line
                                       to $ROOM_BRIDGE (B.3)

KIND = progress|issue|finding|hitl|desire|ack          (v1, talk)
     | task|join|leave|done|failed|review|pass          (v2, work; plan 36 B.1)

TASKS (plan 36 v2 design record) -- a task is a LINE; its state is derived
from the lines threaded to it by reply_to, in hub file order:
  post task TITLE --ref R --repo cluster@master --needs '{"tier":"wsl"}'
       --done-when CHECK [--to any|@name] [--wi 36/A] [--review]
       [--deps ID,ID] [--parent ID]        (a missing required field refuses)
  open -> ack (first, not by the author) -> claimed(by)
       -> done ref=SHA | failed why= | review ; review + ack -> closed
  pass by the claimant, or why=reopen*, puts a claimed/failed task back open.

WHY IT IS BUILT THIS WAY -- each line is a measurement (plan 36 Phase 1):
  * flock on the HUB around every append.  Without it, 64 KiB posts from 10
    boxes tore into each other (4 corrupt lines, 54/100 distinct); with it,
    0 torn.  Above PIPE_BUF, O_APPEND alone does not make a line atomic.
  * ONE ssh connection per box (ControlMaster), brought up under a LOCAL
    lock.  A fresh ssh per post lost 26-46/100 to the hub's sshd
    `MaxStartups 10:30:100` (kex reset, rc=255).  `ControlMaster=auto` lost
    37/100: ten posts race to become the master.  Serialised bring-up:
    100/100, three runs, both sizes.
  * wait/tail ride `tail -F` on the hub: inotify, 7 ms append->read.  An
    event, not a clock (R-AWAIT).  There is no timeout on purpose.

CHANNELS (plan 36 A.1): `room.sh -c CHAN VERB ...` -- one file per channel,
  $ROOM_DIR/CHAN.jsonl (default channel `fleet`; no `#`: a shell comment).
  A DM is `post --to NAME` in the same channel.  `read` without -c covers
  every channel in ROOM_CHANNELS.

HUBS (plan 36 A.2, C.1): `post` appends the SAME line (same id) to every hub in
  ROOM_HUBS and succeeds if any write lands.  read/wait/tail/tasks use the
  first hub that answers and drop duplicate ids.  `room.sh heal` copies each
  hub's missing ids to the others.  The read cursor is the last id seen (it
  means the same thing on every hub) + the recent ids (dedup) + a per-hub
  byte offset (fast path: what is new on THAT hub, heal-appended lines too).

ENV
  ROOM_HUBS  ssh aliases of the hubs, primary first (default: the three island
             gateways cj00wsl,c00wsl,c16wsl, MY island's first; primary = cj00wsl.
             A lone ROOM_HUB still works and means that one hub)
  ROOM_GATEWAYS  island=hub list behind that default (main=cj00wsl,odsp=c00wsl,sydney=c16wsl)
  ROOM_DIR   channel dir on the hubs        (default /var/lib/agent-room)
  ROOM_CHANNELS  channels `read` covers     (default fleet)
  ROOM_FILE  pin ONE file for every channel (legacy / scratch tests)
  ROOM_FROM  my name (default: tmux session name, else $USER)
  ROOM_WS    parent dir of task repos, for the `next` gate (default /workspace)
  ROOM_BRIDGE  shell cmd fed each review/hitl/to=human line as JSON (default off)
"""
import argparse
import fcntl
import json
import os
import re
import secrets
import select
import signal
import shlex
import socket
import stat
import subprocess
import sys
import threading
import time

KINDS = ("progress", "issue", "finding", "hitl", "desire", "ack",
         "task", "join", "leave", "done", "failed", "review", "pass")
HUMAN_KINDS = ("hitl", "issue", "desire", "review")  # 1.3 noise budget; review: B.3
BRIDGE_KINDS = ("review", "hitl")                    # + to=human (B.3)
WS = os.environ.get("ROOM_WS", "/workspace")        # where task repos are checked out
TASK_REQ = ("title", "ref", "repo", "needs", "done_when")
SVCS = ("lserver", "tserver", "wserver")
# C.1: hub = island gateway.  ROOM_GATEWAYS=main=A,odsp=B,sydney=C swaps them
# (scratch hubs in room-e2e-islands.sh); ROOM_HUBS still pins an exact list.
GATEWAYS = dict(kv.split("=", 1) for kv in os.environ.get(
    "ROOM_GATEWAYS", "main=cj00wsl,odsp=c00wsl,sydney=c16wsl").split(",") if "=" in kv)


def fleet_home(name):
    """41 A.1: fleet FACT file ${FLEET_HOME:-~/.fleet}/<name>, else the committed bin/<name>."""
    p = os.path.join(os.environ.get("FLEET_HOME") or os.path.expanduser("~/.fleet"), name)
    return p if os.path.exists(p) else os.path.join(os.path.dirname(os.path.abspath(__file__)), name)


IPS = fleet_home("fleet-ips.json")


def islands():
    """box -> MEASURED island (fleet-ips.json regions.*.islands)."""
    try:
        d = json.load(open(IPS))
        return {b: i for r in d["regions"].values() for b, i in r.get("islands", {}).items()}
    except (OSError, ValueError, KeyError):
        return {}


def my_island():
    return islands().get(me_box(), "main")


def owner_island(t, isl=None):
    """C.2: the island whose dispatcher places task t -- needs.island if set,
    else the island of the box that posted it.  One owner = one placement."""
    return (t.get("needs") or {}).get("island") or (isl or islands()).get(t.get("box"), "main")


def _hubs():
    env = os.environ.get("ROOM_HUBS", os.environ.get("ROOM_HUB", ""))
    if env:
        hs = [h for h in env.split(",") if h]
        return hs, hs[0]
    mine = GATEWAYS.get(my_island(), GATEWAYS["main"])     # reader-local replica first
    return [mine] + [g for g in GATEWAYS.values() if g != mine], GATEWAYS["main"]
DIR = os.environ.get("ROOM_DIR", "/var/lib/agent-room")
CHAN_RE = re.compile(r"[A-Za-z0-9_.-]+")
CHANNELS = [c for c in os.environ.get("ROOM_CHANNELS", "fleet").split(",") if c]
SEEN_KEEP, BACK = 2000, 1000     # dedup ids kept; lines re-scanned before the anchor


def chan_file(chan):
    if not CHAN_RE.fullmatch(chan):
        sys.exit(f"room: bad channel {chan!r} (letters, digits, _ . - only; no #)")
    return os.environ.get("ROOM_FILE") or f"{DIR}/{chan}.jsonl"


CHAN = "fleet"
FILE = chan_file(CHAN)                              # main() rebinds both for -c
MUX = ["-o", "BatchMode=yes", "-o", "ControlPath=/tmp/room-mux-%C"]
# 28-D3 / 33-D3 spirit: a room is readable by every session; refuse the
# shapes that must never be in it.  Cheap, not complete -- the skill says why.
SECRET = re.compile(r"BEGIN [A-Z ]*PRIVATE KEY|\bgh[pousr]_[A-Za-z0-9]{30,}|"
                    r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.")


def me_box():
    """Short fleet name of THIS box (cj10), from fleet-ips hostnames."""
    h = socket.gethostname().split(".")[0].upper()
    # A container's hostname is its distro's + "ctr" (MEASURED c10c
    # 2026-09-26: CPC-bazho-2OH85ctr); the box is the distro's.  The tier
    # (me_tier) says ctr, and room-dispatch host_of() appends the "c".
    if h.endswith("CTR") and os.path.exists("/.dockerenv"):
        h = h[:-3]
    try:
        d = json.load(open(IPS))
        for r in d["regions"].values():
            for b, hn in r.get("hostnames", {}).items():
                if hn and hn.upper() == h:
                    return b
    except (OSError, ValueError, KeyError):
        pass
    return h.lower()


# HUBS: read order (my island's gateway first); post writes all.  HUB: the ONE
# canonical primary (fleet.py's registry lives there) -- same on every island.
HUBS, HUB = _hubs()


def me_tmux():
    if not os.environ.get("TMUX"):
        return None
    r = subprocess.run(["tmux", "display", "-p", "#S"], capture_output=True, text=True)
    return r.stdout.strip() or None


def me_name():
    return os.environ.get("ROOM_FROM") or me_tmux() or os.environ.get("USER", "human")


def on_hub(h=None):
    return (h or HUB).removesuffix("wsl").removesuffix("u") == me_box()


def mux_up(h=None, strict=True):
    """One control connection per box per hub; bring-up serialised by a local
    lock.  strict=False: a dead hub returns False instead of exiting (A.2)."""
    h = h or HUB
    with open(f"/tmp/room-mux-{re.sub(r'[^A-Za-z0-9_.-]', '_', h)}.lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        if subprocess.run(["ssh", *MUX, "-O", "check", h],
                          capture_output=True).returncode == 0:
            return True
        # -f returns once authenticated: the event we need, no clock.
        r = subprocess.run(["ssh", *MUX, "-o", "ControlMaster=yes",
                            "-o", "ControlPersist=600", "-fN", h])
        if r.returncode:
            if strict:
                sys.exit(f"room: cannot reach hub {h} (ssh rc={r.returncode})")
            print(f"room: hub {h} unreachable (ssh rc={r.returncode})", file=sys.stderr)
            return False
    return True


def hub_argv(cmd, h=None, strict=True):
    """argv that runs shell `cmd` on hub h (default the primary; locally when
    we ARE that hub).  strict=False: None when the hub is unreachable."""
    h = h or HUB
    if on_hub(h):
        return ["sh", "-c", cmd]
    if not mux_up(h, strict):
        return None
    return ["ssh", *MUX, h, cmd]


def hub_run(cmd):
    """(hub, stdout) of `cmd` on the FIRST hub that answers (A.2)."""
    for h in HUBS:
        argv = hub_argv(cmd, h, strict=False)
        if argv is None:
            continue
        r = subprocess.run(argv, capture_output=True)
        if r.returncode == 0:
            return h, r.stdout
        print(f"room: hub {h} rc={r.returncode}", file=sys.stderr)
    sys.exit(f"room: no hub answered ({','.join(HUBS)})")


def append_cmd(f):
    """flock'd append.  If a hub died mid-write, its file ends in a torn line
    with no newline; terminate it first so it cannot swallow the next line."""
    q = shlex.quote(f)
    inner = f'[ -s {q} ] && [ -n "$(tail -c1 {q})" ] && echo >> {q}; cat >> {q}'
    # lock the RESOLVED path: fleet.jsonl -> room.jsonl (the v1 file) keeps
    # one lock, room.jsonl.lock, for old and new writers alike.
    return (f"mkdir -p $(dirname {q}) && flock \"$(readlink -f {q}).lock\" "
            f"sh -c {shlex.quote(inner)}")


def post(a, quiet=False):
    body = a.body if a.body != "-" else sys.stdin.read()
    if a.to is None:
        a.to = "any" if a.kind == "task" else "all"
    if SECRET.search(body):
        sys.exit("room: body looks like a secret (key/token) -- refused")
    m = {"id": f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{secrets.token_hex(3)}",
         "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         "from": me_name(), "box": me_box(), "tmux": me_tmux(),
         "to": a.to, "kind": a.kind, "plan": a.plan, "wi": a.wi,
         "body": body, "reply_to": a.reply_to}
    m["chan"] = CHAN
    m.update(v2_fields(a, m))
    line = (json.dumps(m, ensure_ascii=False) + "\n").encode()
    # A.2: the same line to every hub at once; it has landed if ANY write did.
    ps = [(h, subprocess.Popen(argv, stdin=subprocess.PIPE))
          for h in HUBS if (argv := hub_argv(append_cmd(FILE), h, strict=False))]
    for _, p in ps:
        p.communicate(line)
    landed = [h for h, p in ps if p.returncode == 0]
    if not landed:
        sys.exit(f"room: post failed on every hub ({','.join(HUBS)})")
    heal_on_recovery(CHAN, len(landed) < len(HUBS))
    if len(landed) < len(HUBS):
        print(f"room: landed on {','.join(landed)} only -- heal runs on the next full post",
              file=sys.stderr)
    if not quiet:
        print(m["id"])
    return m["id"]


def cursor_path(f, name):
    # Keyed on FILE + name (a channel), not on a hub: the cursor is hub-free.
    key = re.sub(r"[^A-Za-z0-9_.-]", "_", f"{f}.{name}")
    return os.path.expanduser(f"~/.copilot/room-cursor/v2.{key}")


def read_cmd(f, off, last):
    """Hub-side: print the byte offset reading starts at, then the bytes.
    Fast path: my offset on THIS hub (append-only, so everything after it is
    new here -- heal-appended lines included).  Else (first read of this hub,
    or the file was replaced): anchor on the last id I saw, BACK lines early,
    and let the seen-id set drop what I already have."""
    q = shlex.quote(f)
    anchor = ""
    if last:
        anchor = (f'n=$(grep -n -m1 -F -e {shlex.quote(last)} {q} | cut -d: -f1); '
                  f'[ -n "$n" ] && [ "$n" -gt {BACK} ] && o=$(head -n $((n-{BACK}-1)) {q} | wc -c); ')
    return (f"s=$(stat -L -c %s {q} 2>/dev/null || echo 0); o={off if off is not None else -1}; "
            f'if [ "$o" -lt 0 ] || [ "$s" -lt "$o" ]; then o=0; {anchor}fi; '
            f"echo $o; tail -c +$((o+1)) {q} 2>/dev/null; true")


def read_chan(chan, a, name):
    f = chan_file(chan)
    cp = cursor_path(f, name)
    try:
        cur = json.load(open(cp))
    except (OSError, ValueError):
        cur = {}
    offs, seen_l, last = cur.get("off", {}), cur.get("seen", []), cur.get("last")
    seen, floor = set(seen_l), cur.get("floor", "")
    for h in HUBS:                                   # first hub that answers
        argv = hub_argv(read_cmd(f, offs.get(h), last), h, strict=False)
        if argv is None:
            continue
        r = subprocess.run(argv, capture_output=True)
        if r.returncode == 0:
            break
    else:
        sys.exit(f"room: no hub answered ({','.join(HUBS)})")
    hdr, _, data = r.stdout.partition(b"\n")
    end = data.rfind(b"\n") + 1            # never consume a half-written line
    for raw in data[:end].splitlines():
        try:
            m = json.loads(raw)
        except ValueError:
            continue                        # torn by a dying hub; heal re-copies it
        i = m.get("id") or ""
        if i in seen or i[:16] < floor:     # ids lead with UTC time: below the
            continue                        # window's floor = seen, then trimmed
        seen.add(i), seen_l.append(i)
        last = i
        if m.get("from") == name and not a.all:
            continue
        if a.all or m.get("to") in ("all", name):
            print(json.dumps(m, ensure_ascii=False))
    if not a.peek:
        offs[h] = int(hdr or 0) + end
        os.makedirs(os.path.dirname(cp), exist_ok=True)
        if len(seen_l) > SEEN_KEEP:
            seen_l = seen_l[-SEEN_KEEP:]
            floor = max(floor, min(seen_l)[:16])
        json.dump({"last": last, "off": offs, "seen": seen_l, "floor": floor}, open(cp, "w"))


def read(a):
    """Messages since my cursor, per channel: -c CHAN, else ROOM_CHANNELS.
    Never skips, never repeats -- across hub failover too (A.2)."""
    name = me_name()
    for chan in ([CHAN] if a.chan else CHANNELS):
        read_chan(chan, a, name)


def stream():
    """Every message of the channel, from the start, then live -- inotify on
    the hub.  When the hub dies, carry on from the next one, dropping ids
    already yielded; give up only after every hub in turn gave nothing."""
    q = shlex.quote(FILE)
    seen, dead, i = set(), 0, 0
    while dead < len(HUBS):
        h = HUBS[i % len(HUBS)]
        i += 1
        argv = hub_argv(f"touch {q}; exec tail -c +1 -F {q}", h, strict=False)
        if argv is None:
            dead += 1
            continue
        p = subprocess.Popen(argv, stdout=subprocess.PIPE)
        KIDS.append(p)
        got = False
        try:
            for raw in p.stdout:
                try:
                    m = json.loads(raw)
                except ValueError:
                    continue
                got = True
                if m.get("id") in seen:
                    continue
                seen.add(m.get("id"))
                yield m
        finally:
            p.kill()
        dead = 0 if got else dead + 1
    sys.exit("room: stream ended, no hub answered")


def wait(a):
    """Plain: the FIRST reply_to==id (a hitl's answer).  --final (42 A.1):
    skip ack/pass/progress/..., return on done/failed; a `done ref=split:I`
    moves the wait on to the integrate task I (40-D2)."""
    want = a.id
    for m in stream():
        if m.get("reply_to") != want:
            continue
        if a.final:
            if m.get("kind") not in ("done", "failed"):
                continue
            ref = m.get("ref") or ""
            if m.get("kind") == "done" and ref.startswith("split:"):
                want = ref[len("split:"):]
                continue
        print(json.dumps(m, ensure_ascii=False))
        return


def heal_on_recovery(chan, partial):
    """C.3, no clock (R-AWAIT): a post that missed a hub leaves a pending mark;
    the next post that lands on EVERY hub is the 'it answers again' event and
    runs heal once (flock'd; heal is an id-union, so a second one is a no-op)."""
    pend = os.path.expanduser(f"~/.copilot/room-heal.{re.sub(r'[^A-Za-z0-9_.-]', '_', DIR)}")
    os.makedirs(os.path.dirname(pend), exist_ok=True)
    with open(pend + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        if partial:
            with open(pend, "a") as f:
                f.write(chan + "\n")
            return
        if not os.path.exists(pend):
            return
        chans = sorted(set(open(pend).read().split()))
        os.unlink(pend)
    env = {**os.environ, "ROOM_CHANNELS": ",".join(chans), "ROOM_HUBS": ",".join(HUBS)}
    subprocess.run([sys.executable, os.path.abspath(__file__), "heal"], env=env,
                   stdout=sys.stderr)


def heal(a):
    """Copy each hub's missing ids to the others (A.2).  One row per hub and
    channel (R-FLEET); rc=1 if any hub could not be read or written."""
    bad = 0
    for chan in ([CHAN] if a.chan else CHANNELS):
        f = chan_file(chan)
        got = {}
        for h in HUBS:
            argv = hub_argv(f"cat {shlex.quote(f)} 2>/dev/null; true", h, strict=False)
            r = subprocess.run(argv, capture_output=True) if argv else None
            if r is None or r.returncode:
                print(f"{h}\t{chan}\tUNREACHABLE")
                bad = 1
                continue
            ids = {}
            for raw in r.stdout.splitlines():
                try:
                    ids.setdefault(json.loads(raw)["id"], raw)
                except (ValueError, KeyError, TypeError):
                    continue                # torn line: its id lives on elsewhere
            got[h] = ids
        union = {}
        for ids in got.values():            # primary's order first
            for i, raw in ids.items():
                union.setdefault(i, raw)
        for h, ids in got.items():
            miss = [raw for i, raw in union.items() if i not in ids]
            rc = 0
            if miss:
                argv = hub_argv(append_cmd(f), h, strict=False)
                rc = subprocess.run(argv, input=b"\n".join(miss) + b"\n").returncode if argv else 255
                bad |= rc != 0
            print(f"{h}\t{chan}\thad={len(ids)}\tadded={len(miss)}\trc={rc}")
    sys.exit(bad)


def fmt(m):
    head = f"{m.get('ts', '?')[11:19]} {m.get('kind', '?'):8} {m.get('from')}@{m.get('box')}"
    if m.get("to") not in (None, "all"):
        head += f" -> {m['to']}"
    tag = " ".join(x for x in (m.get("plan") and f"plan={m['plan']}",
                               m.get("wi") and f"wi={m['wi']}",
                               m.get("reply_to") and f"re={m['reply_to']}") if x)
    s = f"{head}  [{m.get('id')}] {tag}\n    {m.get('body', '')}"
    if m.get("kind") == "hitl":
        s += (f"\n    reply : room.sh post ack '<answer>' --reply-to {m.get('id')}"
              f"\n    attach: ssh -t {m.get('box')}wsl tmux attach -t {m.get('tmux') or m.get('from')}")
    if m.get("kind") == "review":      # B.3: a human ack of the TASK closes it
        s += (f"\n    close : room.sh post ack 'reviewed' --reply-to {m.get('reply_to')}"
              f"\n    redo  : room.sh post task '<follow-up>' --parent {m.get('reply_to')} ...")
    return s


def tail(a):
    try:
        for m in stream():
            if a.all or m.get("kind") in HUMAN_KINDS or m.get("to") == "human":
                print(fmt(m), flush=True)
    except KeyboardInterrupt:
        pass


# ---------------------------------------------------------------- v2: tasks
# Plan 36 B.1.  Everything below READS the room and derives; nothing stores
# state (37-F3).  The transport above (post/hub_argv/cursor) is u1's.

def _all():
    """Every parsed line of the room, in hub file order (the claim order)."""
    _, data = hub_run(f"cat {shlex.quote(FILE)} 2>/dev/null || true")   # A.2
    out = []
    for raw in data.splitlines():
        try:
            out.append(json.loads(raw))
        except ValueError:
            continue
    return out


def me_tier():
    # MEASURED 2026-09-26: /.dockerenv exists in cj07c, absent in cj07wsl.
    return "ctr" if os.path.exists("/.dockerenv") else "wsl"


def me_sid():
    sid = os.environ.get("ORCH_SID")
    if not sid and me_tmux():
        r = subprocess.run(["tmux", "show-environment", "ORCH_SID"],
                           capture_output=True, text=True)
        sid = r.stdout.strip().partition("=")[2] or None
    return sid or own_cli_sid()


def own_cli_sid():
    """A human-started CLI has no ORCH_SID but exports COPILOT_AGENT_SESSION_ID
    to its children (tools, cserver).  A tmux pane can INHERIT a stale one from
    whoever started the tmux server, so trust it only if one of MY ancestors
    holds that session's inuse.<pid>.lock; else None (the dispatcher then
    finds the sid from the pane itself)."""
    sid = os.environ.get("COPILOT_AGENT_SESSION_ID")
    if not sid:
        return None
    d = os.path.expanduser(f"~/.copilot/session-state/{sid}")
    p = str(os.getpid())
    for _ in range(64):
        if os.path.exists(f"{d}/inuse.{p}.lock"):
            return sid
        try:
            with open(f"/proc/{p}/status") as f:
                p = next(l.split()[1] for l in f if l.startswith("PPid:"))
        except (OSError, StopIteration):
            break
        if p in ("0", "1"):
            break
    return None


def v2_fields(a, m):
    """Extra top-level fields for the v2 kinds; refuses a bad task line."""
    k, f = a.kind, {}
    if k == "task":
        f = {"title": m["body"], "ref": a.ref, "repo": a.repo,
             "done_when": a.done_when, "review": bool(a.review),
             "deps": [d for d in (a.deps or "").split(",") if d],
             "parent": a.parent}
        try:
            f["needs"] = json.loads(a.needs) if a.needs else None
        except ValueError:
            sys.exit("room: --needs must be JSON, e.g. '{\"tier\":\"wsl\",\"svc\":[\"lserver\"]}'")
        miss = [x for x in TASK_REQ if not f.get(x)]
        if miss:   # trust boundary: a task nobody can evaluate never enters the room
            sys.exit(f"room: task refused, missing {','.join(miss)}")
        n = f["needs"]
        if not isinstance(n, dict) or n.get("tier") not in ("wsl", "ctr") \
                or not set(n.get("svc", [])) <= set(SVCS) \
                or n.get("island", "main") not in GATEWAYS:
            sys.exit(f"room: task refused, needs={n}: tier must be wsl|ctr, svc within {SVCS}, "
                     f"island within {tuple(GATEWAYS)}")
        if "@" not in f["repo"]:
            sys.exit("room: task refused, repo must be NAME@BRANCH")
        if m["to"] != "any" and not m["to"].startswith("@"):
            sys.exit("room: task refused, --to must be any or @name")
        if m["to"] == f"@{m['from']}":      # derive(): an author's ack never claims -- it would stay open forever
            sys.exit("room: task refused, --to is yourself (you cannot claim your own task; just do it)")
        if f["parent"] or f["deps"]:
            st = derive(_all())
            for d in f["deps"] + ([f["parent"]] if f["parent"] else []):
                if d not in st:
                    sys.exit(f"room: task refused, unknown task {d}")
            if f["parent"] and depth(st, f["parent"]) >= 3:
                sys.exit("room: task refused, parent depth > 3")
    elif k in ("done", "failed", "review") and not a.reply_to:
        sys.exit(f"room: {k} needs --reply-to <task id>")
    if k in ("done", "review"):
        f["ref"] = a.ref
    if k in ("failed", "pass", "leave"):
        f["why"] = a.why or m["body"]
    if k == "join":
        f.update({"tier": a.tier or me_tier(), "sid": me_sid(),
                  "repos": [r for r in (a.repos or _cwd_repo()).split(",") if r]})
        if a.until:                                      # 40-D5: member until ROOT final
            f["until"] = a.until
    return f


def depth(st, tid):
    n = 0
    while tid and tid in st:
        n, tid = n + 1, st[tid]["task"].get("parent")
    return n


def derive(lines):
    """Task id -> {task, state, by, ref, why, fails}.  Hub file order decides
    every race: the first ack while OPEN is the claim, and every reader sees
    the same winner because every reader reads the same file (design record)."""
    st = {}
    for m in lines:
        k, t = m.get("kind"), m.get("reply_to")
        if k == "task":
            st[m["id"]] = {"task": m, "state": "open", "by": None, "ref": None,
                           "why": None, "fails": 0}
            continue
        s = st.get(t)
        if not s:
            continue
        who, to = m.get("from"), s["task"].get("to", "any")
        if k == "ack":
            if s["state"] == "open" and who != s["task"]["from"] \
                    and to in ("any", f"@{who}"):
                s["state"], s["by"] = "claimed", who
            elif s["state"] == "review" and who != s["by"]:
                s["state"] = "closed"                   # a human ack closes it
        elif k == "pass":
            why = m.get("why") or ""
            if (s["state"] == "claimed" and who == s["by"]) or \
                    (s["state"] in ("claimed", "failed") and why.startswith("reopen")):
                s["state"], s["by"] = "open", None      # given back / reclaimed (B.2)
        elif k == "failed" and s["state"] == "open" and who == s["task"]["from"]:
            s["state"], s["why"] = "closed", m.get("why") or m.get("body")   # 42 C.1: author withdraws (42-F5)
        elif s["state"] == "claimed" and who == s["by"]:
            if k == "done":
                s["ref"] = m.get("ref")
                # 40-D2: `done ref=split:<id>` = I split it; final when <id> is
                s["state"] = ("split" if (s["ref"] or "").startswith("split:")
                              else "review" if s["task"].get("review") else "done")
            elif k == "review":
                s["state"], s["ref"] = "review", m.get("ref")
            elif k == "failed":
                s["state"], s["why"] = "failed", m.get("why")
                s["fails"] += 1
    return st


def final(st, tid, _seen=()):
    """40 B.1: done/closed, or split whose integrate task is final."""
    s = st.get(tid) or {}
    if s.get("state") in ("done", "closed"):
        return True
    return (s.get("state") == "split" and tid not in _seen
            and final(st, s["ref"][6:], (*_seen, tid)))


def members(lines, st=None):
    """40-D5, THE membership rule: name -> its last join line, for names whose
    last join|leave is a join, minus joins `--until ROOT` whose ROOT is final
    (no leave line needed, so none can be lost).  rooms() and room-dispatch
    joined() both call it."""
    st = derive(lines) if st is None else st
    out = {}
    for m in lines:
        if m.get("kind") == "join":
            out[m.get("from")] = m
        elif m.get("kind") == "leave":
            out.pop(m.get("from"), None)
    return {n: m for n, m in out.items() if not (m.get("until") and final(st, m["until"]))}


def claimable(st, s, name=None):
    t = s["task"]
    return (s["state"] == "open"
            and all(final(st, d) for d in t.get("deps", []))
            and (name is None or (t["from"] != name and t.get("to", "any") in ("any", f"@{name}"))))


def tasks(a):
    st = derive(_all())
    for tid, s in st.items():
        t = s["task"]
        if a.open and not claimable(st, s):
            continue
        blocked = [d for d in t.get("deps", []) if not final(st, d)]
        note = (s["by"] and f"by={s['by']}") or ""
        note += (s["ref"] and (f" integrate={s['ref'][6:]}" if s["state"] == "split"
                               else f" ref={s['ref']}")) or ""
        note += (s["why"] and f" why={s['why']}") or ""
        note += (blocked and f" blocked={','.join(blocked)}") or ""
        print(f"{tid}\t{s['state']}\t{t.get('to')}\t{t.get('wi') or '-'}\t{t['title']}\t{note.strip()}")


def _cwd_repo():
    """41-D4: join serves the cwd's repo by default, else cluster."""
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.basename(r.stdout.strip()) if r.returncode == 0 else "cluster"


def gate(t):
    """'' = I can do task t, else the first gate that refused.  37's GATE_SH
    and _refuse are IMPORTED from room_gate.py (49-D3) (37-F10/F11 traps included), never copied.  The
    probe runs HERE, not via fleet._gate's ssh: MEASURED 2026-09-26 a
    container cannot ssh to itself (cj07c has no alias inside; localhost:22
    denied) and cj07wsl localhost:22 times out -- and the claimant must
    measure its own tier anyway."""
    n = t["needs"]
    if n["tier"] != me_tier():
        return f"tier {n['tier']}!={me_tier()}"
    if n.get("island") and n["island"] != my_island():             # C.2
        return f"island {n['island']}!={my_island()}"
    name, _, branch = t["repo"].partition("@")
    fl = _gate_mod()
    sh = fl.GATE_SH.replace("/workspace/cluster", f"{WS}/{name}")
    sh += "echo branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)\n"
    r = subprocess.run(["bash", "-c", sh], capture_output=True, text=True)
    g = dict(l.split("=", 1) for l in r.stdout.split() if "=" in l)
    if g.get("repo") == "absent":      # GATE_SH exits before slots= -> would read as 'reach'
        return f"repo {name} absent under {WS}"
    g["reach"] = r.returncode == 0 and "slots" in g
    if g.get("repo") != "absent" and g.get("branch") != branch and g["reach"]:
        return f"branch {g.get('branch')}!={branch}"
    # A running claimant already HAS its LLM path; a service is gated only if
    # the task needs it (needs.svc) -- else a container, whose 127.0.0.1
    # lserver answers 000 (measured cj07c), could never claim a tier:ctr task.
    for svc in ("lserver", "tserver"):
        if svc not in n.get("svc", []) and svc in g:
            g[svc] = "200"
    if "wserver" in n.get("svc", []) and g.get("wserver") == "0":
        return "wserver=0"
    return fl._refuse(g, bool(n.get("excel")))


def _gate_mod():
    """49-D3: room_gate.py from room.py's own dir -- the portable set needs no fleet.py."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    import room_gate
    return room_gate


def _say(kind, body, re_id, **f):
    """Post through the one post() path (lock, tripwire, schema)."""
    ns = argparse.Namespace(kind=kind, body=body, to="all", reply_to=re_id, plan=None,
                            wi=None, ref=None, repo=None, needs=None, done_when=None,
                            review=False, deps=None, parent=None, repos=None, tier=None, **f)
    ns.why = f.get("why")
    return post(ns, quiet=True)


def next_(a):
    """Claim the next open task I can do.  ALWAYS posts (the dispatcher awaits
    it, R-AWAIT): `ack` for a win, `pass why=<gate|lost|holding|none>` else."""
    name = me_name()
    st = derive(_all())
    held = [tid for tid, s in st.items() if s["state"] == "claimed" and s["by"] == name]
    cands = [tid for tid, s in st.items() if claimable(st, s, name)]
    if held:                                             # (e) one claim per session
        _say("pass", f"holding {held[0]}", cands[0] if cands else None, why=f"holding {held[0]}")
        print(json.dumps(st[held[0]]["task"], ensure_ascii=False))
        return
    for tid in cands:
        why = gate(st[tid]["task"])
        if why:
            _say("pass", why, tid, why=why)
            continue
        _say("ack", f"claim {tid}", tid)
        s = derive(_all()).get(tid)                     # re-read: who came first?
        if s and s["state"] == "claimed" and s["by"] == name:
            print(json.dumps(s["task"], ensure_ascii=False))
            return
        _say("pass", f"lost to {s and s['by']}", tid, why="lost")
    if not cands:
        _say("pass", "no open task", None, why="none")
    print("none")


def bridged(m):
    return m.get("kind") in BRIDGE_KINDS or m.get("to") == "human"


def bridge_out(m):
    """B.3 seam: pipe one room line (JSON) to $ROOM_BRIDGE when it is one the
    human must see.  Off by default (33-D3).  The dispatcher imports this; a
    Teams adapter later is just a different ROOM_BRIDGE command."""
    cmd = os.environ.get("ROOM_BRIDGE")
    if cmd and bridged(m):
        subprocess.run(cmd, shell=True, input=json.dumps(m, ensure_ascii=False) + "\n",
                       text=True)
        return True
    return False


def bridge(a):
    if not os.environ.get("ROOM_BRIDGE"):
        sys.exit("room: ROOM_BRIDGE is unset (off by default, 33-D3)")
    if a.replay:                       # the room as it is now, then exit
        for m in _all():
            bridge_out(m)
        return
    q = shlex.quote(FILE)              # only lines appended from now on
    p = subprocess.Popen(hub_argv(f"touch {q}; exec tail -n 0 -F {q}"), stdout=subprocess.PIPE)
    try:
        for raw in p.stdout:
            try:
                bridge_out(json.loads(raw))
            except ValueError:
                continue
    finally:
        p.kill()


def rooms(a):
    """Every channel on every hub (all islands), one JSON line each:
    {chan, hubs, lines, last_ts, last_from, joined, dispatched}.  joined =
    names whose last join|leave is join (what the dispatcher reads);
    dispatched = a room-dispatch unit on some hub watches this channel --
    joining a channel nobody dispatches means you are never woken."""
    d = shlex.quote(DIR)
    cmd = (f'for f in {d}/*.jsonl; do [ -f "$f" ] || continue; '
           f'echo "@@ $(basename "$f" .jsonl) $(wc -l < "$f")"; tail -n1 "$f"; '
           f'grep -E \'"kind": "(join|leave|task|ack|pass|done|failed|review)"\' "$f"; done; '
           f'echo "@D $(systemctl show -p ExecStart --value room-dispatch 2>/dev/null '
           f'| grep -o "room-dispatch.py [^ ;]*" | cut -d" " -f2)"')
    ps = [(h, subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))
          for h in HUBS if (argv := hub_argv(cmd, h, strict=False))]
    out, disp = {}, {}
    for h, p in ps:
        cur, first = None, False
        for raw in p.communicate()[0].decode(errors="replace").splitlines():
            if raw.startswith("@D "):
                if raw[3:].strip():
                    disp.setdefault(raw[3:].strip(), []).append(h)
                continue
            if raw.startswith("@@ "):
                name, n = raw[3:].rsplit(" ", 1)
                cur = out.setdefault(name, {"chan": name, "hubs": [], "lines": 0,
                                            "last_ts": None, "last_from": None, "_j": {}})
                cur["hubs"].append(h)
                cur["lines"] = max(cur["lines"], int(n or 0))
                first = True
                continue
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            if cur is None:
                continue
            if first:
                first = False
                if (m.get("ts") or "") > (cur["last_ts"] or ""):
                    cur["last_ts"], cur["last_from"] = m.get("ts"), m.get("from")
                continue
            if m.get("id") and m["id"] not in cur["_j"]:    # union of hubs, by id
                cur["_j"][m["id"]] = m
    if not ps:
        sys.exit(f"room: no hub answered ({','.join(HUBS)})")
    for c in sorted(out.values(), key=lambda c: c["last_ts"] or "", reverse=True):
        c["joined"] = sorted(members(sorted(c.pop("_j").values(),
                                            key=lambda m: (m.get("ts") or "", m["id"]))))
        c["dispatched"] = disp.get(c["chan"], [])
        if c["joined"] and not re.search(os.environ.get("ROOM_DISPATCH_SKIP", "test|e2e"), c["chan"]):
            c["dispatched"] = sorted(set(c["dispatched"]) | set(disp.get("--all", [])))  # 40 A.3: --all = every joined chan
        if a.verb == "in":              # 36 D.5: only rooms NAME (default me) is joined in
            if a.name not in c["joined"]:
                continue
            print(c["chan"] if a.names else json.dumps(c, ensure_ascii=False))
            continue
        print(c["chan"] if getattr(a, "names", False) else json.dumps(c, ensure_ascii=False))


LAST_KINDS = ("progress", "done", "failed", "hitl", "issue", "review")


def last(a):
    """39 G1.2: per `from`, its latest {ts, kind, wi, body[:160]} over
    LAST_KINDS, across every channel (or just -c CHAN), union of all hubs
    (same fan-out as rooms()).  One JSON line per sender, newest first --
    what `cli` shows as WI / LAST."""
    d = shlex.quote(DIR)
    files = f"{d}/*.jsonl" if a.chan in (None, "all") else shlex.quote(chan_file(a.chan))
    kinds = "|".join(LAST_KINDS)
    cmd = f'grep -HE \'"kind": "({kinds})"\' {files} 2>/dev/null; true'
    ps = [subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
          for h in HUBS if (argv := hub_argv(cmd, h, strict=False))]
    if not ps:
        sys.exit(f"room: no hub answered ({','.join(HUBS)})")
    best = {}
    for p in ps:
        for raw in p.communicate()[0].decode(errors="replace").splitlines():
            path, _, js = raw.partition(".jsonl:")
            try:
                m = json.loads(js)
            except ValueError:
                continue
            f, ts = m.get("from"), m.get("ts") or ""
            if f and m.get("kind") in LAST_KINDS and ts > (best.get(f, {}).get("ts") or ""):
                best[f] = {"from": f, "ts": ts, "kind": m["kind"], "wi": m.get("wi"),
                           "chan": os.path.basename(path), "box": m.get("box"),
                           "body": (m.get("body") or "")[:160]}
    for r in sorted(best.values(), key=lambda r: r["ts"], reverse=True):
        print(json.dumps(r, ensure_ascii=False))


KIDS = []   # live hub children of stream(); killed when our reader goes away (42 B.1)


def _quit_quietly(*_):
    """Our stdout's reader is gone (`| head -1`, `| grep -m1`): kill the hub
    children and exit 0 with no traceback -- also at interpreter-exit flush."""
    for p in KIDS:
        try:
            p.kill()
        except OSError:
            pass
    try:
        os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
    except OSError:
        pass
    os._exit(0)


def _watch_stdout():
    """42-F2: `tail | head -1` blocks in tail -F with nothing to write, so it
    would never see EPIPE; a pipe's write end polls POLLERR once the reader
    closes, so notice that and leave at once."""
    try:
        if not stat.S_ISFIFO(os.fstat(1).st_mode):
            return
    except OSError:
        return
    def run():
        pl = select.poll()
        pl.register(1, 0)            # POLLERR/POLLHUP are always reported
        while True:
            for _, ev in pl.poll():
                if ev & (select.POLLERR | select.POLLHUP):
                    _quit_quietly()
    threading.Thread(target=run, daemon=True).start()


def main():
    # Not SIG_DFL (the plan's hint): that dies 141 and orphans the hub's
    # ssh tail -F; SIG_IGN keeps EPIPE an exception we turn into exit 0.
    signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    _watch_stdout()
    try:
        _main()
        sys.stdout.flush()
    except BrokenPipeError:
        _quit_quietly()


def _main():
    ap = argparse.ArgumentParser(prog="room.sh", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-c", "--chan", help="channel (default fleet; read: ROOM_CHANNELS)")
    sp = ap.add_subparsers(dest="verb", required=True)
    add = sp.add_parser
    def with_chan(*x, **k):          # -c also after the verb: `room.sh read -c ops`
        q = add(*x, **k)
        q.add_argument("-c", "--chan", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
        return q
    sp.add_parser = with_chan
    p = sp.add_parser("post")
    p.add_argument("kind", choices=KINDS)
    p.add_argument("body", help="text, or - for stdin")
    p.add_argument("--to", default=None, help="all (default), a name, human; task: any|@name")
    p.add_argument("--reply-to")
    p.add_argument("--plan")
    p.add_argument("--wi")
    v = p.add_argument_group("v2 (task kinds, plan 36 B.1)")
    v.add_argument("--ref", help="task: what to read first (path@sha); done: the sha")
    v.add_argument("--repo", help="task: NAME@BRANCH the worker needs, clean")
    v.add_argument("--needs", help='task: JSON {"tier":"wsl|ctr","svc":[...],"excel":false,"island":"main|odsp|sydney"}')
    v.add_argument("--done-when", help="task: the runnable check that ends it")
    v.add_argument("--review", action="store_true", help="task: ends in human review")
    v.add_argument("--deps", help="task: ID,ID not claimable until each is done")
    v.add_argument("--parent", help="task: lineage, depth <= 3")
    v.add_argument("--why", help="failed/pass/leave: the reason")
    v.add_argument("--repos", help="join: repos I serve (default: the cwd's git repo, else cluster)")
    v.add_argument("--tier", help="join: wsl|ctr (default: measured)")
    v.add_argument("--until", help="join: member only until task ID's tree is final (40-D5)")
    p = sp.add_parser("read")
    p.add_argument("--all", action="store_true", help="every message, mine included")
    p.add_argument("--peek", action="store_true", help="do not advance the cursor")
    p = sp.add_parser("wait")
    p.add_argument("id")
    p.add_argument("--final", action="store_true",
                   help="only done/failed; follow done ref=split:I on to I (42 A.1)")
    p = sp.add_parser("tail")
    p.add_argument("--all", action="store_true", help="progress/finding/ack too")
    p = sp.add_parser("tasks")
    p.add_argument("--open", action="store_true", help="only claimable ones")
    sp.add_parser("next")
    p = sp.add_parser("bridge")
    p.add_argument("--replay", action="store_true", help="the room as it is now, then exit")
    sp.add_parser("heal", help="copy each hub's missing ids to the others (A.2)")
    for v in ("rooms", "list", "ls"):   # 36 D.5: `list` = `ls` = `rooms`
        p = sp.add_parser(v, help="list every channel on every hub: lines, last, joined, dispatched")
        p.add_argument("-n", "--names", action="store_true", help="channel names only")
    p = sp.add_parser("in", help="rooms NAME (default: this session) is joined in")
    p.add_argument("name", nargs="?", default=None, help="session name (default ROOM_FROM / tmux)")
    p.add_argument("-n", "--names", action="store_true", help="channel names only")
    sp.add_parser("last", help="per sender: latest progress/done/failed/hitl/issue/review, every channel")
    a = ap.parse_args()
    if a.verb == "in":
        a.name = a.name or me_name()
    global CHAN, FILE
    CHAN = a.chan or "fleet"
    FILE = chan_file(CHAN)
    {"heal": heal, "post": post, "read": read, "wait": wait, "tail": tail, "tasks": tasks,
     "next": next_, "bridge": bridge, "rooms": rooms, "list": rooms, "ls": rooms, "in": rooms, "last": last}[a.verb](a)


if __name__ == "__main__":
    main()
