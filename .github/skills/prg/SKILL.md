---
name: prg
description: Concurrent search over code, logs, traces and git history (GNU parallel + find + ripgrep), plus a no-LLM symbol-chain grapher (rg --json + jq) walking seed → def → refs → enclosing symbol. Use for searches that span a huge tree, shard across many dirs, run many patterns at once, or trace how a symbol connects to the rest of the code. Say "prg", "/prg", "parallel search", "concurrent search <pattern> in <dir>", "build a search index of …", "fan out rg across …", "graph the callers of <symbol>", "trace <symbol>". Not for a one-shot lookup — plain `rg` already parallelizes over files.
argument-hint: "SOURCE (repo|log|trace|git) + TERM (symbol/regex/span) + TASK (find|count|callers|when|summarize) — pass the whole utterance; all three slots are parsed from it"
location: project
---

# prg — parallel ripgrep

`find | parallel | rg` for high-throughput concurrent search. `rg` on its
own already threads over files; `prg` adds a second axis of parallelism —
**sharding the work and fanning heavier per-shard processing across cores** —
for cases a single `rg` invocation handles poorly.

## The basic usage model — utterance in, efficient tool calls out

When a person says **"search"**, **"find"**, **"look for"**, **"where is"**,
**"trace"**, or **"grep"** in their prompt, `prg` is the smart front door.
The model (you) does the understanding; the tools stay model-free and fast.
The loop is:

1. **Take the WHOLE utterance as input.** Not just a quoted token — the
   whole sentence carries the intent ("find how telemetry gets set up",
   "where do we handle the docdb connection", "trace the callers of X").
   **Recover a slash utterance before calling it empty.** The CLI slash
   wrapper can expose only the injected `<skill-context>` to the model while
   recording the actual `/prg ...` text as a separate `user.message` in the
   current session's `events.jsonl`.  If no utterance is visible after the
   skill context, read the latest raw `user.message` from the CURRENT session
   before applying the empty-utterance rule:

   ```bash
   session="${COPILOT_AGENT_SESSION_ID:?}"
   events="$HOME/.copilot/session-state/$session/events.jsonl"
   jq -c 'select(.type=="user.message") | .data.content // empty' "$events" \
     | tail -n 1 | jq -r .
   ```

   Parse a recovered `/prg ...` exactly as if it had arrived inline.  Search
   no other session.  Only run zero tools when the recovered text is empty or
   exactly `/prg`; the injected skill-context itself is NEVER the utterance.
2. **Understand it.** Decide *what* is really being asked: code vs docs vs
   logs? one pattern or a family? a flat match, or a symbol you must
   *follow*? bounded to a subtree, or repo-wide?
3. **Make up the tool calls — smartly.** Construct the keyword(s)/regex,
   pick the efficient mechanism, and only parallel-fan-out when it pays:

   | The utterance implies…                        | Efficient move                         |
   |-----------------------------------------------|----------------------------------------|
   | one token, one tree, "just find it"           | plain `rg` (do NOT reach for prg)      |
   | huge/slow tree, many big children             | Recipe A — shard by top-level dir      |
   | "index / categorize / all the places that …"  | Recipe C — one job per pattern         |
   | "for each hit also extract/count/parse …"     | Recipe B — fan a heavier op per file   |
   | "how does X connect / who calls X / follow X" | `prg-graph.sh` symbol chain            |
   | "in the LLM logs / requests / by model …"     | `prg-log.sh` + a `jq/*.jq` lens  |
   | "in the doc/ppt/pdf corpus / the binary index" | plain `rg` over the sidecars — do NOT |
   |                                               | shard; measured 3-6x slower           |
   | "which xlsx has sheet/cell/formula X"         | `rg -l` prefilter, THEN `jq` the few  |
   |                                               | survivors — 6x (6,676 files -> 9)     |
   | "here is a case/delivery FOLDER — what is in  | `prg-case.sh ls`/`stat` — inventory   |
   | it / what changed between v5 and v6"          | FIRST, then `diff` the two workbooks  |
   | "…and which of these files is the DECOY"      | same `ls`: `peer:N` = near-duplicate  |
   |                                               | family (v2/- Copy/(1)); compare its   |
   |                                               | `sheets`/`bytes`, then READ THE PROSE |
   |                                               | — `ls` flags, it never picks a winner |
   | "…is any of it a picture I can't grep"        | same `ls`: `media:N` embedded images  |
   | "…now actually ANSWER a number off those     | `prg-case.sh plan CASE` names the verb |
   | files"                                        | per file; `read` then resolves         |
   |                                               | index/binary/text FOR you — never hand |
   |                                               | the sidecar path to the next hop       |
   | "what happened last hour / in this session /  | `prg-trace.sh harvest`/`connect` — the |
   | around when X broke / trace this run"         | two-round time-span trajectory dive    |
   | "this exception / stack trace <paste> — find  | Crash-triage — jq the frame's SYMBOL,  |
   | it & what's the fix"                          | then `prg-graph.sh` that symbol in SRC |
   | "debug this ssg leg / what did the model DO   | `prg-leg.sh <run> <id>` — Recipe H,    |
   | & SAY in run X case Y"                        | the session+traffic 2-file join        |

4. **Read the findings, plan the next dive, fan out.** A high-level
   direction becomes several parallel keyword→tool→findings branches; you
   orchestrate above the tools until the picture is complete.

The whole point: the human expresses *what* to find; `prg` is smart about
the efficient *how*. Being clever about tool choice (and about when NOT to
parallelize — see "When plain `rg` is enough") is the skill.

## Parse the utterance first — SOURCE / TERM / TASK

Step 1 (the front door) is symmetric to the last step (the
"## Evidence citation" back door): before any tool runs, decompose the
whole utterance into **three slots**. This is the ONE naming that unifies
the rules already in this doc — it does not add behavior, it makes the
first move explicit so no part of a fused instruction is dropped.

| slot       | what it selects                                      | governed by the rule that already owns it                          |
|------------|------------------------------------------------------|--------------------------------------------------------------------|
| **SOURCE** | WHICH corpus → which verb + corpus env               | the verb table above; `Preconditions` env (`PRG_LOG_CORPUS` = log, `PRG_TRACE_CORPUS` = trace, `--root` = repo, `read_pr`/`read_patch` = git) |
| **TERM**   | the seed fed to the verb (token / symbol / regex / span) | the **fuzz ladder** for a repo seed; the **corpus-anchor** rule when the TASK is a count over logs/JSONL; `prg-when.sh` for a time-span |
| **TASK**   | the downstream OPERATION on the tool's JSON          | the **downstream-op routing table** below (find / count / summarize→doc / callers / when); the write-up ends with **## Evidence citation** |

Machine contract (generated from schema/parse.py — do not hand edit;
regenerate with the CKP-2 pipe, guarded by schema/check-embed.sh):

<!-- prg:parse-schema:begin -->
```json
{"$defs":{"Flow":{"description":"Upstream/downstream direction — the trajectory spine for a workflow.\n\nFor a single utterance both lists may be empty.  For a multi-turn\nworkflow, upstream names what feeds this intent and downstream names what\nthis intent feeds — the same connection prg-trace.sh connect derives\ndeterministically between turns.","properties":{"upstream":{"description":"Intents/refs that feed THIS one (what came before).","items":{"type":"string"},"title":"Upstream","type":"array"},"downstream":{"description":"Intents/refs THIS one feeds (what it enables next).","items":{"type":"string"},"title":"Downstream","type":"array"}},"title":"Flow","type":"object"},"Slots":{"description":"The three-slot decomposition of one utterance (the parse recipe).","properties":{"source":{"description":"WHICH corpus -> which prg verb + corpus env.  Parsed from the source words, not assumed: 'who calls X / follow X' -> repo graph; 'when did X change / last hour' -> trace/log; 'in the L-server logs ... by model' -> log; 'in this case folder / the delivery / these files' -> case folder (prg-case.sh ls/stat, inventory FIRST); a lone symbol -> repo search.  A FOLDER is a legitimate source: the SOURCE picks the folder, TERM is the file/sheet/column seed, and TASK routes downstream unchanged.","title":"Source","type":"string"},"term":{"description":"The seed(s) fed to the verb (token / symbol / regex / span).  Obeys the fuzz-vs-anchor split: FUZZ the separator for a REPO seed; ANCHOR the identifier when COUNTING over a corpus.","items":{"type":"string"},"title":"Term","type":"array"},"task":{"description":"The downstream OPERATION on the tool's JSON, routed by the downstream-op table (find / count / summarize->doc / callers / when).  A long instruction fuses a SEARCH clause (source+term) with an OPERATION clause (task); the task must not be dropped.","items":{"type":"string"},"title":"Task","type":"array"}},"required":["source"],"title":"Slots","type":"object"}},"description":"One parsed user utterance: its text, its slots, and its flow direction.","properties":{"text":{"description":"The raw user utterance being parsed.","title":"Text","type":"string"},"slots":{"$ref":"#/$defs/Slots","description":"SOURCE / TERM / TASK decomposition."},"flow":{"$ref":"#/$defs/Flow","description":"Upstream/downstream direction (empty for a lone utterance)."}},"required":["text","slots"],"title":"Utterance","type":"object"}
```
<!-- prg:parse-schema:end -->

- **SOURCE is parsed, not assumed** — the source words pick the verb:
  "who calls X / follow X" → repo + `graph`; "when did X change / last
  hour" → `trace`/`log`; "in the L-server logs … by model" → `log`;
  a lone symbol → repo `search`. Same TERM, different SOURCE words → a
  different verb (that is the source-disambiguation the tests below check).
- **TERM obeys the ladder-vs-anchor split** already documented: fuzz the
  separator for a REPO seed, ANCHOR the identifier when COUNTING a corpus.
- **TASK must not be dropped** — a long instruction fuses a SEARCH clause
  (SOURCE+TERM) with an OPERATION clause (TASK). Run the search FIRST, then
  perform the TASK on its output (see "A long instruction = a SEARCH clause
  + an OPERATION clause" below), routing via the downstream-op table.

Worked split of one fused utterance:

> "in the L-server logs, count last hour requests by model and write a doc"

| slot   | value                                                              |
|--------|--------------------------------------------------------------------|
| SOURCE | log corpus → `prg-log.sh` + `PRG_LOG_CORPUS` (the "logs" word)      |
| TERM   | ANCHORED `.model` field over span `"1 hour ago".."now"` (a COUNT → anchor, don't fuzz) |
| TASK   | **count** → `jq/count-by-model.jq`, THEN **summarize→doc** → Comprehensive report → `fix.archive/*.md`, ending in a `## Evidence` block |

Then the loop proceeds exactly as before: pick the verb/recipe → run the
tool → operate on its stable JSON → cite the atoms. Parse (this section)
and cite ("## Evidence citation") are the two bookends of the same loop —
and when a whole WORKFLOW (many utterances over many turns) is in play, the
same three slots become the trajectory SPINE (next section).

## Trajectory = the workflow spine

The parse recipe decomposes ONE utterance into SOURCE/TERM/TASK. A real user
workflow is a **connected sequence of parsed intents over turns**. That shape
already has a data model: `prg-trace.sh connect` (Recipe E) emits a
span-scoped trajectory whose `turns[]` ARE the sequence and `edges[]` ARE the
connections, each turn carrying the SAME three slots — PARSE (one utterance)
and TRACE (a workflow) are the identical decomposition at two scales:

    one utterance          →   {SOURCE, TERM, TASK}                (parse recipe)
    a workflow of N turns   →   [ {SOURCE,TERM,TASK}_0            (connect: the spine)
                                  {SOURCE,TERM,TASK}_1 …_N ]
                                connected by tool-derived edges

- **Each turn = one intent node.** `connect` puts `slots:{source,term,task}`
  on every turn, derived DETERMINISTICALLY (no model) by partitioning that
  turn's keywords by their `kind`: SOURCE = the turn's lens/role; TERM =
  the seeds worked on (kind symbol|path|span|commit); TASK = the operation
  that happened (kind event|tool|model).
- **Edges connect the nodes.** A shared ref (same traceId / changed file /
  Round-1 keyword) or adjacent ordinal links turn *i* to turn *j* — so
  turn *i*'s TERM/TASK visibly feeds turn *j*. The workflow is walkable.
- **The spine closes the loop.** A `## Evidence` claim about the workflow
  cites a specific turn's slot atom (a `refs` entry / `path:line` / traceId)
  — so PARSE (per turn) → TRACE (connected) → CITE (per claim) is one
  coherent line: parse the intent, connect the intents, cite the trace.

The trajectory is not a debug afterthought but the **carrier of the workflow
itself** — parse (front door) and cite (back door) are the endpoints of a
spine, not of a single step. Reach for it the moment the question spans more
than one intent ("trace this run", "what was the sequence when X broke").

**A bare token IS the target — never refuse, never ask, just search.**
`/prg office_shim` means "search the repo for `office_shim`" — the seed IS
the keyword. Do NOT reply "no search term was supplied", do NOT call
`ask_user` for "which verb", and do NOT `task_complete` without running a
tool. When only a term is given, default to the **search** verb over the
repo (case-insensitive, fuzzy the separator: `office_shim` →
`rg -i 'office[._-]?shim'`), report hits, then offer a graph/log/trace
follow-up. The ONLY time you may run zero tools is an empty utterance.
Picking the verb is YOUR job from the utterance — a phrase like "count
last hour L-server requests by model" is unambiguously the **log** verb;
"what happened last hour" is **trace**; a lone symbol is **search**
(or **graph** if it says follow/callers). Ambiguity about *scope* is
resolved by searching repo-wide first, not by halting.

**Typos are the user's, not the corpus's — climb the fuzz ladder before
you say "no hits".** A seed can be misspelled, mis-cased, or use the wrong
separator (`office_shim` when the code says `officeai-shim`; `treesiter`
for `tree-sitter`). Do NOT report "no matches" until you have climbed this
ladder, cheapest rung first (`kiss` — stop at the first rung that hits):

1. **Fuzz the separator** — `office_shim` → `rg -i 'office[._-]?shim'`
   (`_`/`-`/`.`/none all match). Case-insensitive is always on.
2. **Stem** — drop a trailing plural/gerund (`handlers`→`handler`,
   `parsing`→`pars`) so `rg -i 'pars\w*'` catches the family.
3. **Identifier-case variants** — try camel/Pascal/snake/kebab of the
   same word: `rg -i 'office[-_]?shim|officeShim'`.
4. **Bounded fuzzy fallback** (only if 1–3 are still zero) — insert a
   gap (`rg -i 'offic\w*shim'`), or split the token and AND the parts
   across a file (`rg -l office | xargs rg -l shim`). Do NOT go
   unbounded-Levenshtein — a gap-regex or split-AND is the lazy win.

Always **report which rung produced the hits so the user sees the
correction** — e.g. "no `office_shim`; matched `officeai-shim` (separator
fuzz)". The seed is a hint, not a spec.

**Anchor the token when COUNTING a log/JSONL corpus** — the fuzz ladder is
for the *repo seed* step. Over `/workspace/L-server` or `/agent/logs`, a
loose `office.?shim` matches incidental substrings inside prose / JSON
blobs and inflates the count (observed 69 false vs 22 true —
[`fix.archive/office-shim.md`](../../REPL/fix.archive/office-shim.md)).
For a corpus statistic use the anchored identifier (`officeai-shim`,
`\bshim\b`, `ExcelHeadlessShim`), not the fuzzed seed.

**A long instruction = a SEARCH clause + an OPERATION clause. Do BOTH.**
Users routinely fuse the target and what-to-do-after into one utterance.
`prg` is a **tool you invoke FIRST**; then YOU (the model) operate on what
it returns — the operation clause must NOT be dropped:

1. **Search clause** → the term/symbol/time-span to feed a verb.
2. **Operation clause** → what to do with the findings (summarize, assess
   scale, write a doc, compare, count, refactor-plan…).
3. **Run the search FIRST, then operate on its output.** Never answer the
   operation from memory before the tool ran; never run the search and then
   forget the operation.

**Route the operation clause to the right downstream producer** (the
verbs the model performs ABOVE the tools, on their JSON):

| operation words in the clause                    | downstream producer                                  |
|--------------------------------------------------|------------------------------------------------------|
| summarize / assess scale / write a doc / explain | **Comprehensive report** recipe → `fix.archive/*.md` |
| count / how many / compare / rank / stats        | `jq` aggregate over the hit stream (Recipe D) or a `bench` lens |
| callers / callees / refactor-plan / blast-radius | `prg-graph.sh` edges/nodes                           |
| when / last hour / who changed / regressed       | `prg-log.sh` / `prg-trace.sh` / `prg-when.sh`        |

Corpus counts still obey the anchor rule above — tighten the token, don't
fuzz, when the operation is a *count* over logs/JSONL.

Worked example (a real prior query):

> `/prg dig into office-shim and summarize into a document
>  fix.archive/office-shim.md — what is the scale of that work?`

- search clause → `office[._-]?shim` (fan out to the real `officeai-shim`
  impl, its importer, the flight gate) — Recipe C then `prg-graph.sh`.
- operation clause → (a) **write** `.github/REPL/fix.archive/office-shim.md`
  summarizing the findings, (b) **assess scale** (LOC of the shim, #call
  sites, provenance) — done by the orchestrator ABOVE the tool, from the
  tool's stable output (see "Comprehensive report" recipe).

The tool stays model-free; the operation is the model's job on the tool's
result. One utterance in → search runs → operation completes.

## Tool-authoring rules

Three rules every `prg-*.sh` obeys. They are not style preferences —
each one exists because violating it produced a concrete defect.

**1. The shell header comment IS the tool description.**
The first ~30 lines state WHAT the tool does, WHY plain `rg` does not
already do it, the subverb list, and the exit contract. An agent must
be able to route a request to the right tool by reading headers alone,
without opening the body. Reference examples: `prg-corpus.sh` (why not
plain `rg md/`: flat filenames lose the case) and `prg-minidx.sh` (why
not plain `rg`: it re-walks 22MB per lookup — but it is still the
fallback, because it is ground truth).
Header must also record **counter-measurements**: things that look like
obvious optimizations but measured badly, so nobody re-adds them. See
the `--prune-short` note in `prg-minidx.sh`.

**2. A prg tool is a THIN layer over binaries.**
`rg` / `jq` / `parallel` / `find` / `awk` do the work. Complex *routing*
between them is the value the tool adds; reimplementing what a binary
already does is not. Zero model calls in the tool path — every helper
here stays model-free so it is deterministic and cheap to bench.
Corollary: process overhead is real. `prg-minidx.sh` was initially
SLOWER than the baseline it existed to beat (40.8ms vs 34.4ms) purely
from re-walking the corpus and forking `basename` per hit. Cache the
file list once per process; keep forks out of loops.

**3. Every tool ships a bench, and the bench carries a naive baseline arm.**
A tool never compared against plain `rg` cannot prove it earns its
keep. The baseline arm must need **no index and no build step**, so the
comparison is honest about setup cost. The bench also decides routing:
`minidx-bench.sh` is what proved short names must bypass the index
(recall 0.135) while long names should use it (0.935).
Bench hygiene, learned the hard way:
- **Stratify the sample.** A flat `shuf` over symbol names is dominated
  by long names and hid the short-name failure completely.
- **Refuse to report on a degenerate sample.** `idx-bench.sh` once
  returned an all-empty table with exit 0 because `grep` hit binary
  rows and emitted nothing. Benches now exit 5 when the sample is too
  small rather than printing a green table they cannot support.
- **Report the strata, not just the mean.** The aggregate recall 0.288
  reads as failure; per stratum it is 0.935 long / 0.135 short, which
  is a routing rule rather than a verdict.

### Rule-1 audit (2026-08-24) — existing tools, gaps NOT yet fixed

Header conformance across the 13 `prg-*.sh`. Compliant on all three
header elements: `prg-corpus.sh`, `prg-crashwatch.sh`, `prg-minidx.sh`.

| gap | tools |
|-----|-------|
| no WHY-not-plain-rg paragraph | graph, leg, llm, log, regress, seed, seed-cases, trace, when |
| no `Subverbs:` block | bench, graph, llm, regress, seed, seed-cases, trace, when |
| no `# Exit:` contract line | bench, graph, llm, regress, seed-cases |
| header < 20 lines | leg (19), regress (15), when (19) |

`prg-regress.sh` (15-line header, zero of three) is the worst offender
and the first to fix. This table is a TODO list, not a verdict — the
rules were written after these tools existed.

## Boundary

| Skill       | Owns                                                     |
|-------------|----------------------------------------------------------|
| `prg`       | Concurrent search mechanics: sharding, fan-out, indexing |
| `frontier`  | Which patterns / scope actually matter (human decisions) |
| `kiss`      | Whether you even need parallel, or plain `rg` suffices   |
| `exec_plan` | Turning findings into plan work-items + verification     |

## Preconditions

Both tools must be on `PATH` (installed to `/usr/local/bin` in this
container; NOT baked into the image — reinstall if the container was
recreated):

```bash
command -v rg parallel jq >/dev/null || {
  echo "MISSING: install ripgrep + GNU parallel + jq (see .github/copilot-instructions.md)"; }
mkdir -p ~/.parallel && touch ~/.parallel/will-cite   # silence citation nag
JOBS="$(nproc)"                                        # fan-out width
```

Per-verb inputs (each helper degrades gracefully — exit 3/4 — when absent):

```bash
# graph  : an LSP server is optional (jedi / ts-morph); exit 3 -> lexical tier.
# log    : L-server request/response corpus.
export PRG_LOG_CORPUS=/workspace/L-server
# trace  : append-only telemetry (*.jsonl lenses).
export PRG_TRACE_CORPUS=/agent/logs
# fast-model orchestration (CKP-5b): a local model proxy on :11434.
curl -sf http://127.0.0.1:11434/v1/models >/dev/null \
  && echo "proxy up" || echo "proxy DOWN -> orchestrate with the session model"
```

## When plain `rg` is enough (do NOT reach for prg)

- One pattern, one tree, you just want matches → `rg PATTERN dir`.
- You want files-with-matches → `rg -l PATTERN dir`.
- `rg` respects `.gitignore` and threads over files automatically.

- **A BINARY-INDEX corpus (doc/ppt/pdf/xlsx sidecars) → plain `rg`.**
  Measured on 19,440 files / 761 MB / 15k sidecars, 16 cores:

  | over `*.md` sidecars                | over `*.meta.jsonl` (xlsx) |
  |-------------------------------------|----------------------------|
  | `rg` alone **48-60 ms**             | `rg` alone **49-61 ms**    |
  | `find \| xargs -P16 rg` 173-259 ms  | same fan-out 270-312 ms    |
  | `find` alone 69-75 ms               | — 3-6x SLOWER either way   |

  Fan-out LOSES, and `find` alone already costs more than rg's whole
  search. `rg` is itself a parallel walker with a work-stealing thread
  pool; `find | xargs -P16 rg` replaces that walk with a SERIAL walk plus
  process spawns. Sharding a tool that shards itself is negative work.

Use `prg` only when at least one of these is true:
1. **Sharding** — the tree is huge / on a slow FS and you want independent
   `rg` processes per top-level dir so one giant walk isn't the bottleneck.
   ⚠️ Measure before believing this: on the 761 MB binary-index corpus
   sharding was 3-6x SLOWER (table above). "Huge tree" is not by itself a
   reason — rg already threads the walk.
2. **Multi-pattern fan-out** — you have N patterns/categories and want one
   job per pattern (e.g. building a categorized index).
3. **Per-shard post-processing** — each match needs a heavier step
   (json parse, per-file extraction, counting) that you want spread
   across cores rather than run serially after a single `rg`.

**The `rg -l` PREFILTER — the one move that reliably wins.** For
`rg + jq` over JSONL sidecars, the payoff is not spreading the work,
it is ELIMINATING it. `rg -l` cheaply names the few files that can
possibly contain a hit, and `jq` (the expensive parse) then runs on
those alone:

```bash
rg -l -g '*.meta.jsonl' -- 'Revenue' "$CORPUS" \
  | tr '\n' '\0' | xargs -0 -r -P16 -n32 \
      jq -c 'select(.k=="sheet" and (.s|test("Revenue")))'
```

`jq` over all 6,676 sidecars: **342-361 ms**. With the prefilter:
**54-59 ms** — 6x, because 6,676 files collapse to **9**. Both return
the identical 5 rows, so the prefilter is LOSSLESS *provided* the rg
pattern is implied by the jq predicate (rg over-selects, jq decides).
Pick an rg pattern that CANNOT be narrower than the jq test, or you
silently drop rows. `xargs -r` matters: without it a zero-hit prefilter
runs `jq` on stdin and hangs.

**The same rule applies to the LINES INSIDE one sidecar — and that is the
half everyone forgets.** The rule above was read for years as being about
*file* selection, so once a single big sidecar was in hand every extraction
went straight to `prg-silo.sh cells`, which `jq`-parses the whole stream.
But a sidecar is *itself* JSONL, i.e. text, so `rg` can drop its
non-matching **rows** first. Measured on a 37 MB / 42,403-row sidecar,
projecting one column:

| arm                                        | wall  |
|--------------------------------------------|-------|
| `prg-silo.sh cells … \| jq`                | 4.99s |
| `rg -N '"c":4' … \| jq` (identical output) | 0.17s |

**29x, byte-identical** (`cmp`-verified). Losslessness needs the same
precondition as the file-level rule: `"c":4` is implied by `.c==4`, so rg
cannot be narrower than jq — a pattern on `.v` would not be safe.

:trap: **SELECTIVITY IS THE SPEEDUP — do not quote 29x as a general
number.** That is the ceiling for the narrowest possible prefilter. Widen
the projection and the win collapses: `prg-case.sh diff` pulls three
columns from two files and measures **2.6x** end-to-end
([`bench/case-bench.sh`](bench/case-bench.sh)). Quote the number your own
projection earns.

:hard-rule: **ONE TOOL FOR EVERY EXTRACTION IS THE SMELL.** `prg`'s value
is *balancing* `rg`, `jq` and the table lenses; `silo` only ever reaches
the `.prg.jsonl` sidecar. If a whole investigation ran through a single
verb, the routing step was skipped — and the cost is not just latency. A
monoculture also decides what you *look at*: in the case that produced this
note, every numeric question was answered off the sidecar and the
`.sql` file carrying the actual root cause was never opened, because it is
`source=text` and `silo` cannot see it.

## `bin2md` — the document→cells extractor (five formats, not just xlsx)

`silo` reads spreadsheets. **`bin2md` reads xlsx, docx, pptx, pdf, csv/md
and emits ONE cell-stream shape for all of them**, so a query written for
a workbook also runs against a Word table or a slide table. That is the
reason to reach for it: not speed, *reach*.

```bash
bin2md --help | jq .        # self-describing: flags, modes, errors, schema
```

:hard-rule: **`--help` IS THE SCHEMA — read it before writing a filter.**
It is machine-readable JSON carrying every key's meaning, including the
traps below. If a query surprises you, re-read `--help | jq .keys` rather
than guessing; the blob is generated from the same source as the emitter,
so it cannot drift the way this document can.

### ONE stream, two row families, told apart by `.k`

`--cells` is **not a second mode**: it *adds* `k=cell` rows to `--blocks`
**and implies it** (`--help`: *"adds k=cell rows to --blocks (and implies
it)"*). So a `--cells` stream carries BOTH families and every selector
below reads the same file:

| you want            | invoke                | selector                     |
|---------------------|-----------------------|------------------------------|
| document text       | `bin2md --blocks F`   | `select(.k==null)`           |
| **table cells**     | `bin2md --cells F`    | `select(.k=="cell")`         |
| tables/charts meta  | `bin2md --cells F`    | `select(.k=="table")`, `"af"`, `"chart"` |

`--cells` is OPT-IN because cells outnumber block rows **8x** (measured,
40 xlsx: 40,412 vs 4,774) — not because the block rows go away.

:trap: **`.k==null` means CONTENT here — the OPPOSITE of `silo`,** where
`.k==null` means cells. Getting this backwards returns a plausible,
entirely wrong row set. `bin2md --help` says so in its own `doc` string.

:hard-rule: **NEVER select cells with `select(has("k")|not)`.** On a
bin2md stream that returns the *markdown block* rows, which have no
`.r`/`.c` — so a downstream `group_by(.r)` collapses them into one phantom
`r:null` bucket and the query returns a plausible wrong answer with rc=0.
Measured on one corpus workbook: **43 markdown rows instead of 329 cells.**
Prefer the STRUCTURAL test `select(.r != null and .c != null)`, which is
exact on **both** parsers and is what `jq/select.jq` and
`jq/silo-schema.jq` use.

:trap: **`k=schema` and `k=file` are meta rows that also carry `.k`,** so
"does this sidecar have any `.k` rows?" is always true and cannot be used
as a parser probe or an emptiness guard. Test for the row family you
actually want (`.k=="cell"`).

### The cell row

```json
{"k":"cell","conf":2,"tbl":1,"r":2,"c":2,"v":"2024-01-05","t":"date","a":"B2","s":"Sheet1"}
```

| key | meaning |
|-----|---------|
| `r`,`c` | 1-based position **in the rendered table**, every format |
| `a` | true A1 address — **xlsx only**, `has("a")` is a real test |
| `tbl` | on `k=cell` it is **file-unique** → the join key |
| `s` | section (sheet name / `Slide N`); **absent** on csv/pdf — that is correct, not a gap |
| `t` | `"n"` numeric, `"date"` ISO-8601 rewritten; **absent = not declared** |
| `tc` | `tc:1` = the type was INFERRED (csv/md/pdf); absent = the file DECLARED it |
| `conf` | extraction confidence, **not** type confidence |

:trap: **empty cells are OMITTED, so `c` is not contiguous.** Never infer
column count from row length; use `max(.c)` or read `k=table`.

:trap: **`r` is the RENDERED position, `a` preserves the sheet's real
gaps.** For a silo-comparable address use `a`; for a key that means the
same thing in all five formats use `r`. They deliberately differ.

:trap: **PORTING FROM silo: a consumer that finds formula cells via
`.v == null` BREAKS SILENTLY.** silo left `v:null` on a formula cell;
bin2md omits the key entirely. Test `has("f")`. This returns a plausible
empty result rather than an error, so it will not announce itself.

### Detecting tables

Two ways, and they answer different questions:

```bash
# 1. AUTHOR-DECLARED regions — the file itself says "this is a table".
#    conf:2 = read verbatim, not inferred.  Carries name/ref/hdr/cols.
bin2md --cells F | jq -c 'select(.k=="table")'
#    {"k":"table","name":"Sales","ref":"A3:C200","hdr":1,"cols":["Q","Amt"],...}

# 2. WHAT ACTUALLY GOT EXTRACTED — group the cells.
bin2md --cells F | jq -c 'select(.k=="cell")' \
  | jq -s 'group_by(.tbl)[] | {tbl:.[0].tbl, s:.[0].s, rows:(max_by(.r).r), cols:(max_by(.c).c)}'
```

Use (1) when you need the author's own header names; use (2) when you need
what is really there. A file can have zero `k=table` rows and still be full
of cells — docx/pptx/csv tables are structural, not declared.

:hard-rule: **DEFAULT TO (2). `k=table` is RARE — measured 0 rows across
300 corpus xlsx.** It requires a real Excel *ListObject* ("Format as
Table"), which almost nobody uses; a normal sheet of data emits none. The
emitter is correct (`src/xlsx.c:828`, asserted in `assert-table.sh`) — the
files simply don't declare. Write (1) as an *optional enrichment* and never
as your detector, or your query returns empty on a file that is visibly
full of tables.

:trap: **`hdr:0` is real and occurs in the wild.** Do not treat it as
unset; a table can legitimately declare no header row.

### Query by select — the header join

There is no header field on a cell row. That is deliberate: `h` would
duplicate row 1 on every row (measured **+70%** stream size). Join to it:

```bash
# Column named "Amount" in table 1 → its data cells.
bin2md --cells F | jq -c 'select(.k=="cell")' | jq -s '
  (map(select(.tbl==1 and .r==1 and .v=="Amount"))[0].c) as $col
  | map(select(.tbl==1 and .c==$col and .r>1)) | .[]'
```

That two-pass shape — *find the column, then filter by it* — is the
workhorse. Everything below is a variation on it.

### Time-range queries

Dates are rewritten to **ISO-8601 precisely so lexicographic order equals
chronological order**, which is what makes a plain string comparison a
correct date filter:

```bash
bin2md --cells F | jq -c 'select(.t=="date" and .v>="2024-01-01" and .v<="2024-12-31")'
```

:trap: **`select(.v >= 44197)` is NOT a date filter and never fails
loudly.** `jq` orders numbers before strings, so *every* string is `>=`
any number — that filter returns 100% of rows whether or not the ISO
rewrite happened. Verified: `jq -n '"2021-01-01" >= 44197'` → `true`.
Compare against ISO **strings**, always.

:trap: serial **60** stays numeric (`t:"n"`). It is Excel's fictional
1900-02-29; bin2md refuses to emit a day that never existed, so a
date-only filter correctly skips it rather than inventing 02-28.

### rg narrows, jq computes

The doctrine above applies verbatim to cell sidecars — `rg` is the *file
and line* selector, `jq` is the *query engine*. Do not ask `rg` to
compare a date; do not ask `jq` to open 20k files.

```bash
rg -l '"t":"date"' --glob '*.prg.jsonl' . \
  | xargs -r -d'\n' cat \
  | jq -c 'select(.t=="date" and .v>="2024-01-01" and .v<="2024-12-31")'
```

Measured on the microcosmo corpus: `rg` narrowed 20k sidecars → **367 in
0.38s**, then `jq` returned **7,242** in-range cells in 0.84s.
**Losslessness verified**, not assumed: full-jq scan and rg-prefiltered
scan both returned **1,789** rows over 300 files. The precondition is the
same as always — `"t":"date"` is implied by `.t=="date"`, so `rg` cannot
be narrower than `jq`. A pattern on `.v` would NOT be safe.

### Join across files

`tbl` is file-unique, so `(file, tbl, r, c)` identifies one cell globally
— and the sidecar's own filename supplies `file`, which is why no `f` key
rides the rows (it was 61% of the stream; it was removed):

```bash
# Fold the filename in from the sidecar name, then join.
for s in **/*.prg.jsonl; do
  jq -c --arg f "${s%.prg.jsonl}" 'select(.k=="cell") | .f=$f' "$s"
done | jq -s 'group_by(.f)[] | {f:.[0].f, cells:length}'
```

The same trick joins a cell stream to `k=chart`: a chart's `series[].val`
is an **A1 range formula** (`'Sheet1'!$B$5:$B$63`) — the join key back
into the cells via `a`, which is why `a` exists alongside `r`.

### Drop-in

Installed at `/usr/local/bin/bin2md`; scripts honour `PRG_BIN2MD` for an
override. **The argv contract is `--batch LIST OUTDIR`**, one process for
N files, index JSONL to stdout and cells to sidecars.

**Producing the sidecars** — `OUTDIR '-'` means *beside the source*:

```bash
find corpus -name '*.xlsx' > list
bin2md --batch list - --cells      # writes <name>.<ext>.prg.jsonl per file
bin2md --batch list -              # writes <name>.<ext>.prg.md   per file
```

The source extension is KEPT (`cr17.dat` → `cr17.dat.prg.jsonl`), so two
files differing only by extension never collide. Line 1 of every sidecar is
the `k=schema` provenance row — that is what `prg-corpus.sh` keys on to
tell a bin2md sidecar from a silo one.

:trap: **in `--batch`, stdout is the INDEX, not cells.** `--batch L - --cells`
looks like it silently produced nothing; the cells went to the sidecars,
exactly as documented. Per-file `bin2md --cells F` is the stream you want.

:trap: `src/collect/index_folder.sh:158` hardcodes `python3 "$BIN2MD"`, so
dropping a *binary* at the `.py` path fails with `WARN: N lost` that reads
like an extractor bug. It is not — the argv contract is honoured exactly
(24 files in, 24 rows out). Use a two-line `exec` shim, or fix line 158.

### :trap: MULTI-FORMAT IS ALSO A HAZARD — "it parsed" is not "it is data"

bin2md's reach is the reason to use it, and the reason a *failure* can look
like a success. It does not reject a file for having the wrong contents; it
finds *some* reader that works. Two measured false greens:

- **A text file named `.xlsx` parses as a one-paragraph doc with rc=0.** So
  `rc` alone is not a validity test. Conversely `corrupt.xlsx` returns rc=1
  but **still writes the schema row**, so a `-s` non-empty test also passes.
  Detecting an unreadable workbook needs **both** rc≠0 **and** a zero-cell
  test (`bin2md --help | jq .exit` documents the codes).
- **An HTML export table named `.xls` yields hundreds of cells whose values
  are raw markup** (`<tr><td colspan=11...`) — bin2md falls back to a
  CSV-ish reader and splits the tags on commas. rc=0, healthy cell count,
  **zero data**. A zero-cell test cannot catch this; the cells are there.
  Measured contamination (`</?(td|tr|table|html|body)\b`) is **bimodal with
  an empty middle** — 12 files at 0%, 6 files at 95–100% — so a ratio test
  thresholded anywhere in the gap separates them cleanly (`bin2md-summary.jq`
  emits `markup`/`junk` for this).

:trap: **the HTML route is NOT deterministic across files** — one HTML `.xls`
yields ONE paragraph and ZERO cells (caught by the zero-cell test), another
yields hundreds of junk cells (not caught). Never generalize from one file.

:hard-rule: **Do NOT "fix" this by rejecting non-OLE input.** Files that are
really xlsx (or plain text) mislabeled `.xls` are **genuine recoveries** that
silo cannot read at all — measured 11,945 real cells across three of them,
versus 1,221 junk cells to reject. Test the *contents*, not the container.

## Stable output contract

Agent-first: every helper's DEFAULT output is machine-parseable and pinned
here so a consuming agent can parse without reading source. Human views are
opt-in behind `--pretty`.

### edges.tsv  (prg-graph.sh)
Tab-separated, one edge per line:

    src \t dst \t path \t line \t kind          kind ∈ {def, ref}

- `src` = enclosing symbol at the ref site, or the literal sentinel
  `«toplevel»` when a ref sits outside any named def.
- `dst` = the queried symbol; for a `def` row `dst` is the literal
  sentinel `«def»`.
- `«toplevel»` and `«def»` are stable literal tokens — match on them.

### search-hit JSONL  (search verb, `--json` / Recipe D)
Opt-in structured hit stream — one JSON object per rg match, via the
`search-hit.jq` lens over `rg --json`. Default search output stays raw rg
lines (this is behind `--json`, not the default):

    {path, line, col, keyword, content, index}

- `line` / `col` are 1-based; `col` is the first submatch's column.
- `content` = the matched line, trailing newline stripped.
- `index` = 1-based ordinal over the SURVIVING hits (1..N), not rg's raw
  JSONL line numbers — so the lens is fed `jq -n -c -f search-hit.jq`.

### prg-log JSONL  (prg-log.sh)
One JSON object per matched log record; only cheaply-derivable fields
(the `--logs`/`PRG_LOG_CORPUS` corpus — an LLM-server request/response log,
called "L-server" in this repo's examples, but any JSONL corpus works):

    {id, ts, model, kind, path, n_tool_calls?}   kind ∈ {request, response}

### corpus JSONL  (prg-corpus.sh) — binary-parsed document corpus
The fourth SOURCE beside repo / log / trace. Its corpus is NOT a source tree
but the output of `src/collect/index_folder.sh`: a flat `md/` of extracted
text plus `index.jsonl` (documents) and `sheets.jsonl` (workbooks). Set with
`--corpus` or `PRG_DOC_CORPUS`; no default, so unset exits 4.

    search <re> [-- rg args] → {case, path, src, line, content}
    case <id>                → {case, kind, ok, chars|cells, path, out}
    stat --by kind           → {key, n, ok, chars} + one xlsx(sheets) roll-up
    stat --by case           → {key, n, docs, formulas}   (ranked by formulas)
    sheets '<jq>' / docs '<jq>' → the manifest row + `case`, your filter applied
    failed                   → {case, path, kind, why}   (both manifests)

- `case` is derived ONCE by `jq/corpus-case.jq` (the segment after
  `/cases/`), never re-guessed with an ad-hoc sed in a caller.
- **Why this exists and plain `rg md/` does not do it:** `md/` filenames are
  FLAT and collision-suffixed, so an rg hit there has lost the case folder —
  and files inside one case are semantically related, making the CASE the
  unit of meaning. Every subverb rejoins the hit to its case via
  `index.jsonl .out` (verified unique across all rows).
- An md file present on disk but absent from the manifest gets the literal
  sentinel `«nocase»` with `src: null` — it is never dropped and never given
  a fabricated case. Same `«…»` convention as `«toplevel»`/`«def»`.
- A manifest whose rows do not all parse is refused with exit 5 and a count
  (`N of M rows parse`). This is deliberate: jq aborts mid-stream on a bad
  row, and without the gate every subverb reports the rows it managed to
  read AS IF COMPLETE, exit 0. Absent corpus (4) and broken corpus (5) are
  distinct because "no results" and "cannot tell" are different answers.
- **Do not read `cells` as amount of data.** It is a bounding-rectangle
  footprint (silo ≥ openpyxl in 20/20 sampled workbooks); `formulas` was
  corroborated 20/20 exactly and is the column to rank on.

### trajectory JSONL + object  (prg-trace.sh)
Two rounds over the telemetry corpus (`--trace`/`PRG_TRACE_CORPUS`, default
`/agent/logs`), both model-free:

- `harvest --span FROM..TO` → a flat keyword collection, one JSONL row per
  hit, every row provenance-tagged:

      {keyword, kind, source, ts, ref}
      kind   ∈ {symbol, path, span, event, tool, model, commit}
      source ∈ {trace.otel, agent.log, agent.lifecycle, git, …}   (its lens)
      ts     = lex-sortable ISO stamp it was found at   ref = traceId|file|sha

  `--pretty` aggregates → `{keyword, kind, lenses, count, score, sources}`,
  ranked by **cross-lens frequency** (a keyword seen in >1 distinct `source`
  outranks a one-off; node_modules/.d.ts down-weighted like prg-seed).

- `connect --span FROM..TO` → ONE object, validated against
  `bench/trajectory.schema.json` (python jsonschema if present, else a jq
  required-field fallback; exit 5 + stderr note on failure, never malformed):

      {session, span:{from,to},
       turns:[{turn, ts, role, keywords, refs,
               slots:{source, term:[…], task:[…]}}],   ← per-turn SOURCE/TERM/TASK
       edges:[{from_turn, to_turn, via}],       via = traceId|file|keyword|ts
       keywords:[{keyword, kind, count, refs}]}

  Edges are DETERMINISTIC/tool-derived (shared traceId, shared changed-file,
  shared Round-1 keyword, adjacent turn ordinal) — no model connects the dots.
  Each turn's `slots` is the SAME SOURCE/TERM/TASK decomposition the parse
  recipe applies to one utterance (see "## Trajectory = the workflow spine"),
  derived deterministically by partitioning the turn's keywords by `kind`:
  SOURCE = the turn's lens/role; TERM = kinds symbol|path|span|commit;
  TASK = kinds event|tool|model. No model — a pure partition of fields the
  turn already carries.

`--span` sides accept **human/relative time** (`prg-when.sh` normalizes):
`"1 hour ago"`, `"this morning"`, `"noon"`, `"HEAD~2"`, or ISO — see the
"Time-sensitive corpora" callout in copilot-instructions.md.

### Exit codes (shared by all helpers)
    0  ok
    2  missing dependency / bad args
    3  unsupported file type / no LSP server / proxy unreachable
       (the CALLER may fall back — e.g. lexical engine, or --no-model)
    4  corpus / target absent
    5  schema validation failed (prg-trace.sh connect)

### jq filter library  (jq/*.jq)
The JSONL contract is versioned as predefined jq filters (invoked via
`jq -f jq/<name>.jq`), NOT ad-hoc one-liners. Each carries a
header-comment stating its output shape:

| filter                 | input record                    | output                                                                            |
|------------------------|---------------------------------|-----------------------------------------------------------------------------------|
| `span-window.jq`       | any (`.timestamp`/`.ts`)        | passes record iff `$from ≤ ts ≤ $to`                                              |
| `otel-span.jq`         | trace.otel record               | `{sessionId, ts, type, traceId, groupId, name}`                                   |
| `transcript-turns.jq`  | transcript turn                 | `{turn, ts, role, text}`                                                          |
| `count-by-model.jq`    | LLM-log response*               | `{model}` (aggregate → `{model,n}`)                                               |
| `tool-calls.jq`        | LLM-log request*                | `{tool_name}` per declared tool                                                   |
| `session-tool.jq`      | session events.jsonl            | `{tool}` per `tool.execution_start` (live shape)                                  |
| `leg-chain.jq`         | session events.jsonl‡           | `{n,tool,ok,digest}` ORDERED chain (join on toolCallId)                           |
| `session-tool-when.jq` | session events.jsonl            | `{tool, day}` — TIME-aware variant for span filter                                |
| `trace-otel.jq`        | trace.otel.jsonl (span)         | `{keyword,kind,source,ts,ref}` (span-name harvest)                                |
| `trace-agentlog.jq`    | agent.log.jsonl (span)          | `{keyword,kind,source,ts,ref}` (event/path harvest)                               |
| `trace-lifecycle.jq`   | agent_lifecycle.jsonl           | `{keyword,kind,source,ts,ref}` (state-transition)                                 |
| `search-hit.jq`        | rg --json match record          | `{path,line,col,keyword,content,index}` per hit                                   |
| `bench-tool.jq`        | ssg-sim `report.json`†          | `{tool, verdict}` per case (aggregate → by-tool pass rate)                        |
| `select.jq`            | silo OR bin2md cell stream §    | one row per MATCH: `{r, a?, row:{<col name>: value}}` (`a` = A1 addr, absent for pdf/pptx) |
| `silo-schema.jq`       | silo meta+cell, BOTH ¶          | `{file,sheet,hdr_row,c_lo,c_hi,r_lo,r_hi,ref,rung,conf}` per candidate rect       |
| `corpus-case.jq`       | corpus `index/sheets.jsonl` row | THE WHOLE ROW **plus** `case` (id after `/cases/`) — derived once, never re-sed'd |
| `bin2md-summary.jq`    | SLURPED bin2md `--cells` ✦     | ONE `sheets.jsonl` roll-up row: `{path,markup,junk,sheets,cells,formulas,used,charts,tables,af}` |

✦ `bin2md-summary.jq` replaces `silo --summary` in `index_folder.sh` — **40/40
EXACT** on all seven shared fields. bin2md emits no `k=sheet` meta row, which
reads like a gap; it is not, every field is derivable from rows already in the
stream. Two traps, both silent: (1) silo's `cells` EXCLUDES formula cells while
`used` includes them, so `cells = used − formulas`, **not** `count(.k=="cell")`
(15/40 mismatch when wrong); (2) count `sheets` over ALL rows — an EMPTY sheet
has zero cells but still appears on a block row carrying `.s` (1/40 when wrong).
`route`/`titles`/`kinds` are deliberately NOT derived: zero consumers repo-wide.

\* input record type from the `--logs` corpus (any JSONL log; the repo's is
an LLM request/response log). Adapt or add a lens for another log shape.

† `bench-tool.jq` takes ONE report OBJECT, not a record stream — invoke it
without `-n` (`jq -f bench-tool.jq report.json`), unlike the JSONL lenses above.

‡ `leg-chain.jq` is SLURPED (`jq -s -f leg-chain.jq events.jsonl`) so one pass
can join `tool.execution_start` to `tool.execution_complete` on `toolCallId`;
`prg-leg.sh` wraps it with the traffic-side summary (Recipe G).

¶ INPUT IS TWO CONCATENATED STREAMS, and it fails SILENTLY without both:
```sh
{ silo --dump-meta-json F; silo --dump-json F; } | jq -s -c -f jq/silo-schema.jq --arg file F
```
Feeding it `--dump-json` alone (the shape every other cell lens takes) emits
NOTHING with exit 0 -- no error, no warning.  R1/R2 read frozen panes and
`table`/`autofilter` declarations, which live ONLY in the META rows (meta rows
have `.k`; cell rows do not).  Use `bench/detect.sh` as the reference caller.

¶ `silo-schema.jq` is the TABLE-DISCOVERY ladder (plan 256 G8), the second
spreadsheet-family lens beside `select.jq`.  It answers "where ARE the tables
on this sheet?" — the question `select.jq` presupposes an answer to.  Four
rungs, tried in order, stopping at the first that fires: R1 frozen panes ·
R2 declared `table`/`autofilter` · R3 header-shape (type transition + mostly
short + >=70% DISTINCT labels) · R4 fallback.  Each emitted rect carries the
`rung` that produced it — always report per rung.

!! READ THE NUMBER CORRECTLY.  The full ladder's 0.897 exact-ref recall is
**91% tautology**: the gold set was DERIVED from `table`/`af` declarations and
R2 re-reads those same declarations, so R2 cannot fail by construction (119 of
131 hits).  The honest, non-circular figure — R1/R2 disabled so the shape rungs
are actually tested — is **0.418** exact-ref recall, 0.778 negative-sheet clean
rate.  Quote 0.418, never 0.897.

!! NOT WIRED TO A RUNTIME VERB YET.  `prg-silo.sh where` is DECLARED-ONLY by
design (43.8% of sheets carry a declaration; it is silent on the other 56.2%)
and must stay that way — "declared, never inferred" is a correctness contract,
not a limitation.  Inference belongs in a SEPARATE verb so a caller can never
mistake a guess for a declaration.  Until that verb exists this lens is
reachable only by invoking it directly.

§ `select.jq` differs from every lens above on BOTH axes, so read it twice.
CORPUS: its input is a SPREADSHEET cell stream (`silo --dump-json` →
`{s,r,c,a,t,v,f?}`), not a log/session record — it is the first of that
family, and a log-shaped lens will not read it.  SLURPED like `leg-chain.jq`
(`jq -s -f select.jq cells.jsonl`) because SQL-style grouping needs the whole
sheet in hand: `--dump-json` emits CELLS with no row container, so a WHERE
clause spanning two columns has to rebuild the row first.
That also makes it NOT DECOMPOSABLE: never run it under `parallel --pipe`,
since a block boundary can cut a row in half and both halves then fail the
WHERE and vanish silently, leaving a plausible-looking smaller count.
Shard by FILE instead — rows never span workbooks.  Memory binds before
time (~6.3x input when slurped); past ~1M cells shard, do not scale up.

The bench asserts these against a REAL corpus. Before hand-editing
`bench/gold-search.tsv` or `bench/regress.baseline.tsv`, read
[`fix.archive/prg-bench-coverage.md`](../../REPL/fix.archive/prg-bench-coverage.md) —
the gold set is a computed artifact; you RE-MINE it, you do not type counts.

## The canonical recipes

The open-ended part of this doc — **append a new lettered recipe when a new
verb or workflow earns one**; do not compress the existing ones to make room.
A–D are the search/index family, E is `trace`, F is crash-triage, G is the
orchestration loop.

Always pass `-0` / `-print0` with `find`, and `--no-messages` to `rg` so
permission noise on one shard doesn't abort the run. Merge with `sort -u`.

### Recipe A — shard by top-level directory (biggest-tree case)

```bash
find <root> -maxdepth 1 -mindepth 1 -type d -print0 \
  | parallel -0 -j"$JOBS" 'rg -l --no-messages "PATTERN" {} 2>/dev/null' \
  | sort -u
```

One `rg` per subtree, all running concurrently. `{}` is the dir. Good when
`<root>` has many large children (e.g. in this repo, `modules agents packages`).

### Recipe B — file-list once, then fan a heavier op per file

```bash
rg -l --no-messages 'PATTERN' -g '!**/node_modules/**' -g '!**/dist/**' <root> \
  | parallel -j"$JOBS" 'printf "## %s\n" {}; rg -c --no-messages "SUBPATTERN" {}'
```

`rg -l` builds the candidate set fast; `parallel` spreads the expensive
second pass (structured extraction, json parse, count) across cores.

### Recipe C — one job per pattern (categorized index build)

```bash
printf '%s\n' pat1 pat2 pat3 \
  | parallel -j"$JOBS" 'rg -l --no-messages {} -g "!**/node_modules/**" <root> \
      > /tmp/idx/$(echo {} | tr -c "[:alnum:]" _).txt'
```

Builds a per-pattern (per-category) index in parallel — the pattern that
produced `/tmp/otel-index/`. Combine with a `categories.txt` mapping
`name<TAB>regex` and iterate with `parallel --colsep '\t'`.

### Recipe D — structured hit stream (`--json`: one JSON object per hit)

Opt-in. The default search recipes above emit raw `rg` lines / file lists
(agent-first, zero render cost). When you want the middle-collection to be
**queryable** — `rg` greps the `content` field, `jq` queries `path`/`line`/
`keyword` — pipe `rg --json` through the versioned `search-hit.jq` lens:

```bash
rg --json 'PATTERN' -g '!**/node_modules/**' -g '!**/.git/**' <root> \
  | jq -n -c -f "$(dirname "$0")/jq/search-hit.jq"
# -> {"path":…,"line":…,"col":…,"keyword":…,"content":…,"index":…}  (one per hit)
```

`rg 14.1.1` emits native JSON Lines with `--json` (a `{"type":"match"}`
record per hit carrying path / line_number / lines.text / submatches);
`search-hit.jq` flattens each to the stable **search-hit** schema (below).
`index` re-numbers 1..N over surviving hits, so `jq -n` (null input,
stream via `inputs`) is required — see the lens header. This is the SAME
`rg --json + jq` pattern the grapher uses; no new tool. Shard it exactly
like Recipe A/B by fanning `rg --json {} | jq …` across `parallel`.

Replaces scattered `/tmp/*.txt` middle-files with one structured JSONL
stream you can re-query without re-searching:

```bash
rg --json 'PATTERN' <root> | jq -n -c -f …/search-hit.jq > /tmp/hits.jsonl
rg '"content":"[^"]*ERROR' /tmp/hits.jsonl        # grep the content field
jq -c 'select(.path|endswith(".ts"))' /tmp/hits.jsonl   # query by path
```

### Recipe E — trajectory deep-dive (`prg-trace.sh`: two-round time-span)

The `trace` verb answers "what happened in this time window" over the
append-only telemetry corpus. It is a **two-round methodology** — an agent
orchestrates ABOVE it; the tool never calls a model.

```bash
export PRG_TRACE_CORPUS=/agent/logs           # default; a dir of *.jsonl lenses
# Round 1: harvest a flat, provenance-tagged keyword collection in a span.
prg-trace.sh harvest --span "1 hour ago..now"            # human/relative time OK
prg-trace.sh harvest --span "HEAD~2..HEAD" --repo .      # git-ref span
prg-trace.sh harvest --span 2026-08-05T08:00..08:22 --pretty   # ranked, grouped
# Round 2: connect the harvest into ONE schema-validated trajectory object.
prg-trace.sh connect --span "this morning..noon" > /tmp/traj.json
```

Round 1 is **bounded**: the ISO span-compare is the FIRST jq expr so most
records drop before any field access. For a recent/open-ended `TO`, the
scan is a **byte-window tail-first seek** (`tail -c … | tac`) — O(window),
not O(file); a historical/full-range span auto-falls-back to a
**parallel-forward** scan (`parallel --pipepart --block 8M`). See the
"tail-first" and "parallel-jq" callouts in copilot-instructions.md — the
two compose (fast path + exhaustive fallback).

Round 2's output is the single artifact a driving agent parses without
reading source (schema at `bench/trajectory.schema.json`). A worked example
of the graph/index a dive produces:
[`fix.archive/OTel.map.md`](../../REPL/fix.archive/OTel.map.md).

### Recipe F — crash-triage: log exception → symbol → source (HERO 3)

An uncaught exception lands (in a log line, a paste, a crash dump). This is
a **fused SOURCE1 + TERM + SOURCE2 + TASK** utterance — parse it, then walk
a THREE-verb chain across TWO knowledge domains: mine the LOG for the frame,
map the frame to a SOURCE symbol, then SEARCH the source for the fix.

```bash
# STEP 1  LOG → FRAME.  rg the error record, jq the method/frame/message.
rg '"level":"error"' app.jsonl \
  | jq -r '"\(.err.method) -> \(.err.frame) :: \(.err.message)"'
#   WebSocketManager.onSessionClosed
#     -> dist/src/websocket/websocket-manager.js:850:33
#     :: ownerAgent?.hasActiveTurn is not a function

# STEP 2  FRAME → SYMBOL.  The join key is the METHOD name, not the line.
sym=onSessionClosed          # = "${method##*.}"

# STEP 3  SYMBOL → SOURCE.  Graph the symbol in SOURCE (never dist).
prg-graph.sh "$sym" --root modules/core/src --out /tmp/crash
awk -F'\t' '$5=="def"{print $3":"$4}' /tmp/crash/edges.tsv   # the SOURCE def-site
```

**The load-bearing lesson — a stack frame's `dist/…js:LINE` is NOT a source
line.** The line number is a *build artifact*; opening it in source will
mislead you. Pivot on the **symbol**, resolve the **source** (`.ts`) def
with the graph, and read the guard there. Here the dist `:850` maps to the
source guard region ~984, while the method's def is at source `:868` — three
different numbers for one symbol. That gap is itself the diagnosis:

> If the SOURCE is already guarded (e.g. the optional-CALL
> `ownerAgent?.hasActiveTurn?.()`) yet the crash frame shows the *unguarded*
> call, the running binary is a **stale deployed dist / process**, not a
> source bug. Fix = rebuild + restart, not edit.

Parse it as: `SOURCE1=log(exception)`, `TERM=the method symbol`,
`SOURCE2=repo source`, `TASK=locate the def-site & compare the guard` — see
["Parse the utterance first"](#parse-the-utterance-first--source--term--task).
This recipe is **gated in the benchmark**: `prg-regress.sh`'s
`case_crash_triage` replays a pinned exception record through the whole
chain and REDs if jq can't pull the method or the def resolves to `.js`/dist
instead of a `.ts` source file.

### Recipe H — debug one ssg leg: the session+traffic 2-file join (`prg-leg.sh`)

When a graded ssg-sim run leaves you asking "what did the model actually DO
and SAY in case Y of run X?", `prg-leg.sh` opens the TWO correlated files for
that leg and prints a glanceable trace — no scrolling 70+ raw events, no LLM.

```bash
# by run dir + leg id (the 8-hex in the traffic filenames):
prg-leg.sh /workspace/ssg-sim/run_<ts>_<slug>_<hash> e5bf2c12
# or straight at the response.json:
prg-leg.sh /workspace/ssg-sim/run_.../<ts>_e5bf2c12.response.json
```

Output = one summary line + the ordered tool chain + the answer:

```
leg=answer  ok=true  http=200  dur=36122ms  tools=5  msgs=3  child=f1ae6bf6
  1. skill  OK  skill=wisesheets-test-dc
  2. view  OK  docs--wiseprice-function.md
  ...
said: Please provide the ticker symbol and the start and end dates. …
```

The join: the traffic `*.response.json` carries `.ssg_sim.childSessionId`,
which names the child session dir under the run's isolated copilot home; there
`tool.execution_start` joined to `tool.execution_complete` on `toolCallId` (in
file order) IS the chain, and the longest `assistant.message .data.content` IS
the answer. `said:` makes the debug verdict obvious — a real program
(`await Excel.run(...`) vs. a refusal/question tells you the failure mode at a
glance. Reasoning is SEALED (provider-encrypted `reasoningOpaque`) — this tool
reports DID + SAID only; see
[`REPL/fix.archive/CoT.extracted.md`](../../REPL/fix.archive/CoT.extracted.md).

### Recipe I — WHICH FILE, and does it agree with itself? (delivered-artifact triage)

The commonest real Excel question is not "compute something" — it is **"which
of these near-identical files did I actually send, what parameters made it, and
does it still agree with the figure next to it?"** A practitioner timed herself
at 90 minutes on exactly this: ~20–25 min proving which of two workbooks the PI
held, ~25 min reconciling her answer against the PI's figure, ~10 min of actual
analysis. All of it is index work, and none of it needs Excel.

Run the ladder in this order — each rung is cheap and **falsifiable**, and you
stop as soon as one discriminates:

```bash
# 1. WHICH FILE?  Sheet inventory first -- a delivery convention (a hand-added
#    README/params/notes tab) usually separates "delivered" from "intermediate"
#    when the FILENAMES cannot.  One call, off the index.
for f in cand_a.xlsx cand_b.xlsx; do
  echo "$f: $(prg-silo.sh sheets "$f" | jq -r .sheet | paste -sd,)"
done
# cand_a: README,IFNb_vs_UT,...   <- the delivered one
# cand_b: IFNb_vs_UT,...          <- intermediate, no decision record

# 2. WHAT PARAMETERS?  That tab is prose, but it is CELLS, so it is greppable.
prg-silo.sh cells v2.xlsx 'select(.s=="README")|.v' | jq -r 'select(type=="string")'
#   design formula, which sample was dropped and why, which cutoffs were
#   applied, "vN supersedes vM".  Frequently the ONLY surviving record --
#   not in the script, not in the email.

# 3. THE ANSWER.  GROUP by row -> WHERE over the whole row -> PROJECT.
#    (Recipe: never filter CELLS before grouping; you throw away the column
#    the other predicate needs.  See jq/select.jq.)

# 4. DOES IT AGREE WITH THE FIGURE?  A chart/PDF next to the workbook often
#    states its own filter in its title.  Extract it from the .prg.md sidecar
#    and apply THAT filter to the workbook -- apples to apples.
grep -oE '[0-9]+ genes' figure.pdf.prg.md      # what the figure claims
#    ...then count the workbook under the figure's stated cutoffs.
```

**Rung 4 is the one nobody asks for and the one that pays.** In the worked
case the workbook and the delivered figure disagreed in *all three* panels
(76 vs 64, 75 vs 55, 78 vs 63). The analyst had found one of the three by
hand, mid-interview, and called it "the only thing standing between me and
quietly sending a wrong list."

:hard-rule: **REPORT THE DISAGREEMENT; DO NOT PICK A SIDE.** Both artifacts
were delivered by the same person on the same day. Deciding which is "right"
is the human's call and needs facts the files do not contain. Silently
choosing one is how a wrong number reaches a figure legend.

:hard-rule: **A CANDIDATE ANSWER FILE IS A CLAIM — FALSIFY IT BY MEMBERSHIP.**
The most dangerous file in a folder is the one that *looks* like the answer
(hand-typed by someone who left, same project, same PI). Test it mechanically
against the delivered data instead of judging it by name:

```bash
prg-silo.sh cells delivered.xlsx 'select(.c==2 and .r>=2)|.v' | jq -r . | sort -u > /tmp/have
prg-silo.sh cells candidate.xlsx 'select(.c==1 and .r>=2)|.v' | jq -r . | sort -u > /tmp/want
comm -23 /tmp/want /tmp/have      # non-empty => candidate is NOT grounded
```

:trap: **EMPTY IS A VALUE, NOT A GAP.** Blank symbol cells and empty
`padj`/`p-value` cells are usually deliberate (unannotated IDs; statistical
filtering). They are neither missing data nor "not significant", and they sort
unpredictably. Type-guard every numeric predicate
(`select((.padj|type)=="number")`) so text and blanks cannot masquerade as 0 —
and count the blanks that survive your filter rather than dropping them
silently.

:trap: **DO NOT RECOMPUTE FROM THE RAW INPUTS JUST BECAUSE THEY ARE PRESENT.**
The counts matrix sitting beside the results is not a shortcut to the results:
the delivered numbers came from a stated design (`~ donor + treatment`) you
cannot reproduce with a spreadsheet average. Read what was delivered.

:trap: **`~$foo.xlsx` IS AN EXCEL LOCK FILE, NOT DATA.** Skip it; it will
otherwise show up as a phantom near-duplicate of the file it is locking.

:trap: **VERIFY THE HUMAN'S NUMBERS TOO.** In the worked case the practitioner
said the counts CSV had "17 columns"; it has 19 — 2 id columns plus 17
*samples*. She was right about the biology and loose about the wording. Assert
the thing you measured, not the phrasing you were handed.

Worked, fully-asserted examples — both on this same case:
[`bench/chain-bench.sh`](bench/chain-bench.sh) (9/9) runs it THROUGH the
tool chain (`prg-case.sh plan` → `read` → `jq` → `awk`), so it is what
breaks when a verb's contract changes. `case-delgado.sh` (15/15) asserts
more of the case (design formula, decoy genes, sample columns) but calls
no prg verb and still lives out-of-repo at
`/workspace/crawler/table_recoginze/bench/` — port it before relying on it.

### Recipe G — the orchestration loop (model at the head, tools model-free)

This is the loop the whole toolkit is FOR: a **fast model at the loop head**
turns a direction into keywords/spans; every *tool* underneath stays
model-free; the model reads the tools' stable output and decides the next,
parallel set of dives; repeat until the picture is complete; one final
synthesis. Only `prg-llm.sh` (the loop head) and `prg-seed.sh`'s optional
model tier ever call a model — never a tool.

```bash
# ---- R1: model picks the SEED SYMBOLS from a natural-language direction ----
# prg-seed.sh's model tier = prg-llm.sh reading the def-anchored candidate
# list and returning the best few.  Model-free tools produced the candidates;
# the model only chooses.  (Proxy down -> prg-seed.sh degrades to --no-model.)
seeds=$(prg-seed.sh 'trace propagation across process boundary' \
          --root "modules agents" --top 30)          # ~1-3 precise symbols

# ---- harvest + search/graph/log run MODEL-FREE, in PARALLEL (width 6) -------
# each seed -> one graph dive; the loop head never runs inside these.
printf '%s\n' "$seeds" \
  | xargs -d '\n' -I{} -P 6 \
      prg-graph.sh {} --root modules --out /tmp/dive.{}

# ---- R2: model READS the harvested trajectory, decides the next dives ------
# feed the merged edges/findings back to the loop head; it names the next
# span/seeds; loop.  This DRIVES the CKP-4b two-round methodology:
#   R1 keywords/span  ->  harvest (model-free)  ->  R2 connect  ->  model reads
#   ->  parallel dives  ->  merge  ->  repeat until complete.
next=$(cat /tmp/dive.*/edges.tsv | prg-llm.sh - \
         --system 'You are a code-dive planner. Given these edges, name the
                   next 1-3 symbols to expand, one per line, no prose.')

# ---- final synthesis: ONE opus call, not per-branch -------------------------
cat /tmp/dive.*/edges.tsv \
  | prg-llm.sh - --model claude-opus-4-8 \
      --system 'Synthesize these edges into a short grounded explanation.'
```

**Why the head must be fast and the tools must be model-free.** A full
`copilot -p` boot is **34.7 s / 22.4 credits** — it CANNOT be fanned out. The
local proxy at `http://host.docker.internal:11434` answers in **~1.5 s, zero
boot, zero credits, concurrency-safe at width 6** — that is the ONLY thing
that makes the parallel dive loop affordable. If a *tool* called a model, the
fan-out would multiply that cost; keeping tools model-free is what lets the
loop scale.

**Benchmarked, not asserted — `prg-bench.sh`.** The claim "the model tier
beats the tool baseline on precision, cheaply enough to fan out" is *measured*
by `prg-bench.sh` over `bench/gold.tsv` and regenerated into the table below.
The gold set pins direction → expected-seed pairs; a pass = emitted seeds
CONTAIN an expected symbol; precision = expected-hit seeds / emitted.

<!-- prg-bench:begin (regenerated; do not hand-edit — run prg-bench.sh --pretty) -->
```
# prg-bench.sh --models "claude-sonnet-4-5 claude-opus-4-8" --pretty
# account/date: GHE dki_research · 2026-08-11 · proxy host.docker.internal:11434 · 12 models
model              tier   n  recall  prec   p50ms  p95ms  fanK  fanWall  speedup
tool(--no-model)   tool   9  1.000   0.245  218    235    6     1156     1.72
claude-sonnet-4-5  model  9  1.000   0.579  1949   2506   6     5160     3.60
claude-opus-4-8    model  9  1.000   0.650  1657   2062   6     4982     7.81
```
<!-- prg-bench:end -->

Reading the table: both model tiers hold **recall 1.0** while **>2×-ing
precision** over the tool baseline (0.245 → 0.58–0.65) — the model rescues the
right seed from the noisy candidate list. Fan-out at width 6 gives a real
3.6–7.8× speedup, confirming the proxy is concurrency-safe (a `copilot -p`
reference at 34.7 s / 22.4 cr per call is on record above as the thing that
CANNOT be fanned out). `opus-4-8` is both more precise and, here, faster than
`sonnet-4-5`; `sonnet-4-5` is the cheap default inner-loop pick, `opus-4-8` is
reserved for the single final synthesis. **Cross-account note:** `--models` is
an explicit list, so switching GHE accounts drops that account's models in with
no code change — the header line records which account/date/model-set produced
these numbers; re-run `prg-bench.sh --pretty` after switching to refresh them.

### Recipe J — the silo scenario folder (spreadsheet: index → query → downstream)

The spreadsheet family is not a single verb but a **scenario folder**: one
recipe that groups an INDEX step, a QUERY step, and a DOWNSTREAM step, so the
front door can route "there's a workbook in this question" to the whole chain
instead of to a lone lens. Register it here for the same reason every recipe is
registered — an unlisted recipe is invisible to the loop head (the 8.2 registry
rule).

The three steps and where each one lives (the layout is deliberately FLAT under
`jq/` + `prg-silo.sh` — there is no `recipe/silo/` directory; 8.3 kept it flat
so the lens and its caller sit beside every other lens, and this row names the
real paths, not an aspirational folder):

| step       | component                     | answers                                   |
|------------|-------------------------------|-------------------------------------------|
| INDEX      | `prg-silo.sh` → `silo`        | build the cell+meta stream once (never re-parse the binary) |
| — lens     | `jq/silo-schema.jq`           | WHERE are the tables? (R1–R4 ladder; DECLARED-only rungs are trustworthy, shape rungs are 0.418 exact-ref — never quote the tautological 0.897) |
| QUERY      | `jq/select.jq`                | GROUP by row → WHERE over the row → PROJECT columns (SQL-style, SLURPED, shard by FILE) |
| DOWNSTREAM | `bench/` harnesses + sidecars | link two files (`bench/link-bench.sh`: {sheet\|header} Jaccard, FILE-level only), reconcile against a figure (`.prg.md` sidecar), triage which-file (Recipe I) |

The load-bearing discipline for this folder: **DECLARED, never inferred** — the
lens reports a table only where a `table`/`autofilter`/frozen-pane declaration
exists; shape inference is a SEPARATE concern kept out of the runtime verb so a
caller can never mistake a guess for a citation. Downstream link/agreement
claims are FILE-level (that is the granularity the corpus labels carry); do not
quote a file-level number as if it established a table-level link.

## The LSP tier — and its honest ceiling

`prg-graph.sh` can layer a semantic tier (jedi for Python, ts-morph/tsserver
for TS) ON TOP of the lexical `rg --json` chain. Its limits, so you don't
over-trust it:

- **Semantic only within OPENED files** — it does NOT index the whole tree.
  A ref in an unopened file is invisible to the semantic tier; the lexical
  tier still finds it (exit 3 → lexical fallback).
- **Capped by `--max-files`** — only the top-N lexical-hit files are opened.
  Widen for completeness, at latency cost.
- **Stateless spawn cost** — a fresh server per run, no warm index. Right for
  a bounded dive, wrong for a whole-repo sweep; use lexical for breadth.

## Guardrails

- **Exclude build/vendor dirs** (`-g '!**/node_modules/**' -g '!**/dist/**'
  -g '!**/.git/**'`) or you'll index generated code and blow up counts.
- **Cap `-j`** at `$(nproc)`; higher just thrashes on I/O-bound trees.
- **`--no-messages` + `2>/dev/null`** so a single unreadable shard doesn't
  kill the pipeline.
- **Deterministic output**: `parallel` interleaves; always `sort -u` (or
  `parallel -k` to keep input order) when order matters.
- **Don't parallelize a search that finishes in <1s serially** — process
  spawn overhead dominates (`kiss`).
- **Ordering vs speed**: default `parallel` returns as jobs finish; use
  `-k` (keep-order) only when a downstream consumer needs stable order.

## Output → durable index

Land the index somewhere a later reading pass can consume:

```bash
IDX=/tmp/<topic>-index; mkdir -p "$IDX"
# ... Recipe C writes $IDX/<category>.txt ...
wc -l "$IDX"/*.txt | sort -n     # category counts = first-glance map
```

If the index underpins a finding that must outlive the session, cite it
from the write-up in `.github/REPL/fix.archive/` (the index files
themselves stay in `/tmp` — they're regenerable).

## Symbol-chain graph — `prg-graph.sh` (tool-only, no LLM)

When you need to *follow* a symbol rather than just find it, use the
bundled grapher. It builds the graph with `rg --json` + `jq` + `awk`
only — **no language server, no ctags, no LLM**:

```
seed symbol ─► find def(s) ─► find refs ─► enclosing symbol at each ref
            ◄──────────────── enqueue (next depth) ◄──────────────────
```

```bash
.github/skills/prg/prg-graph.sh <symbol> \
    [--root "<dir> [<dir>...]"] [--depth 1] [--glob '*.ts'] \  # e.g. (this repo): --root "modules agents"
    [--out /tmp/prg-graph] [--max-per-symbol 40]
# outputs in $OUT:
#   edges.tsv  src \t dst \t path \t line \t kind(def|ref)
#   graph.dot  Graphviz digraph   (dot -Tsvg graph.dot -o graph.svg)
#   nodes.txt  discovered symbols
```

Read the result without a renderer:

:trap: **THE `awk` FORMS BELOW GET MANGLED BY THE SKILL LOADER.** This
file's own `fleet_ssh` sibling already records it (`fleet_ssh/SKILL.md`:
*"survives being rendered by a loader that eats `$` sigils"*) — and this
document did not apply the lesson to itself. MEASURED 2026-09-17: a user
pasted three seeds back from the RENDERED view of this section —
`ssupport`, `recipe?`, `ghcp==s` — none of which exist anywhere in the
repo. They are `$1`/`$2`/`$5` eaten and the neighbouring text spliced.
The file on disk is correct, so the damage is invisible from here and
lands on whoever copies from the rendered page.

So the `cut` forms are the ones to COPY; the `awk` forms are kept below
only because they are what the tool's output natively suits, and are
shown with the fields named rather than numbered.

```bash
# who uses SYM  -- $-free, copy this one:
grep -P '\tref$' "$OUT/edges.tsv" | cut -f1,2,3,4 | grep -P '\tSYM\t' | sort -u
# where SYM is defined:
grep -P '\tdef$' "$OUT/edges.tsv" | cut -f1,3,4 | grep '^SYM' | sort -u
```

The equivalent `awk` (fields: 1=src 2=dst 3=path 4=line 5=kind) — correct
on disk, but verify against this file before trusting a rendered copy:

```bash
awk -F'\t' -v s=SYM '$5=="ref" && $2==s {print $1"  ("$3":"$4")"}' $OUT/edges.tsv | sort -u
awk -F'\t' -v s=SYM '$5=="def" && $1==s {print $3":"$4}' $OUT/edges.tsv
```

### Ceiling (honest, by design — `kiss`)

This is a **lexical** graph (grep-grade), not a type-resolved call graph:

- It matches whole-word occurrences; import/re-export/comment lines are
  filtered, but it cannot tell a *call* from a same-named *field* or a
  shadowed local. Treat edges as "these sites mention SYM", strong enough
  to navigate, not authoritative for refactors.
- `--depth 1` is the default (seed → its direct callers). **Depth ≥ 2
  fans out fast** — a widely-used seed at depth 2 produces thousands of
  edges. Raise depth only for a narrow, rarely-referenced symbol.
- `--max-per-symbol` caps refs harvested per symbol so one hot symbol
  can't dominate.

> kiss ceiling: lexical symbol graph; upgrade to `tsserver`/a real parser
> only when an ambiguous edge actually misleads an investigation.

## Comprehensive report — MD + graph (orchestration recipe, not a helper)

When a search warrants a written summary, render the structured hits
(Recipe D) plus a symbol graph into Markdown with an embedded diagram.
**This lives in the orchestration HEAD, not in a `prg-*.sh` helper** — no prg
helper shells out to a model. Inputs are the tools' stable JSON:

```bash
# 1. structured hits (queryable middle-collection)
rg --json 'PATTERN' <root> | jq -n -c -f …/jq/search-hit.jq > /tmp/hits.jsonl
# 2. symbol graph for the seed(s) that matter
.github/skills/prg/prg-graph.sh SYM --out /tmp/g   # -> /tmp/g/edges.tsv
```

Then the orchestrator writes the report deterministically from those files:

- **Group hits by path** — `jq -s 'group_by(.path)'` over `hits.jsonl` →
  one `### <path>` section per file, each line a `` `L<line>` `` + content.
- **Diagram from edges** — turn `edges.tsv` into a mermaid `graph LR`
  (`src --> dst` per `ref` row), embedded in a ```` ```mermaid ```` fence
  (GitHub renders it inline; no Graphviz needed).
- **Narrative** — the LLM summarizes the picture (what the hits show, how
  the symbols connect). This is the ONLY model-touched part; do it in a
  `task` subagent when the hit set is large so it stays out of the main
  context.

Land the report in `.github/REPL/fix.archive/<topic>.md` if it must outlive
the session (per the dev process); the `/tmp/*.jsonl` inputs stay
regenerable and are not committed.

## Evidence citation (lightweight, subagent) — cite the atom, don't re-quote

This is the loop's back door, symmetric to its front door
("## Parse the utterance first — SOURCE / TERM / TASK") and to the spine
between them ("## Trajectory = the workflow spine"): where the parse step
turned an utterance into SOURCE+TERM+TASK and the trajectory strung those
slots into a connected sequence of turns, this step turns the tool's JSON
back into a cited answer — every claim traces to the TASK it came from (or
to a specific turn's slot on the spine) and ends in an atom the SOURCE
emitted.

Good evidence answers **separate the claims**, commit to a **reproducible
statistic**, and back **every fact with a concrete artifact** — `path:line`,
`<sha7>`, a measured number, a corpus id/field — never an assertion from
memory. prg ALREADY emits those atoms, so citation is a **formatting recipe
on top of the JSON**, not new capture and NOT a re-run of the tool.

**The citation contract — one bullet per claim, each ending in a bracketed
provenance tag drawn from the tool output the claim came from:**

| claim kind        | tag form                       | atom source                       |
|-------------------|--------------------------------|-----------------------------------|
| repo fact         | `` [`path:line`] ``            | search-hit `{path,line}` / graph edge |
| log / corpus stat | `` [`model×N over SPAN`] `` or `` [`id`] `` | prg-log `{id,ts,model,path}` |
| trajectory fact   | `` [`traceId`] `` / `` [`file`] `` / `` [`ts`] `` | trace `refs`         |
| git fact          | `` [`<sha7>`] ``               | read_pr / read_patch              |

Rules: **no claim without a tag**; a *count* cites its **SPAN + anchored
token** (the corpus-anchor rule above — a fuzzy token inflates the stat).
Compact = a bullet list under a `## Evidence` heading — NOT a table, NOT
the re-quoted matched content, just claim + tag.

```markdown
## Evidence
- office-shim's real impl is `officeai-shim`, 763 LOC. [`modules/excel-headless/src/sandbox/officeai-shim-source.ts:1`]
- opus-4-8 drove 1382 requests in the window. [`claude-opus-4-8×1382 over 2026-08-10T18:13..2026-08-11T17:36`]
- the flight gate defaults false. [`83e9de2b5f1`]
```

**Delegate to a citation SUBAGENT only after a BIG dive.** When the
hit/trace JSONL is large, spawn a `task` subagent (`explore` or
`general-purpose`) with the JSONL path(s) + your draft claims; it returns
**ONLY the `## Evidence` block**, keeping raw JSONL out of the main context.
Small dive → format inline (`kiss`). The subagent FORMATS from stable
output; it does NOT re-run a tool and does NOT verify claims by
re-execution (deliberately out of scope — cite the artifact).

Subagent prompt shape:

```text
Read these prg tool outputs (stable JSON, do NOT re-run any tool):
  /tmp/hits.jsonl   (search-hit: {path,line,col,keyword,content,index})
  /tmp/traj.json    (trajectory: turns[].refs, keywords[].refs)
Given these draft claims: <claims>, emit ONLY a `## Evidence` markdown
block — one bullet per claim, each ending in a [`provenance tag`] taken
from the JSON (path:line / id / traceId / sha7). No prose, no re-quoted
content, no tool calls.
```

## One-glance template

```bash
JOBS="$(nproc)"; touch ~/.parallel/will-cite
ROOT="<dir> [<dir>...]"; PAT="OpenTelemetry|OTLP|traceparent"  # ROOT e.g. (this repo): "modules agents"
find $ROOT -maxdepth 1 -mindepth 1 -type d -print0 \
  | parallel -0 -j"$JOBS" "rg -l --no-messages '$PAT' {} 2>/dev/null" \
  | sort -u
```
