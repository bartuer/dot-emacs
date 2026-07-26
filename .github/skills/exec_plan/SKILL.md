---
name: exec_plan
description: Execute an Org-mode plan document (.org.txt) end-to-end — read the plan, focus on the next undone work item, run its commands, update [ ]→[X] as you go, and loop until all work-item groups are DONE. Use when the user says "exec plan", "execute plan", "/exec_plan", "run plan 19", "exec phase 17 of …", or supplies one or more `.github/REPL/*.org.txt` paths. If multiple plan docs are supplied, dispatch them in parallel as a fleet of subagents. Within a single plan doc, parallelize sibling work items tagged with `:parallel_group:` (or explicitly requested by the user) after a pre-flight collision check — the orchestrator owns plan-doc edits; subagents never flip [ ]→[X].
---

# Plan Execution Skill

This skill is the *runtime* counterpart of `org_plan` (which authors plans).
Given one or more Org-mode plan documents, walk the work-item lists and
execute them following the discipline encoded in the doc itself.

The canonical prompt this skill encapsulates is
[master.prompt.md](../../prompts/master.prompt.md "master prompt").

---

## Pre-flight — respect the project's dev process setup

Before executing ANY work item, obey the rules defined in this
project's per-repo instructions:

- `.github/copilot-instructions.md`  (mirrored in `CLAUDE.md`)

Both auto-load into every GHCP CLI session. Open them, read the
current rules, and follow them. This skill intentionally does
NOT restate any of those rules — dev-process specifics live only
in the per-repo instruction files so a checkout in another repo
inherits that repo's rules automatically.

---

## What the user typically asks

Real-world invocation patterns observed in the project's session history:

- `exec plan '/workspace/OfficeAgent/.github/REPL/19.dataconnection.benchmark.org.txt'`
- `/master.prompt.md exec plan 19 phase 16 '…/19.dataconnection.benchmark.org.txt'`
- `go work on phase 17.1`
- `try more, and ws rerun all cases`
- `'/workspace/OfficeAgent/.github/prompts/master.prompt.md' exec plan 19 phase 16 …`
- `/exec_plan '…/08.dataconnection.velixo.eval.org.txt' '…/19.dataconnection.benchmark.org.txt'`  ← multi-doc

When the user names a specific phase (e.g. "phase 17.1"), scope execution
to that work-item group only; otherwise execute from the first non-DONE
work-item group forward.

---

## Plan-doc format recap (so you read it correctly)

```
* TODO Goal [N/M]              ← top-level checklist; not work
* Phase X — title  [done/total]  ← work-item group (TODO/DONE/ABORT/HALT)
  - [ ] X.1 work item            ← undone
  - [X] X.2 work item            ← done
        :test_tool: …            ← test/verify command
        :interrupt: …            ← pause-for-user marker
        (link "path" digit)      ← Org-mode anchor link
```

Conventions you must follow:

1. **Handle work-item groups one by one.** Don't jump phases unless the
   user explicitly told you to. Finish the current group's `[ ]` items
   before moving to the next group.
2. **Update state as you go.** When a work item completes, flip
   `[ ] → [X]` in the doc, then update the group counter
   (`[2/6] → [3/6]`) and the Goal counter `[N/M]` if applicable.
3. **`:test_tool:` items** are the verification step — run them in a
   *separate shell session* from the code being tested (the plan format
   says so explicitly). Use `mode: "async"` + a distinct `shellId` for
   long-running test loops.
4. **`:interrupt:` items** require user confirmation — pause and call
   `ask_user` before proceeding past one.
5. **Link format `(link "path" digit)`** — `digit` is the approximate
   character offset; use it as a hint for where to scroll/view, not a
   strict requirement.

---

## Execution loop (single plan doc)

For each plan doc:

1. **Read the plan.** Skim the `* Goal` checklist first (so you know
   the destination), then jump to the first non-DONE work-item group.
2. **Pick the first `- [ ]` item** within that group. Read its
   sub-bullets — they typically contain the command line, code
   snippet, and acceptance criteria.
3. **Execute** — run commands, edit files, view results. Use the same
   tools the plan references (the plan often names exact CLI commands).
4. **Verify** — if there's a `:test_tool:` sibling item, run it in a
   separate shell. Read its output; if the acceptance criteria don't
   pass, loop (R)→(E)→(P)→(L) until they do.
5. **Update state** — flip `[ ] → [X]`, bump the group counter and
   Goal counter. Use the `edit` tool, never re-write the whole file.
6. **Move to the next item** in the same group, repeating from step 2.
7. **When the group reaches `[N/N]`**, change its label to `DONE`
   (e.g. `* Phase 17 — … [4/4] DONE`). Then move to the next group.
8. **Summarize** at the end — what changed, which artifacts produced,
   what's still pending. Cite file paths and verdict counters.

### Mid-execution housekeeping

- If you discover work that doesn't fit any existing item, ADD a new
  item to the current group (mark it `[ ]`) rather than silently doing
  extra work.
- If you discover a whole new work-item group is needed, add it WITHOUT
  a `TODO/DONE/ABORT/HALT` label (per `org_plan` skill convention) —
  the user will review and label it.
- Significant findings or summaries that must survive the session
  (become part of the durable knowledge base) go in
  `.github/REPL/fix.archive/` with a short, meaningful filename and
  are committed. Everything else — turn-level narrative, why-I-did-X
  notes, intermediate probes, model of the world at each step — goes
  to CLI session memory (see next subsection). Do NOT hand-roll a
  checkpoint file under `.github/REPL/fix.archive/` for narrative;
  the CLI already writes one per turn.
- Avoid editing the plan doc and running commands in the same response
  if the command depends on the edit — split into sequential turns.

### Session memory — three tiers, know which one to read/write

The CLI already logs every turn, tool call, and output — do not
duplicate that work. Instead, read from it and pick the right tier
for each write:

| Tier                | Path / Tool                                                              | Timescale       | Owner        | When to use                                                                 |
|---------------------|--------------------------------------------------------------------------|-----------------|--------------|------------------------------------------------------------------------------|
| Rules               | `.github/copilot-instructions.md`                                        | forever         | human commit | Invariants — never violated (rg vs parallel, CRLF, ssh git identity, …)     |
| Plan state          | `.github/REPL/NN.*.org.txt`                                              | days–weeks      | skill edit   | `[ ] / [X]`, counters, work items                                            |
| Durable findings    | `.github/REPL/fix.archive/*.md`                                          | forever         | skill commit | Taxonomies, postmortems, recipes that outlive the session                    |
| Session narrative   | `~/.copilot/session-state/$COPILOT_AGENT_SESSION_ID/checkpoints/`        | this run only   | CLI auto     | "Why did I do X on turn N" — CLI writes NNN-slug.md files automatically      |
| Raw events          | `~/.copilot/session-state/$COPILOT_AGENT_SESSION_ID/events.jsonl` + `session.db` | this run only | CLI auto     | Every tool call, output, model choice — replay/debug of current run          |
| Cross-session lookup| `session_store_sql` tool (DuckDB over `~/.copilot/session-store.db`)     | forever         | CLI + reader | "Have I hit this F-code / built this script / seen this error before?"       |

Read-before-work rule: for any non-trivial task, spend one
`session_store_sql` query up front to check whether you (or another
session on this repo) already solved it. Example — before writing a
git-reauthor script, query:

```sql
SELECT session_id, turn_index, user_message
FROM turns
WHERE user_message ILIKE '%reauthor%'
  AND timestamp > now() - INTERVAL '90 days'
LIMIT 20;
```

Path resolution — always dynamic, never hardcoded:

```bash
CHECKPOINT_DIR="${HOME}/.copilot/session-state/${COPILOT_AGENT_SESSION_ID}/checkpoints"
# Fallback when running outside a CLI session (unit tests, dry-runs):
[ -z "${COPILOT_AGENT_SESSION_ID}" ] && \
    CHECKPOINT_DIR="/tmp/exec_plan_checkpoints_$$"
mkdir -p "$CHECKPOINT_DIR"
```

The historical dumping ground `.github/REPL/fix.archive/dc.parallel.checkpoints/`
was retired 2026-07-20 — do NOT re-create it, do NOT write there, and do
NOT reference it from new plan docs. Point at
`~/.copilot/session-state/$COPILOT_AGENT_SESSION_ID/checkpoints/` instead
when a plan needs to cite a turn-level artifact.

---

## Multi-plan execution — FLEET MODE

When the user provides **two or more** `.org.txt` paths, use
**`/fleet`** — a native GHCP CLI slash command — to run each plan as
an independent parallel subagent.

### What `/fleet` is

`/fleet` is a first-class GHCP CLI feature listed under
**Agents / Subagents** in `/help`:

```
/fleet    Enable fleet mode for parallel subagent execution
```

It is NOT approximated with `task()` calls or background processes.
It is a CLI primitive that the runtime understands natively. When you
see 2+ plan doc paths in a single user message, the correct response
is to tell the user to use `/fleet`, or (when you are the orchestrating
agent) to emit the fleet invocation yourself.

### When to fleet

| Situation | Action |
|---|---|
| User pastes 2+ `.org.txt` paths | Invoke `/fleet` |
| User says "exec plans 17 and 19 in parallel" | Invoke `/fleet` |
| User says "exec plan 19 phase 16 and phase 17" | Serial — same doc |
| User says "exec plan 19" (single doc) | Direct execution, no fleet |
| Plans share a sweep dir / dataset that mutates | Serial — tell user why |

### How to invoke `/fleet`

As the orchestrating agent, emit a fleet block — each line is one
independent subagent task, all launched in parallel by the runtime:

```
/fleet
  exec_plan '/workspace/OfficeAgent/.github/REPL/17.foo.org.txt'
  exec_plan '/workspace/OfficeAgent/.github/REPL/19.bar.org.txt'
```

Or the user can type it directly in the GHCP CLI terminal:

```
/fleet
  exec plan 17
  exec plan 19
```

GHCP will create two subagent sessions, each inheriting the skill
context. No manual `task()` wiring needed — the CLI handles lifecycle,
cancellation, and result aggregation.

### Before dispatching: pre-flight collision check

Grep both plan docs for shared resources that would cause write races:

```bash
grep -hE ":test_tool:|docker.*run|sweep|dataset\.jsonl" plan-A.org.txt plan-B.org.txt
```

| Collision type | Example | Action |
|---|---|---|
| Same `:test_tool:` port | `:6010` in both | Serial |
| Same docker container | `excel-agent` in both | Serial |
| Same sweep directory | `dceval/_sweeps/` in both | Serial |
| Same dataset write | `dataset.jsonl` in both | Serial |
| No overlap | — | Fleet ✅ |

### Fleet safety rules

1. **One plan per subagent.** Each subagent receives one absolute path
   and the instruction "do NOT touch any other `.org.txt` files."
2. **No recursive fleet.** Every subagent prompt must include:
   *"Do NOT use `/fleet` or dispatch nested subagents. Return any
   cross-plan TODOs to the orchestrator."*
3. **Aggregate on completion.** Wait for all subagents, then produce
   one combined table — not per-subagent noise.
4. **Partial failure is OK.** If one subagent errors, report others'
   progress and suggest the fix for the failed one.

### Subagent prompt template

Paste this into each fleet slot, substituting `<PATH>` and `<PHASE>`:

```text
Invoke the exec_plan skill on:
    <ABSOLUTE_PATH_TO_PLAN_DOC>

Constraints:
- Focus on the first non-DONE work-item group.
  (If phase requested: "<PHASE>", scope to that group only.)
- Edit the plan doc in-place: flip [ ] → [X], bump counters.
- Run :test_tool: in a SEPARATE shell session (distinct shellId).
- Do NOT touch any other .org.txt files.
- Do NOT use /fleet or dispatch nested subagents.

Return:
1. Items flipped [X] (number + one-liner each).
2. New items added (if any).
3. Blockers / unmet acceptance criteria.
4. Artifacts produced (paths under .github/REPL/ or fix.archive/).
5. Any other plan docs your plan referenced — list them, don't exec.
```

### Aggregated result format

After all fleet subagents complete, report once:

```
| plan doc       | items done  | new items | blockers      | artifacts            |
|----------------|-------------|-----------|---------------|----------------------|
| 17.foo.org.txt | 17.1, 17.2  | —         | —             | fix.archive/foo.md   |
| 19.bar.org.txt | 18.2, 18.3  | 18.6      | 18.4 pending  | dceval/leaderboard.md|
```

Then list any follow-up plan docs the subagents surfaced.

---

## Intra-doc fleet — parallel work items within a single plan

The inter-doc fleet above parallelizes across plans. **Intra-doc fleet**
parallelizes `[ ]` work items *inside the same plan doc* when they are
provably independent. This is opt-in and conservative — the default
remains the serial execution loop (the plan author's ordering is the
source of truth).

### When to consider intra-doc fleet

Look for parallelism opportunities ONLY after picking the current
work-item group (per the serial loop, step 1). Within that group:

| Situation | Action |
|---|---|
| Items carry `:parallel_group: <tag>` markers (see below) | Fleet the tagged wave |
| User explicitly says "do 17.1, 17.2, 17.3 in parallel" | Fleet those items |
| Sweep-cell phase: N independent cases sharing a runner | Fleet (cap fan-out) |
| Items have implicit ordering (item N reads item N-1's output) | Serial |
| Items share a `:test_tool:` port / container / sweep dir | Serial |
| Items mutate the same file (other than the plan doc itself) | Serial |
| You are not sure | Serial — ask the user before fleeting |

### Author convention: `:parallel_group:` marker

Authors signal safe parallelism by tagging sibling items with the same
group name. The marker sits on its own sub-bullet line, like
`:test_tool:`:

```
*** TODO Phase 21 — multi-tool smoke [0/4]
    - [ ] 21.1 cf-lint smoke
          :parallel_group: tool_smoke
          :test_tool: pnpm -F cf-lint test:smoke
    - [ ] 21.2 oj-lint smoke
          :parallel_group: tool_smoke
          :test_tool: pnpm -F oj-lint test:smoke
    - [ ] 21.3 docdb smoke
          :parallel_group: tool_smoke
          :test_tool: pnpm -F docdb test:smoke
    - [ ] 21.4 publish rollup report     ← no marker = runs AFTER the wave
```

Semantics:

1. **Same-name siblings form one fleet wave** — dispatched together,
   one subagent per item.
2. **Untagged items in the group are barriers** — orchestrator finishes
   the current wave (all `[X]`) before running the next untagged item
   or the next wave.
3. **Multiple waves are allowed** — `tool_smoke` then `report_rollup`.
   Waves execute serially in declaration order; items within a wave
   execute in parallel.
4. **A lone-tagged item is just serial** — no benefit, no harm.

### Pre-flight: intra-doc collision check

Before dispatching a wave, scan the candidate items' sub-bullets for
shared resources. Reuse the inter-doc collision rules verbatim:

```bash
# extract the wave's sub-bullet lines and grep for shared state
awk '/^    - \[ \] 21\./,/^    - \[/' plan.org.txt \
  | grep -hE ':test_tool:|docker.*run|sweep|dataset\.jsonl|:[0-9]{4,5}\b'
```

| Collision type | Example | Action |
|---|---|---|
| Same `:test_tool:` port | `:6010` in two items | Serial (drop one from wave) |
| Same docker container name | `excel-agent` in two | Serial |
| Same sweep / output dir | `dceval/_sweeps/run-A/` | Serial |
| Same dataset write | `dataset.jsonl` append | Serial |
| Only the plan doc itself | (every item edits it) | Fleet ✅ — orchestrator owns the edit |
| Disjoint paths / ports | — | Fleet ✅ |

If even one pair collides, either (a) drop the colliding item from the
wave and run it serially after, or (b) abandon the wave and fall back
to fully serial. When in doubt, ask the user.

### Plan-doc write serialization (critical)

Every subagent in an intra-doc fleet would naturally want to flip its
own `[ ] → [X]` and bump the `[N/M]` counter. That is a write race on
the plan doc. Rule:

> **Subagents MUST NOT edit the plan doc.** They report which items
> they completed. The orchestrator applies all `[ ]→[X]` flips and
> counter bumps in a single edit sequence after the wave returns.

This also makes partial-failure recovery trivial: failed items simply
aren't flipped.

### How to invoke (intra-doc)

```
/fleet
  exec_plan_item '/workspace/.../21.foo.org.txt' 21.1
  exec_plan_item '/workspace/.../21.foo.org.txt' 21.2
  exec_plan_item '/workspace/.../21.foo.org.txt' 21.3
```

Each subagent receives **one item ID** plus the plan path, and runs
*only* that item's sub-bullets (commands, code edits, `:test_tool:`).
No phase traversal, no neighbor reads, no plan-doc edits.

### Intra-doc subagent prompt template

```text
Invoke the exec_plan skill on a SINGLE work item:
    plan:  <ABSOLUTE_PATH_TO_PLAN_DOC>
    item:  <ITEM_ID, e.g. 21.2>

Constraints:
- Read only the sub-bullets of item <ITEM_ID> in the plan doc.
- Run its commands, apply its code edits, run its :test_tool: in a
  SEPARATE shell session (distinct shellId).
- Do NOT edit the plan doc. Do NOT flip [ ]→[X]. Do NOT bump counters.
- Do NOT touch sibling items or other phases.
- Do NOT use /fleet or dispatch nested subagents.

Return:
1. Verdict: PASS / FAIL / BLOCKED (one line).
2. Commands run + acceptance criteria status.
3. Files modified (paths) — excluding the plan doc.
4. Artifacts produced (paths under .github/REPL/ or fix.archive/).
5. If FAIL/BLOCKED: the exact error and a proposed next step.
```

### Orchestrator post-wave routine

After all subagents in a wave return:

1. **Collect verdicts.** Make a table: item → PASS / FAIL / BLOCKED.
2. **Edit the plan doc once.** For each PASS, flip `[ ] → [X]`. Bump
   the group counter by the count of new `[X]`. Bump the Goal counter
   if any group flipped to DONE.
3. **For FAIL/BLOCKED items**, leave `[ ]` and append a one-line note
   under the item (per the existing "add new items" convention) or
   surface to the user via the summary.
4. **Run the next barrier item or wave** (serial step in the group).
5. **When `[N/N]`**, mark the group `DONE` as in the serial loop.

### Intra-doc fleet safety rules (recap)

1. **One item per subagent.** Item ID is the contract.
2. **No plan-doc writes from subagents.** Orchestrator owns the file.
3. **No recursive fleet.** Subagent prompt forbids `/fleet`.
4. **Cap fan-out.** For sweep-style phases with 20+ cases, batch into
   waves of ≤ 8 to avoid runner thrash. State the batch size up front.
5. **Untagged = barrier.** Respect the author's ordering for any item
   without `:parallel_group:`.
6. **Pre-flight collisions every wave** — don't trust historical safety;
   items get edited.

### Mini-example

User: `exec plan 21` and Phase 21 looks like the sample above.

**Orchestrator:**

1. Read plan 21, locate `* Phase 21`, find wave
   `tool_smoke = {21.1, 21.2, 21.3}` and barrier `21.4`.
2. Collision check on 21.1/21.2/21.3 sub-bullets — disjoint packages,
   no shared ports → fleet OK.
3. Dispatch:
   ```
   /fleet
     exec_plan_item '…/21.foo.org.txt' 21.1
     exec_plan_item '…/21.foo.org.txt' 21.2
     exec_plan_item '…/21.foo.org.txt' 21.3
   ```
4. Wait. Collect: 21.1=PASS, 21.2=PASS, 21.3=FAIL(missing fixture).
5. Single edit: flip 21.1 and 21.2 to `[X]`, bump `[0/4] → [2/4]`.
   Leave 21.3 `[ ]` and add a `← blocked: missing fixture` note.
6. Skip 21.4 (barrier depends on the wave) and report to user.

---

## Quick reference — common pitfalls

- **Editing `[ ] → [X]` and running its command in the same turn**
  → the command may fail and leave the doc lying about state. Run
  first, verify, then edit.
- **Forgetting to bump the group counter** → the `[2/6]` stays stale,
  next agent re-runs the work. Always update both `[ ]→[X]` AND `[N/M]`.
- **Running `:test_tool:` in the same shell as the code under test**
  → the plan doc warns "you will struggle a lot". Use distinct
  `shellId` values.
- **Skipping `:interrupt:` markers** → these are explicit human-in-
  the-loop gates. Always `ask_user` first.
- **Fleeting docs that share state** → race conditions corrupt
  sweeps. Pre-check, fall back to serial when in doubt.
- **Intra-doc fleet writing the plan doc from subagents** → guaranteed
  edit race. Subagents return verdicts; orchestrator flips `[ ]→[X]`.
- **Fleeting across a `:parallel_group:` boundary** → untagged items
  are barriers. Finish the wave first; barrier items run serially.
- **Forgetting to cap fan-out** → 20-case sweep launches 20 subagents
  and DoS-es the local runners. Batch into waves of ≤ 8.

---

## Example: single-doc, named-phase invocation

User: `/exec_plan 19.dataconnection.benchmark.org.txt phase 18`

1. `view` plan-19, locate `* Phase 18` group, read its `[ ]` items.
2. Pick item `18.2 rename + archive`.
3. Run the rename script described in the item's sub-bullets.
4. Verify acceptance criteria (`ls .github/REPL/dceval/hero_*`
   returns exactly 21 entries…).
5. `edit` to flip `[ ] 18.2 → [X] 18.2` and bump `[2/6] → [3/6]`.
6. Move to `18.3`. Repeat until `[6/6]`, then mark group `DONE`.
7. Summarize and stop (user said "phase 18", not "all of plan 19").

## Example: fleet invocation

User pastes two plan paths in one message. Orchestrator does:

**Step 1 — pre-flight check**
```bash
grep -hE ":test_tool:|docker.*run|sweep|dataset" \
  17.foo.org.txt 19.bar.org.txt
# → no shared resources → safe
```

**Step 2 — fleet dispatch (GHCP CLI native)**
```
/fleet
  exec_plan '/workspace/OfficeAgent/.github/REPL/17.foo.org.txt'
  exec_plan '/workspace/OfficeAgent/.github/REPL/19.bar.org.txt'
```
GHCP creates two subagent sessions in parallel. Each runs the
single-doc execution loop on its own plan, updates `[ ]→[X]`
in-place, and returns a summary.

**Step 3 — aggregate**
```
| plan doc       | items done  | blockers      | artifacts            |
|----------------|-------------|---------------|----------------------|
| 17.foo.org.txt | 17.1, 17.2  | —             | fix.archive/foo.md   |
| 19.bar.org.txt | 18.2, 18.3  | 18.4 pending  | dceval/leaderboard.md|
```
