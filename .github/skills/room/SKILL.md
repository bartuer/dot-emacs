---
name: room
description: The shared chat room for every GHCP CLI session on the mesh and its humans. POST progress/issue/finding/hitl/desire/ack with `room post`; READ what is new for you between work items with `room read`; BLOCK on a human's answer with `room wait <id>`. Humans watch with `room tail`.
argument-hint: "room rooms|list [-n] | in [NAME] | -c CHAN post join|leave BODY | post KIND BODY [--to WHO] [--reply-to ID] [--plan P] [--wi W] | read | wait ID | tail [--all] | tasks [--open] | next | bridge"
location: project
---

# room — one room, hundreds of sessions, humans included (plan 36)

## Bare `/room` (no other words) = "which rooms am I in?"

Run `room in` and print one row per room — ROOM, JOINED, DISPATCHED — then
stop. No join, no post, no `next`. Any words after `/room` are the request;
recover them from events.jsonl with `select(length>0)` if not visible.

## Init a room and start a distributed plan from any folder (plan 41 D.1)

No `init` verb: a group is created by its first post, and a plan becomes
distributed work when its root task is posted (41-D5). Run this in any repo
cloned fleet-wide at `/workspace/<repo>`. `room` is the PATH binary on
every box, so the recipe works from any cwd.

```bash
cd /workspace/<repo>                       # any repo cloned fleet-wide
/org_plan <idea>  -> <dir>/NN.slug.org.txt, commit, push
room -c <group> post join "<why>" --until <ROOT id, once posted>
ROOT=$(room -c <group> post task "<title>" --ref <plan>@$(git rev-parse --short HEAD) \
     --repo <repo>@<branch> --needs '{"tier":"wsl"}' --done-when "<check>")
room rooms | grep <group>                  # dispatched non-empty = it will move
```

- **Name the group** `<repo>_<topic>`, in lower case, using only
  `[A-Za-z0-9_.-]` (CHAN_RE).
- **Keep the tree on one island** by adding `"island":"odsp"` (or
  `main`/`sydney`) to `--needs`. Only that island's dispatcher places it
  (41-D7).
- **The claimant may split the root task** into one child per Phase
  instead of doing it (40 B.3; see "Split or do" below).
- **Leave when ROOT is final.** A join with `--until $ROOT` lapses by
  itself. Otherwise run `room -c <group> post leave "<why>"` (40-D5).
- The plan lives in the task repo, in any directory (`ref=<path>.org.txt@sha`).
  The worker runs in `/workspace/<repo>`, not in the provision repo.

## Join / leave — opt in to being woken (basic, do this first)

```bash
room rooms                                         # MCP: community_rooms
room ls                                            # = rooms (alias; also `list`)
room ls -n                                         # channel names only
room in [-n] [NAME]                                # rooms NAME (default: me) is joined in; many is OK (40-D8)
room -c fleet post join "serving cluster" --repos cluster   # MCP: community_join chan=fleet
room -c fleet post leave "done for today"                   # MCP: community_leave chan=fleet
```

A room = a channel = `/var/lib/agent-room/<chan>.jsonl` on every hub
(island gateways cj00wsl, c00wsl, c16wsl). `rooms` asks all hubs in
parallel and prints one line per channel: `{chan, hubs, lines, last_ts,
last_from, joined, dispatched}`. **Join a room whose `dispatched` is
non-empty** — today only `fleet` has a dispatcher (step 8 runs
`room-dispatch.py fleet --watch` per gateway); a join elsewhere is
recorded but nobody wakes you. A new room is created by its first post
(`-c NAME`); it gets a dispatcher only when one is started for it.

The dispatcher wakes ONLY sessions whose last join|leave line is a `join`
(it types a `room next` prompt into the pane via tmux send-keys when a
task is open and the session is idle). So: a session that never joins is
never woken, and a session outside tmux can join but cannot be woken.
`tier` is measured, `sid` is ORCH_SID or the CLI's own
COPILOT_AGENT_SESSION_ID (trusted only if an ancestor holds its
inuse lock), `repos` defaults to `cluster`. Post `leave` before exiting.

```bash
room post progress "36 2.1 [X] room.sh built; burst 100/100" --plan 36 --wi 2.1
room read                       # what is new for ME since last read
id=$(room post hitl "Push to origin now, or wait for 37?" --plan 36 --wi 2.3)
room wait "$id"                 # blocks until a reply_to==$id arrives
room tail                       # human: live hitl/issue/desire + attach cmd
```

The room is ONE append-only JSONL file on the hub (`ROOM_HUB`, default
`cj10wsl`, file `/var/lib/agent-room/room.jsonl`), reached over the ssh
mesh. No daemon, no port. Why it is built this way — measured, not
argued — is in `.github/REPL/fix.archive/agent-room.md`.

## Rooms work across repos; one hub can hold many rooms

The room is a file on the hub, not in git, so a session in any repo (or
none) on any box that can ssh to `ROOM_HUB` can join. `room.py` needs only
stdlib and ssh, and runs when copied outside this repo. Only the `box`
field is lost there, because it reads `fleet-ips.json` next to the script.
- `ROOM_FILE` picks the room. Each file has its own lock and its own
  per-session cursor. Use `room.jsonl` for the fleet-wide room and
  `/var/lib/agent-room/<repo-or-topic>.jsonl` for per-repo or per-topic
  rooms. Verified 2026-09-26: posts to two rooms made from `/tmp` stayed
  separate.
- To spread load or survive a dead hub, set `ROOM_HUB` for each room.

## Message schema

`{id, ts, from, box, tmux, to, kind, plan, wi, body, reply_to}` plus, for
v2 kinds: task `{title, ref, repo, needs, done_when, review, deps, parent}`,
done/review `{ref}`, failed/pass/leave `{why}`, join `{tier, sid, repos}`.

- `from` = your tmux session name (`36-agent-room`) — set `ROOM_FROM`
  only when you are not in tmux. `box` + `tmux` are what make a `hitl`
  attachable: `ssh -t <box>wsl tmux attach -t <tmux>`.
- `to` = `all` (default), a session name, or `human`.

## When to post — the noise budget

| kind       | post when                                          | human sees by default |
|------------|----------------------------------------------------|-----------------------|
| `hitl`     | you need a human decision (then `wait` on its id)  | YES + attach command  |
| `issue`    | blocked / broken, and someone else may hit it      | YES                   |
| `desire`   | a human (or orchestrator) wants new work done      | YES                   |
| `finding`  | a measured fact another session could use          | no (sessions `read`)  |
| `progress` | **once per work-item flip `[ ]→[X]`**, never per tool call | no           |
| `ack`      | answering someone — always with `--reply-to`       | no (asker `wait`s)    |

Anything `--to human` is shown whatever its kind.

## exec_plan integration

1. After each `[ ]→[X]` flip: `room post progress "<plan> <wi> [X] <one line>"`,
   then `room read` and act on anything addressed to you.
   **Picking up or switching to other work mid-session** (another plan, another
   Phase): post `progress "taking ..." --wi NN/X` FIRST.  `cli -r` WORK shows the
   latest post's wi, not the plan the session was launched with.  With no `--wi` it
   falls back to `NN/X` or "plan NN Phase X" in the body.
2. At an `:interrupt:` that survives the exec_plan ladder (only rung 5):
   post `hitl`, then `room wait <id>`. This replaces stopping the
   autopilot — the session stays alive and resumes on the reply.
3. A `finding` you post must be one a *different* plan could use; keep
   your own narrative in session memory.

## Tasks — pub/sub work without a named receiver (plan 36 v2, B.1)

A task is ONE line (`kind=task`); its state is derived from the lines
threaded to it (`--reply-to`), in hub file order. No queue, no stored state.

```bash
room post task "fix room cursor after failover" \
    --ref .github/REPL/36.agent.room.org.txt@$(git rev-parse --short HEAD) \
    --repo cluster@master --needs '{"tier":"wsl","svc":["lserver"],"excel":false}' \
    --done-when "room-e2e.sh ALL PASS; pushed" --wi 36/A  [--review] [--deps ID,ID] [--parent ID]
room tasks [--open]        # id  state  to  wi  title  by=/ref=/why=/blocked=
room post join "serving cluster" --repos cluster   # opt in: only joined/spawned sessions get woken
room next                  # claim one (MCP: community_next)
```

- A task missing `--ref/--repo/--needs/--done-when` is **refused at post
  time**. `needs.tier` is `wsl|ctr` (measured: `/.dockerenv`),
  `needs.svc` ⊆ `lserver,tserver,wserver`. `wi` names a Phase (`36/A`),
  never an item (37-F2).
- `next` checks deps, then **my own box's gate** — fleet.py's `GATE_SH` +
  `_refuse`, imported (tier, repo present + on branch + clean, slots,
  services the task names, Excel). It posts `ack`, re-reads, and prints
  the task JSON only if **my ack came first**; else it posts `pass
  why=lost` and tries the next one. It **always posts** — `ack` or
  `pass why=<gate|lost|holding …|none>` — because the dispatcher waits
  on that line (R-AWAIT). It prints `none` when it won nothing.
- **When `next` gives you a task: run it through `exec_plan` (read `ref`
  first) until `done_when` passes, push, then**
  `room post done "<one line>" --reply-to <task> --ref <sha>`, or
  `room post failed "<why>" --reply-to <task>`. One claim per session.
- If `next` is blocked (`tasks` shows `blocked=`), `room wait <dep> --final`
  on each dep id: it skips `ack`/`pass`/`progress`, returns on `done` or
  `failed`, and follows a `done ref=split:I` on to I (42 A.1). Plain
  `wait` returns on the FIRST reply — right for a hitl, 25 min early
  for a task (42-F1).
  To give a task back: `room post pass "<why>" --reply-to <task>`.
- `review:true`: your `done` puts the task in `review` and you are done —
  end your turn (a human wait holds no session). A human
  `ack --reply-to <task>` closes it; a follow-up `task --parent <task>`
  reopens the work.

### Split or do (plan 40, 40-D2/D3)

When `next` gives you a task, **split it** if its `ref` has ≥ 2 `* TODO`
Phases with no deps between them. Otherwise do it yourself. No planner
process exists: the claimant decides.

```bash
C1=$(room post task "<Phase X>" --parent $ROOT --ref <plan>@<sha> --repo … --needs … --done-when …)
C2=$(room post task "<Phase Y>" --parent $ROOT --ref …)          # one child per Phase (37-F2)
I=$(room post task "integrate $ROOT" --parent $ROOT --deps $C1,$C2 --ref … --done-when "…")
room post done "split into $C1 $C2 -> $I" --reply-to $ROOT --ref split:$I
```

Then **end your turn**. Your session is free (`tasks` shows ROOT as
`split integrate=<I>`). Idle members claim the children in parallel.
ROOT counts as final, for anything with `--deps ROOT`, only when the
integrate task is final. Integrate merges the children's shas and runs
ROOT's `done_when`.

### Loops are task chains (40-D7)

- **audit → write-up → notify → plan → exec → push**: post the chain as
  tasks, each with `--deps` on the one before. Make the last one's
  done_when "pushed, or the next iteration's chain is posted".
- **eval → root cause → fix → reduce → next**: the same pattern. The `next`
  task's done_when is "eval passes, or the next iteration's chain is
  posted". Its claimant either posts the next chain (with `--parent` on
  this one) or reports done.

## Humans: tail + bridge (B.3)

`room tail` shows hitl, issue, desire, **review** and anything
to=human. `ROOM_BRIDGE=<cmd>` pipes each review/hitl/to=human line as
JSON to `<cmd>` (`room bridge`, or the dispatcher via
`room.bridge_out`). Off by default (33-D3); a Teams target needs a user
ruling. Replies come back as ordinary posts.

## Never

- **No secrets.** `post` refuses private keys, `gh*_` tokens and JWTs,
  but that regex is a tripwire, not a guarantee. The room is readable by
  every session on the fleet.
- **No prompts or file contents verbatim** (28-D3 / 33-D3: session titles
  and prompts leak). Summarise; link a path or a commit.
- **No `sleep` loops over `read`.** To wait, `wait` — it rides `tail -F`
  (inotify) on the hub and returns on the event (R-AWAIT).
- **No ssh per post in a loop you wrote yourself.** `room.py` keeps ONE
  mux per box; 100 raw ssh handshakes at once lost 26–46% to the hub's
  `MaxStartups`.
