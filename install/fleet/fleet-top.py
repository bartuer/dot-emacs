#!/usr/bin/env python3
"""fleet-top -- live cluster session map, htop-style, pulled over ssh (plan 39 B).

One long-lived ssh per box (39-F2, R-FLEET) runs

    ssh -o BatchMode=yes <box>wsl python3 -u - --watch   < bin/orch-collect.py

with the collector shipped on STDIN (39-D2), so the box's checkout HEAD is
irrelevant and nothing is written on the box.  Each box streams the 39-D5
NDJSON protocol: {"t":"snap","host","doc"} on change, {"t":"hb"} every 15s.
The viewer keeps {box: doc, last_seen} and redraws on every snap (<=4 Hz).

    fleet-top.py [-b BOXES] [-t TIER]            live screen (ANSI when a tty;
                                                  plain frames split by \\f else)
    fleet-top.py --json   [-b BOXES]              merged map ONCE, then exit:
                                                  {box: doc | {"down": why}}
    fleet-top.py --stream [-b BOXES]              the merged map as one JSON line
                                                  per change (scripts, allocator)

Box states:  a doc and a line within 30s = live;  silent >=30s = STALE;
ssh exited = DOWN (why = last stderr line / rc), reconnected with backoff.
Nothing here has a timeout (R-AWAIT): a dead link is ended by ssh's own
ServerAlive probe, which is the transport's cancellation signal.

age_s / idle_s are excluded from the collector's change test (they tick every
second), so the viewer ages them itself: value + (now - collected_at).

BOXES defaults to `fleet-route.sh broadcast` (the measured `-b up` scope of
fleet-ssh.sh), else this driver's region from bin/fleet-ips.json -- the same
fallback fleet-ssh.sh uses, never silently `all`.
"""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import importlib.util
import io
import json
import os
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def fleet_home(name: str) -> str:
    """41 A.1 / 49-F2: fleet FACT file ${FLEET_HOME:-~/.fleet}/<name>, else bin/<name> (as room.py)."""
    p = os.path.join(os.environ.get("FLEET_HOME") or os.path.expanduser("~/.fleet"), name)
    return p if os.path.exists(p) else os.path.join(HERE, name)
STALE_S = 30
BACKOFF = (1, 2, 4, 8, 15, 30)
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=3", "-T"]


def load_collector(path: str):
    """Import orch-collect.py (hyphenated name) to REUSE its --render rows."""
    spec = importlib.util.spec_from_file_location("orch_collect", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def default_boxes() -> list[str]:
    rt = os.path.join(HERE, "fleet-route.sh")
    try:
        p = subprocess.run([rt, "broadcast"], capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.split():
            return p.stdout.split()
    except OSError:
        pass
    print("# -b up: no reachability graph; falling back to region scope", file=sys.stderr)
    ips = fleet_home("fleet-ips.json")
    if not os.path.exists(ips):                     # 49-D2: facts are not exported
        sys.exit(f"fleet-top: no fleet facts ({ips}); put fleet-ips.json in ${{FLEET_HOME:-~/.fleet}}")
    d = json.load(open(ips))
    me = next((a for a in subprocess.run(["hostname", "-I"], capture_output=True, text=True)
               .stdout.split() if a.startswith("10.") and not a.startswith(("10.42.", "10.43."))), "")
    blk = ".".join(me.split(".")[:2])
    out = [b for r in (d.get("regions") or {}).values()
           if blk and r.get("block", "").startswith(blk + ".") for b in r.get("boxes", {})]
    return sorted(out or d.get("boxes", {}))


class Box:
    def __init__(self, name: str):
        self.name = name
        self.doc: dict | None = None
        self.seen = 0.0          # monotonic time of the last line
        self.seen_wall = 0.0     # wall time of the last line (ages age_s/idle_s)
        self.down: str | None = None
        self.proc = None
        self.first = asyncio.Event()   # first snap OR first DOWN (--json)

    def status(self, mono: float) -> str:
        if self.down is not None:
            return "DOWN"
        if self.doc is None:
            return "CONNECTING"
        return "STALE" if mono - self.seen >= STALE_S else "UP"


class Top:
    def __init__(self, boxes, collector: bytes, tier: str, mode: str, render_mod,
                 renv: list[str] | None = None):
        self.renv = renv or []
        self.boxes = {b: Box(b) for b in boxes}
        self.order = list(boxes)
        self.src = collector
        self.tier = tier
        self.mode = mode
        self.rm = render_mod
        self.dirty = asyncio.Event()
        self.last_stream = None

    # ---- transport ------------------------------------------------------
    async def run_box(self, b: Box, once: bool) -> None:
        tries = 0
        while True:
            why = await self.session(b)
            b.down, b.proc = why, None
            b.first.set()
            self.dirty.set()
            if once:
                return
            await asyncio.sleep(BACKOFF[min(tries, len(BACKOFF) - 1)])  # reconnect backoff
            tries = 0 if b.doc is not None and why.startswith("rc=0") else tries + 1

    async def session(self, b: Box) -> str:
        target = b.name if self.tier in ("", "ctr") else b.name + self.tier
        try:
            p = await asyncio.create_subprocess_exec(
                "ssh", *SSH_OPTS, target, *(["env", *map(shlex.quote, self.renv)] if self.renv else []),
                "python3", "-u", "-", "--watch",
                stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE, limit=16 << 20)
        except OSError as e:
            return f"spawn: {e}"
        b.proc = p
        try:
            p.stdin.write(self.src)
            await p.stdin.drain()
            p.stdin.close()   # EOF ends `python3 -`'s script read
        except (BrokenPipeError, ConnectionResetError):
            pass
        err_task = asyncio.ensure_future(p.stderr.read())
        async for line in p.stdout:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            b.seen, b.seen_wall = time.monotonic(), time.time()
            if m.get("t") == "snap" and isinstance(m.get("doc"), dict):
                b.doc, b.down = m["doc"], None
                b.first.set()
                self.dirty.set()
            elif m.get("t") == "hb" and b.doc is not None:
                self.dirty.set() if self.mode == "tty" else None
        rc = await p.wait()
        err = [l for l in (await err_task).decode(errors="replace").splitlines()
               if l.strip() and "setlocale" not in l]
        return f"rc={rc}" + (f" {err[-1][:120]}" if err else "") + \
            ("" if b.doc is not None else " (no snap)")

    # ---- model ----------------------------------------------------------
    def aged(self, b: Box) -> dict | None:
        """The doc with age_s/idle_s advanced to now (39 A: volatile fields)."""
        if b.doc is None:
            return None
        d = json.loads(json.dumps(b.doc))
        t0 = self.rm.parse_ts(d.get("collected_at")) or b.seen_wall
        dt = max(0, int(time.time() - t0))
        for s in d.get("sessions") or []:
            for k in ("age_s", "idle_s"):
                if isinstance(s.get(k), int):
                    s[k] += dt
        return d

    def cluster_map(self) -> dict:
        out = {}
        for n in self.order:
            b = self.boxes[n]
            if b.down is not None and b.doc is None:
                out[n] = {"down": b.down}
            elif b.doc is None:
                out[n] = {"down": "connecting"}
            else:
                d = self.aged(b)
                st = b.status(time.monotonic())
                if st != "UP":
                    d["_viewer"] = {"status": st, "why": b.down,
                                    "silent_s": int(time.monotonic() - b.seen)}
                out[n] = d
        return out

    def frame(self, color: bool) -> str:
        mono = time.monotonic()
        lines, tags, notes = ["#BOXES\t" + ",".join(self._label(n, mono) for n in self.order)], {}, []
        for n in self.order:
            b = self.boxes[n]
            st = b.status(mono)
            lab = self._label(n, mono)
            if b.doc is not None:
                d = self.aged(b)
                # render() marks STALE on collected_at>90s; in --watch the viewer
                # owns staleness, so hand it a fresh stamp and label the box instead.
                d["collected_at"] = self.rm.iso(time.time())
                lines.append(f"{lab}\tj\t{json.dumps(d)}")
            if st in ("DOWN", "STALE"):
                notes.append(f"{n} {st}: {b.down or f'silent {int(mono - b.seen)}s'}")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.rm.render(lines, color)
        cnt = {}
        for n in self.order:
            s = self.boxes[n].status(mono)
            cnt[s] = cnt.get(s, 0) + 1
        hdr = f"fleet-top {time.strftime('%H:%M:%S')}  boxes={len(self.order)} " + \
            " ".join(f"{k}={v}" for k, v in sorted(cnt.items()))
        return "\n".join([hdr, buf.getvalue().rstrip("\n")] + notes) + "\n"

    def _label(self, n: str, mono: float) -> str:
        st = self.boxes[n].status(mono)
        return n if st == "UP" else f"{n}({st})"

    # ---- output loops ---------------------------------------------------
    async def display(self) -> None:
        tty = self.mode == "tty"
        while True:
            if tty:
                # 1s tick in tty mode only: ages AGE/IDLE and flips STALE on screen.
                with contextlib.suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(self.dirty.wait(), 1.0)
            else:
                await self.dirty.wait()
            self.dirty.clear()
            if self.mode == "stream":
                m = self.cluster_map()
                key = json.dumps({k: {kk: vv for kk, vv in v.items() if kk != "_viewer"}
                                  if "sessions" not in v else
                                  dict(v, sessions=[{x: y for x, y in s.items()
                                                     if x not in ("age_s", "idle_s")}
                                                    for s in v["sessions"]])
                                  for k, v in m.items()}, sort_keys=True)
                if key != self.last_stream:
                    self.last_stream = key
                    sys.stdout.write(json.dumps({"ts": self.rm.iso(time.time()), "boxes": m},
                                                separators=(",", ":")) + "\n")
            elif tty:
                sys.stdout.write("\033[H\033[2J" + self.frame(True))
            else:
                sys.stdout.write("\f" + self.frame(False))
            sys.stdout.flush()
            await asyncio.sleep(0.25)   # <=4 Hz redraw cap (39 B.1)

    async def main(self) -> int:
        once = self.mode == "json"
        tasks = [asyncio.ensure_future(self.run_box(b, once)) for b in self.boxes.values()]
        try:
            if once:
                await asyncio.gather(*(b.first.wait() for b in self.boxes.values()))
                print(json.dumps(self.cluster_map(), indent=1))
                return 0
            await self.display()
            return 0
        finally:
            for b in self.boxes.values():
                if b.proc and b.proc.returncode is None:
                    with contextlib.suppress(ProcessLookupError):
                        b.proc.terminate()
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            for b in self.boxes.values():
                if b.proc:
                    with contextlib.suppress(ProcessLookupError):
                        await b.proc.wait()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-b", "--boxes", help="comma or space separated (default: -b up scope)")
    ap.add_argument("-t", "--tier", default="wsl", help="ssh alias suffix (default wsl)")
    ap.add_argument("--collector", default=os.path.join(HERE, "orch-collect.py"),
                    help="collector shipped on stdin (default bin/orch-collect.py)")
    ap.add_argument("--remote-env", action="append", default=[], metavar="K=V",
                    help="env for the remote collector, e.g. ORCH_STATE_GLOBS=... (tests)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--json", action="store_true", help="print the merged cluster map once")
    g.add_argument("--stream", action="store_true", help="one merged-map JSON line per change")
    a = ap.parse_args()
    boxes = [b for b in (a.boxes or "").replace(",", " ").split() if b] or default_boxes()
    boxes = list(dict.fromkeys(boxes))
    src = open(a.collector, "rb").read()
    if b"--watch" not in src:
        print(f"fleet-top: {a.collector} has no --watch (plan 39 A not landed?)", file=sys.stderr)
        return 2
    mode = "json" if a.json else "stream" if a.stream else "tty" if sys.stdout.isatty() else "frames"
    top = Top(boxes, src, a.tier, mode, load_collector(a.collector), a.remote_env)
    try:
        return asyncio.run(top.main())
    except KeyboardInterrupt:
        return 0
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0


if __name__ == "__main__":
    sys.exit(main())
