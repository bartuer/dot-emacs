# prg — production-grade code/doc/log/trajectory intelligence

`prg` is a **model-free** toolkit for searching and connecting the evidence
scattered across a workspace: source code, docs, LLM request/response logs,
and telemetry trajectories. An LLM orchestrates *above* the tools — it parses
the human's intent, constructs keywords, fans out parallel dives, and cites
the atoms it found. Every tool underneath is deterministic and fast
(`find | parallel | rg → jq → LSP → stable JSON`). Only one script,
`prg-llm.sh`, ever calls a model, and only at the loop head.

For the full operating manual (recipes, schemas, the orchestration loop),
read [SKILL.md](./SKILL.md). This README is the map: **which data source you
have → which tool mines it**.

---

## Data source → task tool

The first move on any request is to parse the utterance into three slots —
**SOURCE** (which corpus), **TERM** (the seed), **TASK** (the operation). The
SOURCE picks the tool from this matrix:

| Data-source type | What it is | Task tool | Verbs / subverbs | Corpus selector |
|------------------|------------|-----------|------------------|-----------------|
| **Source repo (lexical)** | the code/doc tree | `prg-seed.sh` | direction → ranked seed symbols | `--root` / `PRG_REPO_ROOT` (default `git rev-parse --show-toplevel`) |
| **Source repo (semantic graph)** | symbols + their defs/refs | `prg-graph.sh` | `<symbol>` → def→ref→enclosing chain (DOT + `edges.tsv`) | `--root`; LSP via `prg-lsp.py` |
| **Huge / sharded tree** | many big subtrees, multi-pattern | `find \| parallel \| rg` recipes | Recipe A (shard by dir), B (per-file extract), C (one job per pattern) | any path arg |
| **LLM request/response logs** | L-server capture pairs `<ts>_<id>.json` + `.response.json` | `prg-log.sh` | `count-by-model`, `pair <id>`, `tool-calls`, `grep <jq>`, `latest [N]` | `--corpus` / `PRG_LOG_CORPUS` |
| **Telemetry trajectory** | OTel + agent-log + lifecycle JSONL lenses, over a time span | `prg-trace.sh` | `harvest` (R1 keywords), `connect` (R2 one trajectory object) | `--corpus` / `PRG_TRACE_CORPUS` (default `/agent/logs`) |
| **Crash / exception stream** | `officeagent.log` uncaughtException classes | `prg-crashwatch.sh` | `scan`, `count`, `watch`, `gate` | `--log` / `PRG_CRASH_LOG` |
| **Scanned document corpus (structure)** | `*.prg.jsonl` cell sidecars from a bin2md scan | `prg-join.sh` | `schema`, `join`, `peek` — tables, header rows, join candidates | a folder of `*.prg.jsonl` |
| **Scanned document corpus (SQL)** | the same corpus loaded into SQLite | the `sql` skill (`skills/sql/`) | preflight → one-shot SQL generation | a `.db` built from `insert.prg.sql` |
| **Query result → workbook cell** | a db row's originating `(file, sheet, A1)` | `prg-addr.sh` | `rows`, `cell`, `check` — the WRITE-BACK path | a folder of `*.prg.jsonl` + the `.db` |
| **Time expression** | "last hour", "yesterday", a git ref | `prg-when.sh` | human/relative/git-ref → ISO-8601 Z | shared normalizer for every time-scoped source |
| **Git history** | commits that add/remove a symbol | `git log -S` (via `read_pr` / `read_patch`) | pickaxe over a pathspec | the repo |
| **The model (loop head only)** | keyword/span/dive choice | `prg-llm.sh` | one completion via the local proxy | `PRG_LLM_URL` (default `host.docker.internal:11434`) |

**Reading the matrix:** the *same* TERM routed through a *different* SOURCE
word is a different tool — "who calls `X`" → `prg-graph.sh`; "when did `X`
change" → `prg-trace.sh` / git; "`X` by model in the logs" → `prg-log.sh`; a
bare `X` → repo search. Parsing SOURCE is what disambiguates them.

**Crash-triage is a chain of three sources:** paste a stack trace →
`prg-crashwatch.sh` / `jq` the frame's SYMBOL → `prg-graph.sh` that symbol in
the source → the fix site. Log source → repo source → graph source, in one
line. See SKILL.md "Recipe F".

---

## Architecture

### The split of responsibility

```
                 ┌──────────────────────────────────────────────┐
   utterance ──▶ │  MODEL (prg-llm.sh, loop head ONLY)           │
                 │  parse SOURCE/TERM/TASK · pick keywords/span ·│
                 │  plan the next dives · bound the fan-out      │
                 └───────────────────┬──────────────────────────┘
                                     │ keywords, spans, seeds
                    ┌────────────────┼────────────────┬─────────────────┐
                    ▼                ▼                ▼                 ▼
              prg-seed.sh      prg-graph.sh      prg-log.sh        prg-trace.sh   …
              (rg rank)        (LSP + rg)        (jq + parallel)   (jq + parallel)
                    │                │                │                 │
                    └────────────────┴───────┬────────┴─────────────────┘
                                             ▼
                              STABLE JSON / TSV (agent-first)
                                             │
   findings ◀── MODEL reads, plans next dives, fans out ──┘   (repeat)
                                             │
                                    ## Evidence citation
```

- **TOOLS are 100% model-free.** Deterministic, parallel, stable schemas.
  The heavy lifting lives in compiled binaries — `rg` (search),
  `jq` (JSON aggregation), GNU `parallel` / `xargs -P` (fan-out),
  `typescript-language-server` / `jedi-language-server` (semantic graph),
  `dot` (graphviz). Each wrapper is a thin 95–335-line shell/py glue over
  one of those binaries; the win is the binary, and the wrapper's only job is
  to feed it correctly (batch, don't fork-per-record — see
  `fix.archive/41.prg-thin-wrapper-perf-audit.md`).
- **The MODEL sits only at the loop head.** `prg-llm.sh` hits an
  OpenAI-compatible proxy that answers in ~1.5 s with zero boot and zero
  credits, so a parallel fan-out of dives stays cheap. (A full `copilot -p`
  boot is 34.7 s / 22.4 credits and *cannot* be fanned out — which is why the
  loop head is a proxy call, not an agent.)

### The three-slot spine (parse → trace → cite)

The same decomposition works at two scales:

```
one utterance          →   {SOURCE, TERM, TASK}                 (parse: the front door)
a workflow of N turns  →   [ {SOURCE,TERM,TASK}_0 … _N ]         (trace: the spine)
                            connected by tool-derived edges
each claim             →   cite a turn's slot atom               (## Evidence: back door)
```

`prg-trace.sh connect` puts `slots:{source,term,task}` on every turn and links
them by shared refs (traceId / changed file / shared symbol / turn ordinal),
so a whole workflow is a walkable trajectory — the carrier of the user's
mental model, not a debug afterthought.

### Degrade-safely contract

Every helper returns a documented non-zero exit rather than a stack trace:

| exit | meaning |
|------|---------|
| `0` | ok |
| `2` | bad args / missing dependency |
| `3` | model proxy unreachable (`prg-llm.sh`) → caller falls back to the `--no-model` tool-only path |
| `3` | no such cell (`prg-addr.sh cell`) → a missing address is an ERROR, never a silent skip |
| `4` | corpus absent (`prg-log.sh`, trace) |

### Portability

Zero hardcoded OfficeAgent coupling: repo root from `--root` / `PRG_REPO_ROOT`
(default `git rev-parse --show-toplevel`), log/trace corpora from
`PRG_LOG_CORPUS` / `PRG_TRACE_CORPUS`, model URL from `PRG_LLM_URL`, temp paths
from `mktemp`. Drop the dir into a bare repo and every verb's `--help` + a
smoke search works with no edits.

---

## Quick start

```bash
P=.github/skills/prg

# repo tools resolve roots relative to CWD — run them from the repo root
# (or pass --root / set PRG_REPO_ROOT):
$P/prg-seed.sh --no-model "trace propagation across a process boundary"
$P/prg-graph.sh getActiveTraceparent          # def→ref chain, DOT + edges.tsv

# corpus tools take an explicit --corpus, so they run from anywhere:
$P/prg-log.sh count-by-model --corpus /workspace/L-server --pretty
$P/prg-log.sh pair <8-hex-id> --corpus /workspace/L-server

# trajectory: two-round time-bounded dive (--span sides accept human time)
$P/prg-trace.sh harvest --corpus /agent/logs --span "1 hour ago"..now
$P/prg-trace.sh connect --corpus /agent/logs --span "1 hour ago"..now

# health: regression harness (model-free), record a baseline then gate on it
$P/prg-regress.sh record
$P/prg-regress.sh check         # green = no perf/completeness/correctness regression
```

## Files

| File                | Role                                                        |
|---------------------|-------------------------------------------------------------|
| `SKILL.md`          | the operating manual (recipes, schemas, orchestration loop) |
| `prg-seed.sh`       | direction → ranked seed symbols (repo, rg)                  |
| `prg-graph.sh`      | symbol → def/ref/enclosing chain (LSP, lexical fallback)    |
| `prg-lsp.py`        | LSP driver (typescript / jedi language servers)             |
| `prg-log.sh`        | L-server LLM-log miner (jq + parallel)                      |
| `prg-trace.sh`      | two-round telemetry trajectory research (jq + parallel)     |
| `prg-when.sh`       | the one time normalizer (human/relative/git-ref → ISO Z)    |
| `prg-crashwatch.sh` | api-server crash-class watcher over `officeagent.log`       |
| `prg-llm.sh`        | the ONLY model call — the loop head (local proxy)           |
| `prg-bench.sh`      | seed-quality + latency benchmark for the loop head          |
| `prg-regress.sh`    | model-free regression harness (record / check)              |
| `prg-pairwise.py`   | paired McNemar significance test of two ssg runs (same cases)|
| `prg-seed-cases.sh` | mine the regression gold set from the real corpus           |
| `bench/`            | gold fixtures, jq lens library, regression baseline         |
