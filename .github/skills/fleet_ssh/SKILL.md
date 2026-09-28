---
name: fleet_ssh
description: SCOPE — any box named in the utterance (c01, c02, ...) is the scope; name none and it is the whole fleet. TABLE — column 1 is the box, then one column per thing asked. FAN OUT — write the bash that answers it on ONE box and run it everywhere with `fleet-ssh.sh [-b BOXES] COL=CMD` (ssh + parallel --tag), then print the table.
argument-hint: "fleet-ssh.sh COL=CMD ... [-b c01,c02] [-t wsl|u|win|e] [-j N] — run the command the user ASKED FOR; recipes.sh <name> ONLY when they named a recipe or asked for a full readiness sweep"
location: project
---

# fleet_ssh — one probe, every box, one table

```bash
.github/skills/fleet_ssh/fleet-ssh.sh node='node -v' docker='docker --version'
```

```
BOX  NODE      DOCKER
c01  v24.20.0  Docker version 29.8.0, build 88096ef
c02  v24.20.0  Docker version 29.8.0, build 88096ef
c03  v24.21.0  Docker version 29.8.0, build 88096ef
c04  v24.21.0  Docker version 29.8.0, build 88096ef
```

**Column 1 is the box. Every other column is one query.** That layout is
the point: a fleet answer is a *matrix*, and a matrix read as prose hides
the one box that differs. The eye finds `c03  v24.21.0` in a column; it
does not find it in four sentences.

## The core test: can bash answer it on ONE box?

Before anything else, ask **one** question of the user's words:

> *Could I answer this by typing a command into a shell on a single box?*

If **yes** — that command is the PROBE, and this skill's whole job is to
run it on every box at once and table the answers. Take the query. Fan it
out. There is nothing else to decide.

If **no** — it is not a fleet_ssh request at all (it wants a file edited,
a decision made, a plan read).

That test is the entire intent parse. It is not "which recipe is this?",
not "is this tool one I know?", not "what does the user really want?" —
those questions have produced every wrong answer this skill has given.
"how many apt packages" passes the test (`dpkg-query -W | wc -l`), so it
runs. So does "how much RAM", "what kernel", "is /etc/foo there", and any
other sentence a shell can settle.

## Then split it into exactly two parts

Every request that passes the test has the same shape, and nothing else:

| part | question | becomes |
|------|----------|---------|
| **1. SCOPE** | which boxes? whole fleet, or a named subset? | `-b c01,c02` — or omit for all |
| **2. PROBE** | what one command answers it, run on each box? | `COL=CMD` |

Then hand both to the wrapper. It fans out with `parallel --tag`, one
ssh per box, and renders the table. **That is the entire job.**

```
"rg version on c01 and c02"
      |            └── SCOPE: c01,c02          -> -b c01,c02
      └── PROBE: rg --version                  -> rg='rg --version'
```

Scope is often *implied* — "everywhere", "the fleet", or simply unstated
means all boxes, so omit `-b`. Name boxes only when the user did.

There is no third part. No intent classification, no recipe lookup, no
judgement about what the user "really" wants to know. If you find
yourself deciding *which sweep this resembles*, you have left the model.

**THE PROBE IS ANY BASH THAT ANSWERS THE QUESTION.** Not a tool name,
not a version check — *any command line*. If the user's question could be
answered by typing something into a shell on one box, the probe is that
something, and this skill's entire job is to run it on every box at once.

    "how much RAM"        free -g | sed -n '2s/  */ /gp' | cut -d' ' -f2
    "kernel version"      uname -r
    "is the disk filling" df -h / | tail -1 | tr -s ' ' | cut -d' ' -f5
    "who is logged in"    who | wc -l
    "does /etc/foo exist" test -f /etc/foo && echo y || echo NO
    "biggest dir in /var" du -sh /var/* 2>/dev/null | sort -rh | head -1

(Those first and third use `cut`/`tr` rather than `awk '{print $N}'`
purely so this document survives being rendered by a loader that eats
`$` sigils — see the quoting-death note below. In a real invocation the
awk form is fine: the probe rides to the box on **stdin**, so nothing
between here and the remote shell reinterprets it.)

None of those are version checks and none map to a recipe. **Version
queries are just the most common case, not the shape of the thing.**
Think: *what would I type on one box to answer this?* — then hand it
over and let the wrapper fan it out.

There is no catalogue of supported probes, because the probe is just a
shell command and every box has a shell.

The failure this forbids: reading a query for a tool no recipe covers,
finding no match, and concluding *"no PROBE given"* — then asking the
user to restate what they already said plainly. "awk and grep version"
is a complete, unambiguous probe. Treating an unrecognised tool as an
absent one turns the whole skill into a lookup table with nine entries,
which is the opposite of a shell fan-out.

**THERE IS NO "EMPTY INVOCATION" CASE. LOOK AT THE CONVERSATION.**

When `/fleet_ssh` is invoked, the skill body arrives on its own — the
user's sentence is NOT appended to it. The query is in the message that
triggered the invocation, or in the turn just before it. **Read there.**

An earlier version of this file said a probe was missing when the user
"named no command and no tool at all — e.g. `/fleet_ssh` with an empty
message". That sentence was a bug, and a self-fulfilling one: the skill
body always looks empty, so the escape hatch always seemed to apply, and
the answer was always "name a probe and I will run it" — to a user who
had just named one.

So: never conclude the query is absent because the skill block carries
no arguments. It never does. Scroll up.

**If the utterance is genuinely not visible, RECOVER it — do not guess.**
Use **`events.jsonl`, filtering out blank entries**:

```bash
S="${COPILOT_AGENT_SESSION_ID:?}"
jq -r 'select(.type=="user.message") | .data.content // empty | select(length>0)' \
  "$HOME/.copilot/session-state/$S/events.jsonl" | tail -n 1
```

The last NON-EMPTY entry IS the utterance. Parse it exactly as if it had
arrived inline. Read no other session. The injected skill block is NEVER
the utterance.

:*** trap: `select(length>0)` IS THE WHOLE FIX, AND WITHOUT IT THE PATH
LOOKS PERMANENTLY DEAD. *** The stream carries blank `user.message`
entries (a skill invocation writes one), so the documented
`… // empty' | tail -n 1` returns an EMPTY STRING even when the utterance
is sitting two lines above it. MEASURED 2026-09-27, same file, same
second:

```
naive  … // empty       | tail -1   ->  (blank)
fixed  … | select(length>0) | tail -1  ->  /fleet_ssh all cluster git pull
```

29 `user.message` events present, file live (2.9 MB, mtime current).

:*** trap: AND THAT BLANK IS WHY THIS FILE PREVIOUSLY DECLARED THE PATH
DEAD — A WRONG DIAGNOSIS THAT SURVIVED A WHOLE REVISION. *** The text
here used to say the directory "**does not exist** for the running
session … the file is never written, so the recovery is permanently
dead." MEASURED 2026-09-27 on the same driver: the directory **exists**,
`events.jsonl` is **2032 lines and being appended to right now**, and the
`jq` recovers the current turn once blanks are skipped. The empty output
was read as a missing FILE when it was a missing FILTER — so the previous
fix replaced a working tool with a worse one. **When a probe returns
blank, `ls` the path before concluding anything about it.**

:*** trap: `session_store_sql` ONLY HOLDS *COMPLETED* TURNS, SO IT CANNOT
SEE THE TURN YOU ARE IN. *** It is a fine cross-session tool and a
**wrong** recovery for the current utterance. MEASURED 2026-09-27: mid-turn
it returned turn **13** (`update c01 and c13`) as newest — the PREVIOUS
turn, already executed — and turn 14 (`/fleet_ssh all cluster git pull`)
appeared only after that turn ended, timestamped at the end boundary.

That is the most dangerous possible failure: it returns a real utterance
from this very session, correctly formed and recent, that the user is NOT
currently asking. Acting on it re-runs the last request instead of the
new one, and nothing about the answer looks wrong. Use it only to read
turns you know are finished.

:*** trap: `~/.copilot/session-store.db` IS NOT STALE — `immutable=1` MAKES
IT LOOK STALE. *** This paragraph twice claimed the file was days behind.
Both claims were WRONG, and the cause is one URI flag.

SQLite here runs in **WAL mode**, so recent writes live in the `-wal`
sidecar, not the main `.db`. `immutable=1` promises the file never
changes, so SQLite **skips the WAL entirely** — you read the last
checkpoint and nothing since. The main file's mtime is the checkpoint
date, which is why `ls` appears to corroborate the wrong conclusion.
MEASURED 2026-09-27, same file, same second:

```
ls: session-store.db      Sep 26 14:11     <- looks a day old
    session-store.db-wal  Sep 27 03:03     <- the truth, 4.2 MB of it

?mode=ro&immutable=1   turns=425  newest=2026-09-26T12:51   <- the "stale" read
?mode=ro               turns=435  newest=2026-09-27T03:03   <- current
```

**Read it with `?mode=ro` and it is LIVE** — it even carries the
IN-FLIGHT turn (turn 15 appeared while that turn was executing), which is
more than the `session_store_sql` tool offers. 12 rapid reads against the
running CLI: 12/12 ok, 14 ms total, so `mode=ro` does not fight the
writer.

:trap: **THE FLAG IS CORRECT WHERE IT WAS COPIED FROM.**
`session_rescue`'s `repair.py`/`pack.py` use `immutable=1` deliberately —
they repair a session and must not race its writer, and a checkpoint-only
snapshot is exactly right there. Copying it into a *liveness* query
inverts its meaning: the same flag that guarantees safety guarantees
staleness. **Match the flag to the question — `immutable=1` to inspect a
frozen past, `mode=ro` to ask what is true now.**
Full timings for all three session sources, and why the collection ladder
starts at sqlite rather than `ps`:
[`session-query-cost-and-the-wal-trap.md`](../../REPL/fix.archive/session-query-cost-and-the-wal-trap.md)

:*** trap: WHEN RECOVERY RETURNS EMPTY, ASK -- DO NOT PICK A SWEEP.
*** MEASURED 2026-09-26: recovery printed NOTHING on every attempt in one
session, and the gap was filled by *guessing* a plausible sweep --
`recipes.sh mesh`, a **930-dial** square nobody asked for. The table
rendered beautifully and answered a question the user never asked.

:note: the 2026-09-27 recovery showed the guess was not arbitrary — the
user's PREVIOUS turn had contained the word `mesh` (they were saying the
`ghcp` recipe should not invoke it). The guess echoed a nearby token and
felt like inference. **That is what makes this failure mode dangerous:
a guess assembled from context carries the *feeling* of a deduction.**
Plausibility is not recovery.

An empty recovery is the ONE case where a one-line question is correct,
and it is cheap: 930 dials is not.  The rule against refusing (below) is
about a query you CAN see and do not recognise -- "awk version" is a
probe even though no recipe covers awk.  It is NOT a licence to invent a
query you cannot see.  The two failures are opposite:

| situation | wrong move | right move |
|---|---|---|
| query visible, tool unfamiliar | refuse / ask to restate | RUN it -- any bash is a probe |
| query genuinely invisible | invent a sweep | RECOVER from `events.jsonl` with `select(length>0)`; ask only if that is empty too |

:*** AND IF A RECOVERY PATH IS BROKEN, FIX IT -- DO NOT DOCUMENT AROUND
IT. *** On 2026-09-26 the empty `jq` was met by writing the trap above
and asking the user. That was better than guessing and still not enough:
thirty seconds of `ls` would have shown the file was *missing* rather
than late, and the skill shipped another day pointing at a dead path.
A tool that returns nothing is a **defect to diagnose**, not a condition
to handle.

**A recipe name is never a default.** `mesh`, `matrix` and `stages` are
the most expensive things here; reaching for one to fill a blank is how
a sweep becomes both wrong AND slow.

| the user says | SCOPE | PROBE | run exactly this |
|---|---|---|---|
| "rg version on c01 and c02" | c01,c02 | `rg --version` | `fleet-ssh.sh -b c01,c02 rg='rg --version'` |
| "is docker up everywhere" | all | `systemctl is-active docker` | `fleet-ssh.sh docker='systemctl is-active docker'` |
| "check node" | all | `node -v` | `fleet-ssh.sh node='node -v'` |
| "awk and grep version" | all | `awk --version`, `grep --version` | `fleet-ssh.sh awk='awk --version \| head -1' grep='grep --version \| head -1'` |
| "run the base recipe" | — | *named a recipe* | `recipes.sh base` |
| "is the fleet ready" | — | *named a sweep* | `recipes.sh stages` |

Only the last two name a recipe. The first three would be **wrong** as
`recipes.sh runtime` — that answers a question nobody asked, on boxes
nobody named, and buries the one column that was wanted among five.

**EMIT THE TABLE AND STOP.** The table IS the answer. No preamble, no
restatement of the parse, no "no drift detected" summary, no caveats
about probe reliability, no offer of next steps. The matrix already says
everything -- that is the entire reason the output is a matrix.

A reader scanning four columns does not want a paragraph telling them
what they can already see, and a summary line is worse than redundant:
it is a fleet verdict, which R-FLEET exists to forbid.

**A red cell is not a work item.** If a sweep shows a failure, report the
table. Chasing it — capturing panes, reading logs, opening the plan doc
— is a *different task* the user has not asked for yet.

### Recipes are shorthand, invoked by name

They exist so a *repeated* sweep is one word. They are not an
interpretation layer over the user's sentence:

```bash
.github/skills/fleet_ssh/recipes.sh list      # what exists
.github/skills/fleet_ssh/recipes.sh name      # which box/island am I on (c01 odsp ...)
.github/skills/fleet_ssh/recipes.sh stages    # all three checkpoints
.github/skills/fleet_ssh/recipes.sh base      # just stage 1
```

**Three of them are the readiness ladder**, and `stages` runs all three:

| recipe | stage | answers |
|--------|-------|---------|
| `stages` | **all** | the three below, labelled, in order |
| `base` | **1** | bootstrap: rg, jq, parallel, git, git-lfs, tmux |
| `service` | **2** | **three** services: lserver + :11434, mcp sock + :47390, fleet-token :11435 |
| `harness` | **3** | H1 image, H2 api, H3 emacs |

Stage 1 has a fourth member that needs no probe: **ssh IS the
bootstrap**. If a row appears at all, that box passed it; an
`(unreachable)` row is the stage-0 failure. An `ssh_ok=y` column would
be true by construction and is deliberately absent.

`stages` *dispatches* to the three rather than merging their probes,
because each carries its own corrected tier — stage 1 is root's
(packages are machine state), stage 2 is the human's (the services and
their tmux socket are theirs). Flattening them would ask stage 2 as root
and print a false red on every box.

The rest answer narrower questions:

| recipe | kind | answers |
|--------|------|---------|
| `name` | LOCAL | **which box am I?** `hostname` says `CPC-bazho-RP0DF`, the fleet says `c01`. Prints box, host, ip, island, region, project and the tmux session for THIS box by default; `name all`, `name cj05`, `name <host>` or `name <ip>` looks up others. No ssh: reads `~/.fleet/fleet-connection.json` (edges merged across observers), and `fleet-ips.json` fills gaps (e.g. cj02/05/08 island) |
| `runtime` | DEPS | node / docker / dotnet / python versions |
| `copilot` | DEPS | GHCP CLI version per box |
| `images` | DEPS | Arcadia base images + officeagent |
| `ghcp` | PROCS | **who is driving**: live copilot sessions — name, ip, host, last query |
| `fleet-top` | PROCS (live) | `bin/fleet-top.py [-b BOXES] [--json / --stream]` — not a recipes.sh entry: the **live** `ghcp`. One persistent ssh per box streams collector snaps; change -> screen median 0.31 s, watcher <=0.43 % core (MEASURED 2026-09-27, 10 ODSP boxes, [fix.archive/fleet-top-pull-over-ssh.md](../../REPL/fix.archive/fleet-top-pull-over-ssh.md)). WSL sessions only |
| `tmux` | PROCS | tmux sessions across **all four sockets** (see below) |
| `listeners` | PROCS | every listening TCP port |
| `disk` | PROCS | free space + docker footprint |
| `defend` | PROCS | is the WSL-crash defence ARMED and ENABLED? (2 tiers) |
| `matrix` | **MESH** | the full **N×N** square — every ordered pair, dialled with a real ssh |
| `mesh` | **MESH** | 31×31 **latency** square (930 dials, :2200): `*` self, ms per cell, `X` dark, `?` row lost; always saved to `/tmp/fleet_latency.md`. Cross-island cells ride sea, whose `MaxStartups 10:30:100` throttles bursts — inner fan capped `MESH_J=6`, row login + dials retried with 1–4s jitter. MEASURED 2026-09-26: 926/930 with c13 BACK (it is `30/30` out and reached by every row), 4 dark cells -- `cj06->c04`, `c02->cj02`, `c11->c03`, `c15->cj08` -- each ISOLATED, i.e. single broken pairs, not a dark row or column.  An earlier run read 829/930 while c13 was down; a mesh number is an OBSERVATION, so quote its date |
| `meshcfg` | MESH | (was `mesh`) per-box ssh-config coverage, no latency |
| `broadcast` | **WRITE** | copy one dir **or one docker image** from one box to every peer, over the mesh |
| `clean` | **DESTROY** | reap what `ghcp` lists: remove dead session state, optionally kill parked agents |

:trap: **`copilot` and `ghcp` are not the same sweep.** `copilot` is DEPS
— *is the CLI installed, same version everywhere*. `ghcp` is PROCS — *is
an agent running right now, and what was it last asked*. A box can pass
`copilot` with no session on it, and that is the common case.

`ghcp` reads liveness from the **`inuse.<pid>.lock`** the CLI drops in the
session dir it is attached to, then re-checks that pid against
`/proc/<pid>/cmdline`. Globbing `session-state/*/` instead would count
every session the box has *ever* run — measured here: 6 dirs, 1 live —
and name a stale one as the current driver. The lock alone is not enough
either: it survives a crash, and pids get recycled.

```
$ recipes.sh ghcp
BOX  SESSION                   IP           HOST             STATE                  LSAGE   QUERY
m01  1:(unnamed) | 2:token_09  10.30.2.154  CPC-bazho-RP0DF  1:NOLOG | 2:WAIT/782s  783s    1:(nolog) | 2:(blank)
m02  1:harness.07              10.30.2.95   CPC-bazho-PMBMN  1:ERR/599s             7848s   1:/exec_plan 07 push to harness
m03  -                         10.30.5.71   CPC-bazho-8SBST  -                      65662s  -
m04  1:add recipe to skill...  10.30.5.25   CPC-bazho-0U0P5  1:BUSY/1s              1s      1:not forget lots of box has
m05  1:git clone bin2md        10.30.5.74   CPC-bazho-ZLP0K  1:WAIT/3215s           3215s   1:git clone bin2md
```

### When the merged row gets too wide: SPLIT BY TIER, one table each

The single-row form above carries BOTH tiers on one line (`w`-tagged and
`c`-tagged fields). At 5 sessions on one box that row is ~200 columns and
the eye can no longer land on a cell. USER RULING 2026-09-22 after a
two-tier sweep rendered as two tables: *"that is much more clear format"*.

So when a box runs several sessions, emit **one table per tier** rather
than one wide row per box:

```
## WSL distro tier
BOX  SESSION                                          STATE                                    QUERY
m01  1:windows.replacement | 2:fleet_ghcp | 3:(unnamed)  1:ERR/7604s | 2:ERR/129695s | 3:NOLOG  1:(blank) | 2:edit skill fleet_ssh | 3:(nolog)
m03  1:cowork.03.plan | 2:OA.helper                   1:WAIT/127605s | 2:WAIT/286027s          1:(blank) | 2:/fleet_ssh ghcp

## Container tier
BOX  TIER(PROOF)                                 SESSION            STATE            QUERY
m01  CPC-bazho-RP0DFctr [Microsoft Azure Linux]  c1:/fleet_ssh ghcp c1:BUSY/217525s  c1:do we copy the new bundle
m03  CPC-bazho-8SBSTctr [Microsoft Azure Linux]  -                  -                -
```

Two things the split BUYS, beyond width:

1. **`TIER(PROOF)` becomes a column, not a footnote.** The container
   table carries the hostname AND the OS, so `Microsoft Azure Linux` with
   a `…ctr` suffix is visible per row. A row showing `Ubuntu` means the
   probe fell back to the distro — the silent-hop failure this file
   records for `-t win`, and the reason a *proof* column beats a prose
   assurance that the tier landed.
2. **`IP`/`HOST`/`LSAGE` drop out when nobody asked for them.** They are
   box identity, not session state; carrying them in a session sweep is
   what pushed the merged row past readable. Add them back when the
   question is about the box.

:trap: **SPLITTING IS A RENDERING CHOICE, NOT A SECOND SOURCE OF TRUTH.**
Both tables must come from the SAME probe semantics — the lock+pid
re-check, the numbered fields, the three distinct empties. A split that
re-implements the probe per tier will drift, and the drift shows up as
one tier quietly disagreeing with the other.

:trap: **THE INDEX PREFIX STILL MATTERS INSIDE A SPLIT TABLE.** With one
tier per table the `w`/`c` layer letter is redundant, but the NUMBER is
not: `1:`/`2:` is what joins SESSION to STATE to QUERY when a field is
empty. Dropping it re-opens the gap-pairing bug recorded below.

**A box running several agents is the normal case, not the edge**, so every
per-session column emits one field per session and numbers it. The index is
the join: `2:WAIT/782s` belongs to `2:token_09`. Measured 2026-09-17, m01 ran
two — a `head -1` anywhere in these columns would report one and look correct
doing it.

Numbering exists because position alone was not enough. On m01 an unnamed
session printed an *empty* field, so SESSION held one entry while STATE held
two — the eye pairs the first state with the only name and reports the
**healthy** session as `NOLOG`. A visible `1:` makes a gap a gap.

:trap: **`paste -sd"; "` does not join on `"; "` — it alternates.** `-d`
is a *list* of delimiters used in rotation, so at three or more sessions the
separators cycle `;`, ` `, `;`, ` `. On a 4-session fixture:

```
session n;session n session n;session n
```

Sessions 2 and 3 are divided by a bare space — indistinguishable from a space
*inside* a name, so two sessions read as one. Invisible at N=2, which was the
whole fleet when this was written; it took a fixture to find. Join on one
character, expand after.

:trap: **`LSAGE` is per BOX, not per session.** One lserver serves every agent
on the machine, so its mtime is the newest request from *any* of them. On a
multi-session box a hot `LSAGE` proves only that at least one is working —
pairing it with `1:WAIT` would be a fabricated confirmation. It is
deliberately left unnumbered: the missing index is the signal that it belongs
to the row, not a session. It can refute "everything here is parked"; it
cannot name which one is busy.

:trap: **AN EMPTY QUERY DOES NOT MEAN "WAITING FOR INPUT".** It is the
question that produced `STATE`, and it has three causes that the one cell
cannot tell apart — measured across five boxes, only *one* was the
waiting case:

| cell | cause |
|---|---|
| `-` | no live session at all — the box is idle (m03) |
| `(nolog)` | live lock, no readable `events.jsonl` — a session dir exists before its log does, so this is a **race**, not a state (m01) |
| `(blank)` | the user really did send a whitespace-only message (m01) |

Read as "idle", `(nolog)` is a false negative: m01 had **two** live locks,
one mid-startup beside a healthy 3.8M log.

**`STATE` is the last event type**, which is what actually separates them —
`assistant.turn_end` → `WAIT` (the prompt is the user's), mid-turn events →
`BUSY`, `session.error` → `ERR`. That last one matters: without it m02's
crashed session reads as `WAIT`, which is backwards — nobody is waiting, it
fell over. The age beside it is what makes `WAIT` legible: `WAIT/3s` is a
human typing, `WAIT/3044s` is an abandoned box.

**`LSAGE` is the corroboration, not a verdict.** lserver is the model proxy,
so a `BUSY` agent must be making requests and a parked one must not. The two
ages agreeing is the confirmation; `BUSY` beside a stale `LSAGE` is the
disagreement worth chasing. They stay two columns because merging them into
one "confirmed" flag would hide exactly that.

:trap: **lserver is on the HUMAN's socket, and capturing its pane as root
lies uniformly.** A bare `tmux capture-pane -t lserver` over `-t wsl`
returned **0 lines on 5/5** — a clean, consistent, entirely false "every
proxy is dead". (This file says above that lserver moved to root with the
bundle's supervisor; measured 2026-09-17 it answers on uid 1000 and
`/tmp/tmux-0/default` does not exist at all.) `LSAGE` therefore reads the
**log directory mtime**, which needs no socket, no tier and no user — so it
cannot produce that false negative.

### `clean` — the reaper for what `ghcp` lists

`ghcp` **answers** "who is driving". `clean` **acts** on that answer:
remove the session state nothing is running, and — only when explicitly
asked — stop agents that have been parked past a threshold.

```bash
recipes.sh clean                       # REPORT: what WOULD go.  The default.
recipes.sh clean --apply               # remove dead session state
recipes.sh clean --apply --idle 86400  # ALSO kill agents parked >24h
recipes.sh clean -b c03                # one box
```

```
== clean c01,c02,c03,c04,c05,c06  MODE=report ==
== REPORT ONLY -- nothing is removed.  Add --apply to act. ==
-- tier wsl --
c01  RM=16 KILL=0 VETO=0 KEPT=4 PRUNED=0 MODE=report
c03  RM=39 KILL=0 VETO=0 KEPT=4 PRUNED=0 MODE=report
c06  (unreachable)
-- tier ctr --
c02  RM=9  KILL=0 VETO=0 KEPT=4 PRUNED=0 MODE=report
```

MEASURED 2026-09-21 before this existed: **88 session dirs across 5 boxes,
11 of them live.** c03 alone carried 42 dirs for 3 live sessions.

**It classifies into five states, and only two are ever touched:**

| class | means | action |
|---|---|---|
| `STALE` | no live copilot holds it | **removed** |
| `IDLE` | live, parked (`WAIT`/`ERR`) past `--idle` | **killed**, if its pid is alone |
| `LIVE` | working, or parked under the threshold | kept |
| `SELF` | the caller's own session | kept, always |
| `YOUNG` | lockless but newer than `MIN_AGE` | kept |

**Deleting and killing are separate opt-ins, because they are different
claims.** Removing a `STALE` dir reclaims disk from a session that already
ended — it cannot lose work. Killing an `IDLE` session **ends a live
agent**, and "parked 24h" is a heuristic, not a fact about whether its
human is done. MEASURED: c04's only session was `WAIT/213007s` — 2.5 days
parked, and still the box's sole driver. So `--idle` must be typed, with
its threshold, every time.

:trap: **ONE PROCESS CAN HOLD SEVERAL SESSIONS, SO THE KILL UNIT IS NOT
THE SESSION.** MEASURED on c01: pid 34966 holds **both** `7ba4caa0`
(`NOLOG`) and `7d0cfcfa` (`WAIT/155846s`). The lock is per-session but the
kill is per-process, so "reap this idle session" reads as "kill 34966" and
takes the other session with it. A pid is killable only when **every** dir
it holds is idle; one live dir **vetoes** the pid and the row says so:

```
VETO gggg-pair-idle pid=900004 (pid also holds a live session)
```

:trap: **THERE IS A SECOND REGISTRY, AND DIRS ALONE DO NOT PRUNE IT.**
`~/.copilot/open-sessions-state.json` keys the same uuids independently of
the directories. MEASURED on c01: `d92d5830` sits there `"working": true`
with no dir lock at all. `clean` prunes exactly the keys whose dir is now
gone — derived from the filesystem, never a second source of truth.
Verified on c04: 9 dirs → 2, registry 5 keys → 2, and the two sets match.

:trap: **THE DRIVER IS ONE OF THE BOXES.** This cluster is driven from a
container on c01, so an unguarded sweep deletes the state of the session
running it. `$COPILOT_AGENT_SESSION_ID` is passed as `PROTECT`
automatically. Belt-and-braces: that session is also `BUSY` (it is
executing the sweep), so the `LIVE` rule already spares it — but only
while mid-turn, and a reap scheduled *between* turns would find it `WAIT`.

:trap: **NOLOG IS NOT IDLE.** A session dir exists before its
`events.jsonl` does, so a starting agent and a logless corpse are
identical *in the log*. The lock is what separates them, which is why
`NOLOG`-with-a-live-pid is classed `LIVE`. `MIN_AGE` (1h) is the same
guard one layer out: a dir younger than that is never removed even with no
lock, because the lock is written *after* the dir.

:trap: **IT CLEANS BOTH TIERS, BECAUSE `ghcp` READS BOTH.** MEASURED: the
container tier held 9 more reapable dirs on c02 that a wsl-only sweep
never sees — cleaning one tier reports a tidy fleet while half the garbage
remains.

:trap: **A DEAD BOX MUST STILL GET A ROW.** Output is whitelisted to the
record grammar (`RM=`/`RM`/`KILL`/`VETO`) rather than blacklisting MOTD
banners and `setlocale` noise — a blacklist grows one entry per distro and
silently passes what it has not met. But the whitelist then drops ssh's
error text too, and MEASURED, **c06 disappeared from the report entirely**:
five boxes rendered and the sixth was simply absent, which reads as
complete. Empty record sets now render `(unreachable)` or `(no sessions)`.

Because it is destructive it does **not** go through the table wrapper —
that takes only the first line, which would print the counts and discard
every `RM`/`KILL`/`VETO` record beneath it, i.e. exactly which session was
destroyed. It fans the script out with `parallel --tag`, like `broadcast`.

**Graded against a fixture, never the fleet** —
`bench/clean-bench.sh`, 10/10. Every other bench here may use real boxes
because every other sweep reads; testing a reaper on a box means performing
the destructive act. The fixture is 11 dirs covering every class, a fake
`/proc`, and a fake `kill`. Mutation-tested on five rules (`veto`, `self`,
`floor`, `deadpid`, `idleage`), each of which must produce a different
answer. Two findings came straight out of building it:

- the `floor` mutant initially **passed** — the fixture had no young
  lockless dir, so the rule was never graded;
- the `deadpid` mutant left the *identical survivor set* while
  **signalling a process the baseline never touches** (`KILL=1`→`2`).
  "Same dirs remain" and "same acts performed" are different claims, and
  only the second is safety — so mutants are graded on counts **and**
  survivors.

:trap: **A BACKTICK IN A COMMENT INSIDE THE `parallel` BODY IS STILL
COMMAND SUBSTITUTION.** The body is double-quoted, so bash expands the
whole string before any shell sees a `#`. A prose comment cost a
`command not found` on the driver, printed beside an otherwise correct
table.

:trap: **`ssh cNNwsl` then `tmux ls` SHOWS YOU ONE SESSION OF THREE.**
There is no single tmux server on these boxes. MEASURED on c02:

```
$ recipes.sh tmux
BOX  ROOT     HUMAN  MCP_SOCK        CONTAINER
c02  lserver  -      wwwrootsdx-mcp  api-server
```

Three reasons they cannot share a list:

1. a tmux server is **per-user** (`/tmp/tmux-<uid>/`), and `cNNwsl` logs
   you in as **root** — `cNNu` is the human;
2. **lserver runs as root now**, because the bundle's
   `install-tmux-service.sh` renders `SERVICE_USER=root`. (This is why
   `service-up.sh` once called a HEALTHY lserver
   `not-attachable-or-empty` — it asked the human's socket.)
3. **`wwwrootsdx-mcp` is not on a default socket at all** — explicit
   `-S ~/.local/state/wwwrootsdx/tmux.sock`, so even as the human a bare
   `tmux ls` misses it.

Attach, per session:

```bash
ssh cNNwsl 'tmux attach -t lserver'                 # root tier
ssh cNNu   'tmux -S ~/.local/state/wwwrootsdx/tmux.sock attach -t wwwrootsdx-mcp'
ssh cNN    'tmux attach -t api-server'              # container, BARE alias
```

Or ask lserver's supervisor, which is socket-agnostic:
`sudo /workspace/lserver/L-server/bin/l-server-tmux status|capture 50`.

```
$ recipes.sh service
BOX  LSERVER  P11434  MCP   P47390
c01  21       ok      sock  LISTEN
c02  21       ok      sock  LISTEN
c03  21       ok      sock  LISTEN
c04  21       ok      sock  LISTEN
```

`defend` is the one recipe that is **not** a status question, and the
distinction is the whole reason it exists:

```
service   is it up RIGHT NOW?
defend    when it dies, does it come BACK — with nobody watching?
```

Those two diverged for **seven hours** on 2026-09-16. Every port was green
on 5/5 while the lserver session was unreachable on 5/5, because the
boot-time supervisor had hit an unrecoverable state and *nothing on the box
re-ran it*. **A green `service` table is not evidence of defence.**

```
$ recipes.sh defend
== WSL: is the guard ARMED (active) and will it SURVIVE a reboot (enabled) ==
BOX  KEEPALIVE  KA_EN    SUPERV  SV_EN    MCP_T   BOOTCMD
c01  active     enabled  active  enabled  active  1
...
== WINDOWS: the only thing that STARTS the VM ==
BOX  BOOTTASK  BOOT_RC  VMWP
c01  Running   267009   1
```

:trap: **`is-active` is not `is-enabled`, and the gap is invisible.** A
guard that is active now but not enabled is armed *until the next reboot*
and silently absent after it — which is exactly the window this recipe
checks. Both columns are printed on purpose; a `disabled` beside a green
`active` is the finding.

:trap: **`BOOT_RC 267009` (`0x41301` = `SCHED_S_TASK_RUNNING`) is HEALTHY.**
It reads like an error code and is not one: the task's action ends in
`exec sleep infinity`, so it never finishes and never reports an exit
code. Its neighbours mean the opposite —

| code | hex | meaning |
|------|-----|---------|
| `267009` | `0x41301` | running — the `sleep infinity` is alive |
| `267011` | `0x41303` | never ran — owner logged off, `InteractiveToken` had no session |
| `3221225786` | `0xC000013A` | `STATUS_CONTROL_C_EXIT` — action **killed**; VM alive, nothing re-ran `systemctl start ssh`. State reads `Ready`, which looks fine. |

:trap: **`BOOT_RC` is a proxy for the TASK, not the VM.** MEASURED on c05:
`VMWP=0` while the task reported `Running`. That is why `VMWP` sits in the
same table — `Running` beside `VMWP=0` is the false green, and
`/End`-before-`/Run` is the fix (`IgnoreNew` silently discards a bare
`/Run`).

:trap: **five layers, two tiers, and only one of them can START a VM.**
`wsl-keepalive` and `vmIdleTimeout=-1` both keep a *running* VM alive and
neither can launch a stopped one; only the Windows-tier `fleet-wsl-boot`
task does that. Asking one tier answers half the question.

`matrix` is the fleet answer at its strongest shape — **a square, not a
count**. Every cell is its own real ssh dial, so N boxes cost N² dials:
5×5=25 today, **16×16=256**, **30×30=900** at full fleet.

```bash
recipes.sh matrix        # container tier (:2222) — the default
recipes.sh matrix wsl    # distro tier (:2200)
```

```
FROM  c01 c02 c03 c04 c05 OK
c01   .   o   o   o   o   5/5
c02   o   .   o   o   o   5/5
c03   o   o   .   o   o   5/5
c04   o   o   o   .   o   5/5
c05   o   o   o   o   .   5/5
```

`o` reached · `X` dark · `.` the diagonal (self — a **real** dial, drawn
differently only so the eye can find it). MEASURED 2026-09-19: 25/25 in
**22s**.

**Read it as shapes.** This is why the square beats every count-shaped
view — the geometry names the culprit before you read a single label:

| shape | means |
|---|---|
| a dark **ROW** | that box cannot dial **OUT** — its config or its route |
| a dark **COLUMN** | that box cannot be **REACHED** — its sshd or its publish |
| one dark **CELL** | a single broken pair — a route, not a host |
| dark **DIAGONAL** | the self-dial only — the hairpin (below) |

**Asymmetry is the whole point.** `A→B` working while `B→A` fails is the
most informative state a mesh can be in, and a per-box `4/5` cannot
express it — `harness-mesh` tells you a peer is dark, never *which*, and
never in which direction. Mutation-tested: pointing one self entry at an
unroutable address produced exactly one `X`, on the diagonal, `4/5`, with
every other cell untouched.

:trap: **THE DIAGONAL IS A DIFFERENT ROUTE AND FAILS DIFFERENTLY.** A
peer arrives at the box's published port from outside; a box dialling
*itself* by its own 10.30 address must hairpin. MEASURED 2026-09-19 on
m01 — and it is a **routing table**, not a firewall:

```
ip route get 10.30.2.154
  m01: via 169.254.73.152 dev eth0 TABLE 128   <- hairpins via Windows
  m03: dev eth0 src 10.30.5.71                 <- direct, no table 128
```

m03 has no table 128 at all. The symptom was `kex_exchange_identification:
Connection closed by remote host`, which reads like a dead container —
the container was healthy and answered on `172.17.0.1:2222` (docker0)
instantly. Fixed by `bin/ctr-selfdial-fix.sh`, which points the SELF
entry at docker0 and leaves every peer entry on its `ProxyJump`.

:trap: **NEVER "FIX" A DARK DIAGONAL BY DELETING THE SELF BLOCK.** The
shape is N blocks *because* a box carries an entry for itself; dropping
it shrinks the map and makes it non-uniform.

:trap: **N² NEEDS A BOUNDED HOP AND A FANNED ROW.** Dials are fanned one
job per source **row** and run sequentially within a row, so wall time is
one row, not the square — at 30 boxes a serial square would be 900×~1s,
this is ~30. Every hop is bounded twice (`ConnectTimeout` + an outer
`timeout`): one unroutable peer otherwise costs a full TCP timeout, and
N of them cost minutes.

:trap: **DO NOT RENDER THE SQUARE FROM A COUNT.** Each cell must print
its own character from its own dial. A row that reports `4/5` with no
per-cell record cannot say which column was dark — which is the entire
information the square exists to carry.

`broadcast` is the ONLY recipe that **writes**, and it is deliberately
not a table:

```bash
recipes.sh broadcast c02 OfficeAgent             # DIR   -> rsync
recipes.sh broadcast c02 officeagent:devlatest   # IMAGE -> docker save|load
```

Everything else here reads, and `fleet-ssh.sh` takes only the first line
of output — built for reading, per "When NOT to use it" above. A copy
changes state on N boxes, so this fans a real `rsync` out with
`parallel --tag` and reports per peer instead.

:trap: **A DOCKER IMAGE IS NOT A DIRECTORY.** An image lives in the graph
driver, so rsync cannot move it — and the failure is not a clean error.
MEASURED 2026-09-17: `broadcast c02 officeagent:devlatest` resolved to
`/workspace/officeagent:devlatest`, which does not exist; the directory arm
runs `--delete`, so **a tag typo is a mirror of nothing onto four boxes.**
The image arm exists to make that unreachable.

**The arm is chosen by ASKING THE SOURCE'S DOCKER DAEMON**, not by looking
for a `:` in the string. A colon is not proof (a directory may contain one)
and its absence is not proof either (`officeagent` alone is a valid tag).
`docker image inspect` on the source settles it and **fails closed**: an
unknown tag is reported as such instead of falling through to rsync.

**Stream, never stage.** `docker save > file` then rsync then load writes
~19G to the source disk, reads it back, and writes it again per peer.
`save | pigz -1 | ssh | pigz -d | docker load` moves it once with no temp
file on either end. `pigz -1` because these layers are *already* compressed
— a higher ratio costs real time and buys almost nothing; it falls back to
`cat` if pigz is absent, since raw bytes beat no copy.

:trap: **GRADE ON THE PEER, NOT ON `rc`.** A broken pipe can still exit 0,
so each peer is re-asked with `docker image inspect` *after* the load and
its image Id is printed. Ids matching the source is the proof; `rc=0` alone
is not. MEASURED 2026-09-17, 18.7G to four peers in parallel: 4/4 `rc=0`,
all five boxes on `sha256:dde911e4bb4a`, **7m36s** wall.

:trap: **the `c`→`m` swap assumes the driver holds `cNN` aliases.** This
driver's `~/.ssh/config` had **only `mNN` stems**, so an unconditional
`m${peer#c}` built `c02wsl` for the source and returned
`Could not resolve hostname` — `rc=255` on 4/4, which reads like a dead
fleet rather than a naming bug. Strip either prefix (`${peer#[cm]}`) so
`c02` and `m02` name the same box.

**Why the mesh and not the driver.** The obvious version pulls to the
driver and pushes N times, moving the payload N+1 times over the slow
relay. The boxes reach each other directly on the 10.30 subnet via the
`mNNwsl` aliases, so the payload crosses the fast path ONCE per peer and
never touches the driver. MEASURED 2026-09-16 (plan 05): relay 7.820s vs
direct 0.308s, **25x**.

MEASURED 2026-09-17, 31G / 557,569 files from c02 to four peers in
parallel: all four `rc=0`, `Total transferred 31,173,300,853 bytes`, and
the file count matches 5/5. A re-run transfers **0 bytes** — rsync makes
it idempotent, so it is safe to repeat as a convergence check.

:trap: **`mNN` is the same box as `cNN`** — the prefix is the *route*, not
a different machine. Verified from c02: `m01wsl`→RP0DF, `m03wsl`→8SBST,
i.e. exactly c01…c05. So the destination alias is a `c`→`m` swap.

:trap: **the source box pushes.** rsync runs ON the source over ssh so the
delta/compress work happens between the two peers; driving it from the
driver would put the driver back in the middle of 31G.

:trap: **`--delete` makes it a MIRROR, and that is the point.** A copy
that merely "has the files" leaves a later diff meaningless. It also means
a wrong `<path>` argument deletes on four boxes at once — test a new path
on a throwaway directory first, as this recipe was.

:trap: the remote login shell emits a `setlocale` warning that crowded the
real stats line out of a `head -2`. Filtered explicitly; widening the
window would only move the truncation.

A recipe is worth adding **the second time you run the same sweep** —
that is the whole bar. What it really stores is not the command but the
*corrections*: `service` runs on `-t u` because the services are the
human's and their tmux socket is the human's (asking as root finds no
session and reports a false red), and `base` uses `dpkg -s` rather than
`command -v` because a package name is not a binary name (`ripgrep` ships
`rg`; `ca-certificates` ships nothing).

## The box list is DISCOVERED, never hardcoded

This is how **SCOPE** resolves when the user did not name boxes.
`~/.ssh/config` is the only thing that already knows which boxes exist and
how to reach them, and `fleet.py sshconfig` regenerates it as the fleet
grows. So the box list is derived from `Host cNN…` stems at run time.

A baked-in list is wrong the day box 5 arrives — and wrong **silently**,
because the sweep still returns a full, confident table for the boxes it
happens to know. Override with `-b` for a subset; set `FLEET_SSH_CONFIG`
to point elsewhere.

:trap: **the config carries the SCHEME, not the fleet.** `fleet.py
sshconfig` emits a `Host` block for every box the numbering scheme
predicts. After a regen, MEASURED 2026-09-13: 16 `cNN` stems in the
config, **4 that answer** (c01–c04); c05–c16 returned `(unreachable)`,
padding every default sweep with 12 dead rows.
Pin the default scope with `FLEET_SSH_BOXES`:

```bash
export FLEET_SSH_BOXES=c01,c02,c03,c04
```

:trap: do NOT filter on the `# CNN: UNVERIFIED` comment `fleet.py`
writes. That is a *provisioning* note, not a liveness fact — it is
stale for c03/c04, which are both flagged UNVERIFIED and both answer
every probe. Filtering on it would silently drop two working boxes.

## Flags

| flag | default | meaning |
|------|---------|---------|
| `-t TIER` | `wsl` | suffix appended to the box name: `wsl`, `u` (human), `ctr` (container, :2222), `e`/`eu` (emacs, :2223) |

### `-t win` IS GONE — R-NORELAY BANS WINDOWS sshd

**The `win` tier dialled `cNNwin` on port 22, which is a Windows sshd.
R-NORELAY forbids one.** That rule is not a style preference: it is a
written commitment this estate made to Cyber Defense Investigations on
2026-09-21, whose text names removing "the fleet key from
`administrators_authorized_keys`" explicitly.

MEASURED 2026-09-25, `:22` from the driver:

```
10.30.5.75   dark      10.30.1.102  dark      10.30.3.63   dark
```

Dark on every box, **by design**. So a `cNNwin` alias cannot resolve to
anything that answers, and `ssh -G cNNwin` echoing its own alias is the
CORRECT state, not a config gap to repair. Do not "fix" it.

**The Windows tier is still reachable — over WinRM (`:5985`), not ssh.**
That is the sanctioned path and it leaves nothing behind: no account, no
scheduled task, no service, no tunnel. It authenticates as the signed-in
human and each call is a transient session.

```bash
# Windows-tier fact, from a peer IN THE SAME PROJECT:
ssh <peer>wsl "cd /mnt/c && powershell.exe -NoProfile -NonInteractive -Command \
  \"Invoke-Command -ComputerName <ip> -ScriptBlock { <powershell> } -EA Stop\""
```

:trap: **PORT-OPEN IS NOT REMOTING-PERMITTED, AND IT VARIES BY REGION.**
Three distinct failure modes hide behind "WinRM didn't work":

| scope | `:5985` | `Invoke-Command` |
|---|---|---|
| same project | open | **works** |
| cross-project | open | **"Access is denied"** — creds are project-scoped |
| japaneast | **dark fleet-wide** | unavailable |

:trap: **WinRM OUTLIVES THE DISTRO IT INSPECTS, AND THAT IS WHY IT
MATTERS.** Reading `.wslconfig` through a dying box's own distro returned
EMPTY — which reads as "the config was wiped" and points straight at a
fix. Over WinRM the same file was `LEN=53` and correct; the empty answer
was the distro dying mid-command. **Never diagnose a dying box with a
probe that runs inside it.**
[`winrm-vs-devcenter-api-pick-by-power-state.md`](../../REPL/fix.archive/winrm-vs-devcenter-api-pick-by-power-state.md)

:trap: **THE ORIGINAL `win` BUG IS STILL WORTH KNOWING, because its shape
recurs.** On a `cNNwin` host sshd handed `bash -s` to whatever `bash` was
on the *Windows* PATH — WSL's bash — so the probe hopped back into the
distro and answered AS THE DISTRO under a "Windows" header. MEASURED
2026-09-13: `-t win os='uname -s'` returned **Linux on 4/4**. The failure
was silent AND uniform, and **4/4 agreeing reads as corroboration**.
*Uniformity across a fleet is evidence about the PROBE at least as often
as about the fleet.* The same assertion still guards `-t ctr`: `ctr` and
`wsl` must DISAGREE.

**THERE ARE TWO ssh TIERS, PLUS WinRM FOR WINDOWS.**
Port convention (user ruling 2026-09-13, implemented in `bin/fleet.py`):

| port | layer          | flag      | alias used            |
|------|----------------|-----------|-----------------------|
| 2200 | WSL distro     | `-t wsl`  | `cNNwsl` (default)    |
| 2200 | WSL, as human  | `-t u`    | `cNNu` — same host, user `bazhou` |
| 2222 | container sshd | `-t ctr`  | **none** — port on the wsl HostName |
| 2223 | emacs          | `-t e` / `-t eu` | `cNNe` / `cNNeu` |
| 5985 | **Windows**    | *not a `-t` tier* | WinRM — see above |

`22` is deliberately absent: that was `cNNwin`, and R-NORELAY bans it.

```bash
fleet-ssh.sh -t ctr os='head -1 /etc/os-release'   # answers INSIDE the container
```

:trap: **THIS FILE USED TO SAY "there is no `ctr` tier — the CONTAINER IS
THE BARE NAME", AND THAT WAS HALF RIGHT.** Correct: no `cNNctr` STEM exists
in `~/.ssh/config`. Wrong: the conclusion "so use the bare alias", which
only holds on a driver whose config HAS a bare `Host cNN` block. MEASURED
2026-09-18 — this driver's config carries **only `mNNwsl` and `mNNwin`**, so
the bare name resolved to nothing and every container probe had to be
hand-written as `docker exec` over the wsl tier. The container tier is a
**PORT**, not a suffix, so it cannot be expressed as `{}$TIER` at all; `-t
ctr` reads HostName + IdentityFile from the box's own **wsl** block (via
`ssh -G`, never by re-parsing the file) and dials `:2222`.

:trap: **A BARE `ssh -p 2222 root@<ip>` IS REJECTED, AND NOT FOR THE REASON
IT LOOKS LIKE.** MEASURED: `Permission denied (publickey,…)` on 3/3 — while
our key IS in the container's `authorized_keys` (`grep -c` = 2),
`PermitRootLogin yes`, `PubkeyAuthentication yes`, and `/root/.ssh` perms
are correct. `ssh -v` names the real cause: with **no `Host` block matching
the IP**, ssh never OFFERS `~/.ssh/nx.rsa` — it tries
`id_rsa`/`id_ecdsa`/`id_ed25519`, none of which exist, and gives up. Read as
"the container does not trust us", this sends you to fix `authorized_keys`,
which was never broken. Pass `-i` and `-p` explicitly.

:trap: **THE SAME MISSING `-i` MAKES A HAND REPRO ACCUSE THE RECIPE.** The
trap above is about an IP that matches no `Host` block; this is what that
costs when you re-run a recipe's dial BY HAND to check it. Recipes export
their own transport —

```
GIT_SSH_COMMAND='ssh -i /root/.ssh/nx.rsa -o BatchMode=yes -o ControlPath=none …'
```

— so a manual `git fetch ssh://root@<ip>:2200/…` omits the key, fails
`rc=128`, and destroys `.git/FETCH_HEAD` on the way out.

MEASURED 2026-09-22 on `reduce`: c01 (the driver, dialling ITSELF) printed
`contained`. The hand repro returned `rc=128`, so the row was diagnosed as a
FALSE GREEN — a stale `FETCH_HEAD` masking a dead dial — and a patch to
`recipes.sh` was nearly written. `bash -x` on the real run showed the fetch
**succeeding**: the recipe had the key, the hand repro did not. No defect
existed.

So the rule is symmetric with every other probe trap here: **reproduce the
TRANSPORT, not just the URL.** Either export the same `GIT_SSH_COMMAND`, or
trace the recipe (`bash -x`) instead of re-running a fragment of it.

To tell a real dial from a stale variable, DELETE the artifact first —
`rm -f .git/FETCH_HEAD`, fetch, and confirm it is recreated. A test that
cannot fail proves nothing, and `FETCH_HEAD` surviving from an earlier
`fetch origin` is exactly the thing that would make a dead dial look alive.

:trap: **PROVE THE TIER LANDED — the win tier's silent hop is the precedent.**
`ctr` and `wsl` must DISAGREE, and both columns are the assertion:

```
        -t ctr                            -t wsl
c08  NAME="Microsoft Azure Linux"      PRETTY_NAME="Ubuntu 26.04 LTS"
c08  CPC-bazho-U41JRctr                CPC-bazho-U41JR
```

A `ctr` row showing Ubuntu means the probe answered from the distro.

:trap: **USE `uname -n` FOR THE PROOF COLUMN, NOT `hostname` — AZURE
LINUX SHIPS NO `hostname` BINARY.**  MEASURED 2026-09-25 on c08: a `ctr`
sweep with `hn='hostname'` rendered `-` while the OS column correctly
read `Microsoft Azure Linux`.  That `-` is HONEST (the box answered, the
command printed nothing) but it reads as a broken tier, and the obvious
next move is to "fix" a tier that was working.  `uname -n` is present in
both images and returns `CPC-bazho-U41JRctr` — the `ctr` suffix that IS
the proof:

```bash
fleet-ssh.sh -t ctr hn='uname -n' os='head -1 /etc/os-release'
``` Verified
equivalent to the old `docker exec` path on 5/5 (same CLI version, same `h`
alias, same absent `ghe`) — so the tier is a shorthand for that path, not a
second source of truth.

:trap: **`2224` IS DEAD — do not re-derive it from an old config.** It was
correct once (the distro sat on 2222, so the container took the next free
slot), then the distro moved to 2200 and VACATED 2222. `bin/fleet.py`
carries the fix and the history; a `~/.ssh/config` on disk may predate it.
**Regenerate rather than read**: `python3 bin/fleet.py sshconfig`.

| `-j N` | `8` | parallel width |
| `-b BOXES` | `c01,c02,c03,c04` | comma list |

### `-b up` — scope from MEASURED edges, not from the config

`~/.ssh/config` carries the *scheme* (every box the numbering predicts);
`bin/fleet-connection.json` carries what a **real TCP dial reached**.

```bash
fleet-ssh.sh -b up host='hostname'     # only boxes this host can actually reach
```

MEASURED 2026-09-24 from helix, same probe:

| scope | wall | rows |
|---|---|---|
| `-b up` | **929ms** | 4 useful |
| `-b all` | **60339ms** | 4 useful + 24 `(unreachable)` |

**65x**, and the slow run's extra minute buys nothing but red cells — each
dark edge burns the full `ConnectTimeout` before it can be reported.

Build/refresh the graph (this is the only thing that writes it):

```bash
python3 bin/fleet-connect.py                    # this host's view
FLEET_OBSERVERS=cj00 python3 bin/fleet-connect.py   # add a peer's view
bin/fleet-route.sh table                        # every observer x every box
```

:trap: **AN EDGE IS AN OBSERVATION WITH A TIMESTAMP, NOT A PROPERTY OF THE
BOX.** A box rebooted since the sweep makes a stale `open` a confident wrong
answer, so `fleet-route.sh` warns on stderr past an hour. `-b up` falls back
to the *region* scope — never to `all` — when no graph exists, because
silently widening scope is how a 1s sweep becomes a 60s one.

:trap: **DO NOT DERIVE REACHABILITY FROM THE CIDR.** `fleet-ips.json` has
`block` and `gateway` per region, which makes a CIDR rule tempting. Measured,
it is wrong in both directions: helix routes 10.30 and 10.12 **via the same
next hop** and only 10.12 answers, and *inside* one /17 only 4 of 12 peers
answer. Full write-up:
[`reachability-is-not-derivable-from-cidr.md`](../../REPL/fix.archive/reachability-is-not-derivable-from-cidr.md).

`fleet-route.sh table` renders the layer, not just the state:

```
BOX    CPC-bazho-OUQ6D  c08           VERDICT
c08    open             open          up
c09    dark:noroute     dark:noroute  dark:noroute
c10    dark:timeout     dark:timeout  dark:timeout
```

`c09` and `c10` are in ONE /17 and differ on exactly this — a table
showing both as plain `dark` hides the only distinguishing fact it holds.
`SPLIT` still wins when two observers disagree (mutation-tested: one
observer flipped to `open` renders `dark:noroute | open | SPLIT`).

:trap: **`dark` DOES NOT MEAN "DOWN".** A closed port on a **reachable** box
times out at ~6s exactly like an unroutable host — nothing sends RST, so
timing cannot separate them (`cj00:9999` drops in 6005ms while `cj00:2200`
answers in 54ms). `dark` means *no answer observed from this observer*.
Naming a cause needs a second observer, which is why the file is keyed by
observer and `table` prints `SPLIT` when two disagree.

:trap: **BUT READ THE ERROR VERB FIRST — IT SEPARATES CASES TIMING CANNOT.**
The sentence above is true of the two cases it names and was over-read as
"nothing distinguishes a dark cell", which cost two wrong write-ups. A real
`ssh` reports *which layer* failed, and this estate produces three:

| message | layer | what it means |
|---|---|---|
| `Connection refused` | 4 | something answered and DECLINED (RST) |
| `Connection timed out` | 3 | packet LEFT, nothing came back — policy drop |
| `No route to host` | **2** | it NEVER LEFT — ARP/route never resolved |

MEASURED 2026-09-25: `ssh m09wsl` returned `No route to host` **instantly**
while every other unreachable peer took the full timeout. c00 is
`10.30.1.102/17`, so `10.30.5.155` is inside its own broadcast domain — the
kernel ARPs rather than routes — and `ip neigh` told the whole story:

```
10.30.5.72    lladdr 12:34:56:78:9a:bc  STALE    <- works
10.30.5.75    lladdr 12:34:56:78:9a:bc  STALE    <- works
10.30.5.155                             FAILED   <- "No route to host"
```

**Every reachable peer shares ONE MAC — the gateway's.** No peer is on the
wire with us; the gateway proxy-ARPs for them, and for the others it
DECLINES. `ip route get` is identical either way, so routing was never the
variable. The target was verified alive from another observer at that exact
address, so `FAILED` is a statement about THIS box's permission.

`ip neigh show` is free, local, needs no second observer, and would have
separated these on day one.
[`the-partition-is-proxy-arp-not-routing.md`](../../REPL/fix.archive/the-partition-is-proxy-arp-not-routing.md)

:trap: **WHEN A SWEEP NEEDS TWO DRIVERS, LABEL THE TABLES BY *PROJECT*,
NOT BY DRIVER.**  MEASURED 2026-09-25 on `m00-m09 2222 listen`: m00-m08
answered from c00 and m09 needed helix, so the two tables were headed
"driver c00" / "driver helix".  That names the WORKAROUND and hides the
CAUSE -- m09 is **OfficeAIPlatform** while m00-m08 are **ODSP**, and the
driver differs *because* the project does.  A reader given the driver
label learns which machine I happened to type on; given the project
label they learn why a box is in a different table AND which driver any
future box will need.  `fleet.py live` carries `project` per box, so the
correct heading costs one lookup.

:*** AND THE PROJECT IS NOT A NUMERIC RANGE -- C17 IS ODSP. ***  The
tempting shortcut is "c00-c08 are ODSP, so c09+ are not".  Measured:

```
C00-C08  ODSP               C14-C16  Sydney
C09-C13  OfficeAIPlatform   C17      ODSP     <- OUT OF SEQUENCE
```

C17 sits numerically past two other projects and is back in the first
one.  Any rule of the form "boxes above N belong to X" is wrong for
exactly one box -- and that box reaches the ODSP mesh, so a sweep that
inferred its project from its number would put a REACHABLE box in the
unreachable table.  **Read `project` from the control plane; never
derive it from the box number.**
Rendered correctly:

```
## ODSP                       ## OfficeAIPlatform
BOX  P2222                    BOX  P2222
m00  LISTEN                   m09  LISTEN
...                           ...
m08  LISTEN
m17  LISTEN   <- same table as m00, not with m09
```

Tiers are why the box column says `c01` and not `c01wsl` — the same probe
reads differently per tier, and the tier is a property of the *run*, not
of the box.

## Examples

```bash
# service checkpoint, as the human who owns the services
fleet-ssh.sh -t u \
  lserver='tmux capture-pane -t lserver -p | grep -vc "^$"' \
  p11434='curl -s --max-time 3 http://127.0.0.1:11434/health >/dev/null && echo ok || echo DOWN' \
  p47390='ss -lnt | grep -qc 47390 && echo LISTEN || echo off'
```
```
BOX  LSERVER  P11434  P47390
c01  20       ok      LISTEN
c02  20       ok      LISTEN
c03  20       ok      LISTEN
c04  20       ok      LISTEN
```

```bash
# is a package installed?  dpkg -s, never `command -v` --
# ripgrep ships `rg`, ca-certificates ships no binary at all
fleet-ssh.sh rg='dpkg -s ripgrep >/dev/null 2>&1 && echo yes || echo NO'
```

## Three cell states, deliberately distinct

| cell            | means                                          |
|-----------------|------------------------------------------------|
| a value         | the command answered                           |
| `-`             | the box answered, the command produced nothing |
| `(unreachable)` | the box never answered at all                  |

Collapsing these is how a fleet sweep lies. "ssh failed" and "the command
printed nothing" need different fixes, so they must not share a cell
value. `(unreachable)` prints **once**, in column 1 — it is a fact about
the box, not about each field, and repeating it per column reads like N
separate failures.

## A LOST HOST MUST NOT COST YOU THE SESSION

A box that dies mid-probe is the normal case, not the exception, and the
sweep is built to survive it: `fleet-ssh.sh` bounds **every** ssh with
three guards, because each one covers a failure the others cannot.

| guard                              | covers                                   | default |
|------------------------------------|------------------------------------------|---------|
| `ConnectTimeout`                   | box is dark — no SYN/ACK                 | 15s     |
| `ServerAliveInterval/CountMax`     | path dies MID-session (half-open NAT/VPN)| ~30s    |
| outer `timeout -k 5` (**the cap**) | box answered, the COMMAND hangs          | 60s     |

Tune with `FLEET_SSH_CONNECT_TIMEOUT` / `FLEET_SSH_CMD_TIMEOUT`.

**A stalled box costs ~30s before the cap is even consulted**, because
`ServerAliveInterval=10 × CountMax=3` fires first. Set
`FLEET_SSH_CMD_TIMEOUT` **below 30** if you want the cap itself to be the
guard that fires. (Measured: cap=12 → 12s; cap=45 → 30.2s, ServerAlive
winning. An earlier note said 15s here and was wrong.)

### Three cell states, three different facts

| cell | meaning |
|---|---|
| a value | the probe ran and printed it |
| `-` | the box answered, the command printed **nothing** |
| `(cut)` | the box answered, **this column never ran** — the cap killed the probe first |
| `(unreachable)` | the box never answered at all (dark, or cut before its first field) |

:hard-rule: **`-` AND `(cut)` ARE OPPOSITE FACTS AND MUST NEVER SHARE A
CELL.** Fields stream one line at a time, so a box cut *mid-probe* has
already sent its early columns. Before `(cut)` existed, the remainder
rendered blank — identical to an honest empty answer — and a truncated
sweep was indistinguishable from a complete one:

```
BOX  A  B  C
c90  A  B            <- C NEVER RAN, and the table could not say so
```

If you see `(cut)`, the columns to its left are still trustworthy; raise
`FLEET_SSH_CMD_TIMEOUT` or split the sweep into fewer fields. **Watch for
it on serial probes** — `recipes.sh`'s `meshcfg` loops 5 peers × `timeout 15`
per field, a 75s worst case that truncates under the 60s default.

:hard-rule: **`ConnectTimeout` IS NOT A HANG GUARD, AND BELIEVING IT IS
COST A WHOLE SESSION.** It bounds only the *connect* phase. A box that
ACCEPTS the connection and then stops — hung sshd, wedged distro, remote
command blocked on a credential prompt — leaves `ssh` waiting forever.
MEASURED 2026-09-23 against a server that completes the SSH banner and
then goes silent: `ConnectTimeout=15` ran **150s+ (unbounded)**; with the
outer cap the same stall returned in **12s at cap=12, 15s at cap=45**
(ServerAlive winning the longer case). The repo had already recorded this
exact trap for `git fetch` (`recipes.sh:1637`) and bounded that ONE call
— the shared wrapper every recipe funnels through had no such guard.

:*** WHY THIS IS CORRECTNESS, NOT TIDINESS. *** A foreground tool call
that blocks past ~120s makes the CLI emit a `tool.execution_partial_result`
event, and the session host has a **fixed 120s** budget to acknowledge it.
A host busy rendering a long call misses that budget and the session dies
with `session host did not acknowledge the ... event within 120s`. It is
**not recoverable by resuming** — the resumed session reproduces the same
stall. 357 such failures were logged across two sessions in one evening.
Full postmortem: [`REPL/fix.archive/survive_lost_host.md`](../../REPL/fix.archive/survive_lost_host.md).

### Never hold a fleet sweep open in the foreground

A bounded sweep of a live fleet returns in ~1s, so the default needs
nothing. But when a sweep *can* be slow (many boxes, a heavy probe, a
tier you suspect is wedged), **do not raise `initial_wait` to cover it** —
that is the exact shape that trips the ack deadline.

```bash
# WRONG — a long foreground hold is what kills the session.
#   bash(initial_wait: 300)  fleet-ssh.sh ...

# RIGHT — hand it to the background, then poll.
#   bash(mode: "async", shellId: "sweep")  fleet-ssh.sh -j8 host='hostname'
#   read_bash(shellId: "sweep", delay: 15)   # repeat; each read is cheap
```

Rules of thumb, in order of importance:
1. **`initial_wait` ≤ 90s on anything that touches the fleet.** Past that,
   use `mode: "async"` + `read_bash`.
2. **Let the cap do the waiting, not the deadline.** `FLEET_SSH_CMD_TIMEOUT`
   already guarantees termination; a big `initial_wait` only moves the risk
   onto the session host.
3. **Fan out, don't loop.** `-j8` finishes in one box's time; a serial loop
   over five boxes multiplies every timeout into the ack budget.
4. **Drop known-dead boxes from `-b`.** Probing them burns real seconds of
   cap for a cell that will read `(unreachable)` anyway.

## Why this exists rather than the one-liner

The one-liner is easy to get subtly wrong, and **every way of getting it
wrong produces a confident wrong table rather than an error.** All three
of these were hit for real in this repo:

- **Shredded rows.** Two `printf`s per job are two writes; under
  `xargs -P` they interleave across boxes:
  `c03wsl c02wsl c04wsl GitHub Copilot CLI 1.0.83.` — three boxes, one
  row. It is a *race*, so it often survives, which is worse than always
  failing. `parallel --tag` buffers each job and emits it whole;
  stress-tested at 12 jobs with staggered partial writes, 12/12 intact.
- **Quoting death.** An escaped `awk '{print $3}'` did not survive
  `sh -c` → `ssh "..."` → remote shell, and returned `NONE` on 4/4 — while
  the fleet was fine. **4/4 uniformity made it look credible.** This
  script pipes the probe over stdin (`bash -s`) so the remote shell sees
  it verbatim and no layer reinterprets it.
- **Positional collapse.** A probe emitting two bare lines read with
  `head -1`/`tail -1` collapsed on boxes where the first command printed
  nothing — a listener count `0` was parsed as a container *name*, so "no
  container" was reported as "container up, port dark". Fields here are
  `KEY<TAB>VALUE`, so a missing value cannot shift a column.

## Rules it obeys

- **NEVER REFUSE FOR "NO PROBE DETECTED" (HARD RULE).** If the user
  named a tool, a command, or a thing to check — that is the probe. Run
  it. Refusing, or asking them to restate a query they already gave
  plainly, is FORBIDDEN, not merely discouraged.
  **THE SKILL BLOCK NEVER CARRIES THE QUERY.** It renders this file and
  nothing else, so "the invocation looked empty" is never evidence that
  the user asked nothing — it is how every invocation looks. The query
  is in the triggering message or the turn before it; read it there.
  Anything named there is a probe, however unfamiliar the tool.
  This rule exists because the failure happened twice in one session:
  "awk and grep version" was reported as "no PROBE given" because no
  recipe covered awk. A probe is a shell command, and every box has a
  shell — there is nothing to recognise it against.

- **Per-box rows, never a fleet verdict** (R-FLEET). There is no summary
  line by design: 31 boxes is exactly the size where a summed result hides
  the broken one.
- **`ControlPath=none`** on every hop. A cached mux session predates what
  you are testing — measured: after `usermod -aG docker`, a probe through
  a live mux showed 0 images while a fresh session showed 7.
- **Probe through the alias**, never a literal `127.0.0.1`: ControlMaster
  keys on `%n`, so a literal collapses every box onto one mux socket and
  one box answers for all of them.
- **`BatchMode=yes`** — one box that would prompt hangs the whole sweep.

## When NOT to use it

One box → plain `ssh`. Something that must *change* state on every box →
write a script and fan *that* out (R-REPEATABLE); this wrapper takes only
the first line of output and is built for reading, not writing.

## The parse bench — every row is a failure that really happened

`bench/gold-parse.tsv` is mined from the session where this skill was
corrected eight times. Each row is a REAL user utterance, labeled with the
three slots; repeats in that session are the frustration signal (the user
re-sent `rg version` twice, the apt count three times).

```bash
.github/skills/fleet_ssh/bench/parse-bench.sh          # per-row table
.github/skills/fleet_ssh/bench/parse-bench.sh --quiet  # totals only
```

It grades only what is decidable WITHOUT a model — SCOPE (which boxes),
PROBE (is one derivable at all), and COLS *arity* (how many columns). It
never asserts the exact bash a model would write, because that is a
modelling judgement and pinning it would make the bench brittle.

**The transport was never the bug.** The ssh fan-out worked on every one
of those seven failures; all seven were parse failures. That is why the
bench grades the parse and not the wrapper.

Mutation-tested, so it is known to discriminate rather than merely pass:
scope-always-`all` → 7/9, always-refuse → 1/9, arity-always-1 → 5/9.

Two more arms sit beside it, both scoped to this skill (nothing is added to
`prg`; `model-bench.sh` only *calls* `prg-llm.sh` as a binary):

```bash
.github/skills/fleet_ssh/bench/sep-bench.sh     # -b accepts space AND comma
.github/skills/fleet_ssh/bench/model-bench.sh   # a real model, forced schema
```

`sep-bench.sh` pins a live bug the gold set found: `-b "c01 c02"` — how users
say it — parsed as ONE bogus host and returned a single `(unreachable)` row at
exit 0, a silent wrong answer.

`model-bench.sh` runs each utterance through `prg-llm.sh` with a forced tool
schema (prose formatting is NOT honored by the proxy — asked in prose the model
ignored the format and hallucinated fake `rg` output). It scores 9/9, but read
its header before quoting that: a generic-prompt control ALSO scores 9/9, so
the arm measures the schema, not this file's prose.

### The ANSWER also has a schema

`parse.schema.json` governs the INPUT (utterance → scope/cols).
`table.schema.json` governs the OUTPUT — the table is what the user actually
reads, and a correct parse that renders a lying table is still a wrong answer.

```bash
.github/skills/fleet_ssh/bench/table-bench.sh   # runs the REAL fleet
```

It uses a deliberately unreachable box as a fixture, so the three cell states
are produced by the tool rather than asserted in prose, and pins: `header[0]`
is `BOX`; one row per box in scope (a failed box still gets a row); cell count
matches header count; the three states stay distinct; `(unreachable)` prints
once per row, not per column. 9/9, mutation-tested (drop-a-box → 8/9,
break-empty-state → 8/9).

**Measured limit — schema conformance is NOT a correct table.** A table that
collapses `(unreachable)` into `-`, and a table that silently drops a box row,
BOTH validate against `table.schema.json`: JSON Schema sees structure, and
those two lies are semantic. They are caught by `table-bench.sh`'s explicit
checks, which is why the bench exists alongside the schema rather than the
schema alone.
