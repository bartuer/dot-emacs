#!/usr/bin/env python3
"""cli-feed -- the ONE background feeder behind `watch -n 2 cli` (plan 39 H.1, 39-D14).

    cli-feed.py            run: fleet-top --stream over the registry's boxes,
                           rewrite $REG.top atomically on every snap
    cli-feed.py --once F   fold ONE fleet-top map (a file, - = stdin) -> $REG.top
                           (tests; no network)

`cli` (no args) reads $REG + $REG.state + $REG.top and makes NO network call.
It starts this feeder lazily if $REG.feed.pid is dead, and touches $REG.feed.read.

$REG.top = box|session|wi|last|state|since|owes   (cli -r writes the first 4 only)
  state  WAIT|BUSY|ASK|PERM|ERR|DEAD|GONE  (raw; `cli` derives STALL/IDLE -> ACT)
  since  epoch of the session's last event (idle_s at snap time, made absolute)
  owes   1 = a room task claimed by this session is still `claimed` (39-D16)

R-AWAIT (deviates from 39-D14's "room.sh last every 10s"): no tick.  Room
data (`room.sh last`, `tasks`) is re-read on each fleet-top snap -- a session
that posts to the room writes its own events.jsonl, so its box snaps anyway.
The one deadline is the D14 self-expiry: CLI_FEED_IDLE (300s) since the last
`cli` read ($REG.feed.read mtime) -> exit.  Ages are NOT written: `since` is an
epoch and `cli` ages it, so a quiet fleet needs no rewrite.
Never writes $REG: its 5-field readers (plan-route) stay intact.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.realpath(__file__))
REG = os.environ.get("PLAN_REGISTRY", os.path.expanduser("~/.copilot/sessions"))
ROOM_SH = os.environ.get("ROOM_SH", os.path.join(HERE, "room.sh"))
FEED_IDLE = int(os.environ.get("CLI_FEED_IDLE", "300"))



_WI = re.compile(r"(?<![0-9])([0-9]{2}/[A-Z][A-Za-z0-9.]*)")
_PLAN = re.compile(r"[Pp]lan ([0-9]{2})(?: [Pp]hase ([A-Z]))?")


def body_wi(body):
    """No --wi on the post: `NN/X` or "plan NN [Phase X]" from its body, so a
    session that switched plan mid-work shows it (same rule as cli toprows)."""
    m = _WI.search(body)
    if m:
        return m.group(1)
    m = _PLAN.search(body)
    return (m.group(1) + ("/" + m.group(2) if m.group(2) else "")) if m else ""

def rows(path: str, n: int) -> list[list[str]]:
    try:
        return [(l.rstrip("\n").split("|") + [""] * n)[:n] for l in open(path) if l.strip()]
    except OSError:
        return []


def clean(v: str | None) -> str:
    return re.sub(r"[|\s]+", " ", v or "").strip()[:160]


def room_json(*args: str) -> list[dict]:
    try:
        out = subprocess.run([ROOM_SH, *args], capture_output=True, text=True).stdout
    except OSError:
        return []
    res = []
    for l in out.splitlines():
        try:
            res.append(json.loads(l))
        except ValueError:
            pass
    return res


def room_state(groups: set[str]) -> tuple[dict, set]:
    """({from: last line}, {sessions that owe a claimed, not-final task})."""
    last = {m.get("from"): m for m in room_json("last")}
    owes = set()
    for g in groups:   # `tasks` is per channel: one call per joined group
        try:
            out = subprocess.run([ROOM_SH, "-c", g, "tasks"], capture_output=True, text=True).stdout
        except OSError:
            continue
        for l in out.splitlines():
            f = l.split("\t")
            by = next((x[3:] for x in f if x.startswith("by=")), "")
            if len(f) > 1 and f[1] == "claimed" and by:
                owes.add(by.split()[0])
    return last, owes


def fold(cmap: dict, room: tuple[dict, set], now: float | None = None) -> list[str]:
    """One fleet-top map + room state -> $REG.top lines, for the registry's rows.
    Raw state + `since` (epoch of the session's last event), never an age: `cli`
    ages it at read time, so STALL/IDLE turn on without the feeder waking."""
    last, owes = room
    now = time.time() if now is None else now
    pids = {(r[0], r[1]): r[3] for r in rows(REG + ".state", 4)}
    out = []
    for b, s, *_ in rows(REG, 6):
        doc = cmap.get(b) or {}
        ses = next((x for x in doc.get("sessions") or [] if str(x.get("pid")) == pids.get((b, s))), None)
        m = last.get(s) or {}
        k = m.get("kind") or ""
        w = m.get("wi") or body_wi(m.get("body") or "")
        wi = (("prog" if k == "progress" else k) + (" " + w if w else "")) or "-"
        h = (ses or {}).get("hitl") or {}
        la = ("?" + clean(h.get("question"))) if h.get("pending") else \
            clean((ses or {}).get("last_msg")) or clean(m.get("body")) or "-"
        idle = (ses or {}).get("idle_s")
        if pids.get((b, s)) in (None, "", "-") or doc.get("down") == "connecting":
            # no pid join (old .state, PROBE saw no lock) or no first snap yet
            # (MEASURED: the first stream line has every other box `connecting`):
            # '' = cli keeps PROBE's $REG.state, never a false GONE
            state = ""
        elif "down" in doc or (doc.get("_viewer") or {}).get("status") in ("DOWN", "STALE"):
            state = "GONE"
        elif not ses or not ses.get("live"):
            state = "DEAD"
        elif h.get("pending"):
            state = {"ask_user": "ASK", "permission": "PERM"}.get(h.get("kind"), "BUSY")
        else:
            state = {"WAIT": "WAIT", "ERR": "ERR"}.get(ses.get("state"), "BUSY")
        since = str(int(now - idle)) if isinstance(idle, int) else "-"
        out.append("|".join([b, s, wi, la, state, since, "1" if s in owes else ""]))
    return out


def write_top(lines: list[str]) -> None:
    tmp = f"{REG}.top.feed.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write("".join(l + "\n" for l in lines))
    os.replace(tmp, REG + ".top")   # atomic: `watch cli` never reads half


def groups() -> set[str]:
    return {g for r in rows(REG, 6) for g in r[5].split(",") if g and g != "-"}


def once(path: str) -> int:
    cmap = json.load(sys.stdin if path == "-" else open(path))
    cmap = cmap.get("boxes", cmap)
    write_top(fold(cmap, room_state(groups())))
    return 0


def run() -> int:
    pidf = REG + ".feed.pid"
    open(pidf, "w").write(str(os.getpid()))
    boxes = sorted({r[0] for r in rows(REG, 6)})
    if not boxes:
        return 0
    p = subprocess.Popen([sys.executable, os.environ.get("FLEET_TOP", os.path.join(HERE, "fleet-top.py")), "--stream",
                          "-t", "", "-b", ",".join(boxes)], stdout=subprocess.PIPE, text=True)
    latest, ev = [None], threading.Event()
    seen: set[str] = set()   # pids already swept for

    def reader():   # keep only the NEWEST map: a slow fold never builds a backlog
        for line in p.stdout:
            latest[0] = line
            ev.set()
        latest[0] = None
        ev.set()
    threading.Thread(target=reader, daemon=True).start()
    try:
        while True:
            ev.wait(FEED_IDLE)   # the deadline IS the 39-D14 self-expiry, not a poll
            ev.clear()
            try:
                if time.time() - os.stat(REG + ".feed.read").st_mtime > FEED_IDLE:
                    return 0   # nobody looked for CLI_FEED_IDLE: 39-D1, no watcher when unwatched
            except OSError:
                return 0
            line = latest[0]
            if line is None:
                return p.wait()
            try:
                cmap = json.loads(line).get("boxes") or {}
            except ValueError:
                continue
            write_top(fold(cmap, room_state(groups())))
            # 41: a live pid no $REG row knows = a new session -> one `cli -r` in the
            # background (seen: vterm pids never join $REG, so each pid fires once only)
            known = {r[3] for r in rows(REG + ".state", 4)}
            new = {str(x.get("pid")) for d in cmap.values() if isinstance(d, dict)
                   for x in d.get("sessions") or [] if x.get("live")} - known - seen
            if new:
                seen |= new
                subprocess.Popen([os.path.join(HERE, "cli-sessions.sh"), "-r"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    finally:
        if p.poll() is None:
            p.terminate()
        try:
            if open(pidf).read().strip() == str(os.getpid()):
                os.remove(pidf)
        except OSError:
            pass


if __name__ == "__main__":
    if sys.argv[1:2] == ["--once"]:
        sys.exit(once(sys.argv[2] if len(sys.argv) > 2 else "-"))
    sys.exit(run())
