# prg benchmark — `bench/`

The model-free regression benchmark for the `prg` toolchain. There is no model
in the tools, so quality is a property of the *scripts*; regressions are silent
unless a benchmark asserts a KNOWN answer on a REAL corpus. This folder holds
that benchmark's fixtures and recorded result.

## What's here

| file                       | role                                                                                                                                                     |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| **`regress.baseline.tsv`** | **THE benchmark result** — the recorded golden the harness gates against. One row per case: `name  ok  wall_ms  count`.                                  |
| **`gold-search.tsv`**      | **Accuracy anchor** — mined `class  pattern  flags  root` (4 cols, no count: cases are recounted live and gated vs the baseline); a COMPUTED, re-minable fixture (example-only header). Feeds the `search_*` cases. |
| **`jq/*.jq`**              | The versioned **output-contract lenses**  The bench asserts these against a real corpus.                                                                 |
| **`trajectory.schema.json`** | Frozen draft-07 schema for `prg-trace.sh connect`'s Round-2 object; the connect step validates its output against it.                                  |

### Trajectory / time-sensitive coverage (CKP-4b)

Beyond code/doc `search` and the two L-server jq rows, the gold set now
gates **time-sensitive trajectory** search so a regression in the
telemetry lenses is CAUGHT:

| gold class            | corpus tag     | lens / probe               | asserts                                  |
|-----------------------|----------------|----------------------------|------------------------------------------|
| `jq:trace-otel`       | `agent-logs`   | `trace-otel.jq`            | a stable OTEL span-name count            |
| `jq:trace-agentlog`   | `agent-logs`   | `trace-agentlog.jq`        | a stable agent.log event count           |
| `jq:trace-lifecycle`  | `agent-logs`   | `trace-lifecycle.jq`       | a stable lifecycle-event count           |
| `jq:session-tool-when`| `session-state`| `session-tool-when.jq`     | events.jsonl tool count via a TIME-aware lens (`{tool,day}`) |
| `git:log-s`           | `repo`         | `git log -S <sym> -- spec` | commits that add/remove a symbol (pickaxe) |

`agent-logs` resolves to `$PRG_TRACE_CORPUS` (default `/agent/logs`) and
finds `*.jsonl`; the trajectory lenses take a wide-open `--arg FROM/TO`
span in the bench.  `git:log-s` attributes changed symbols through git
history (runtime symbol/diff attribution stays with `read_pr`/`read_patch`,
NOT reinvented here).  All rows SKIP symmetrically when their corpus is
absent, so a bare checkout never false-regresses.

The harness itself is one level up: `../prg-regress.sh` (runner) and
`../prg-seed-cases.sh` (the gold miner that regenerates `gold-search.tsv`).

## `regress.baseline.tsv` columns

    name        the case id (case_graph_ts, case_lsp_precision, case_tput_*,
                case_search_json, search_<class>_<NN>, …)
    ok          1 = the case ran and its correctness invariant held; 0 = failed
    wall_ms     wall-clock milliseconds for that case
    count       what the case produced (edges / rows / refs / matched lines /
                records-per-sec for tput cases)

## Run it

```bash
cd .github/skills/prg
export PRG_LOG_CORPUS=/workspace/L-server   # REQUIRED: else the log/tput/gold
                                            # rows that touch it SKIP out
touch ~/.parallel/will-cite                 # silence GNU parallel citation
./prg-regress.sh record    # (re)write bench/regress.baseline.tsv
./prg-regress.sh check     # re-run now, gate vs baseline
```

`check` exit codes: **0** all-green, **1** a regression fired, **2** bad args /
no baseline, **4** corpus absent. A one-line VERDICT goes to stderr; stable TSV
to stdout.

## Pass/fail gate (what `check` enforces, per case vs its baseline row)

- **correctness** — FAIL if `ok` flips `1 → 0`.
- **completeness** — FAIL if `count` drops below `baseline * (1 - TOL)`
  (`PRG_REGRESS_TOL`, default 0.15). It is a **FLOOR**: monotone growth of a
  live corpus never trips it; a DISAPPEARING row can.
- **perf** — FAIL if `wall_ms` exceeds `baseline * (1 + SLOW)`
  (`PRG_REGRESS_SLOW`, default 1.0 = up to 2× baseline).

**SKIP is symmetric.** A corpus/seed-dependent case that can't find its input
emits `SKIP` and is omitted from BOTH record and check, so a drop-in repo with
no `PRG_LOG_CORPUS` never false-regresses.

## Reproducibility (read before you hand-edit anything)

**Do NOT hand-edit these files — RE-MINE / RE-RECORD instead.** The corpus is
live-growing: only pure-`rg`-over-static-dir rows are byte-identical across
mines; anything touching the L-server / session-state corpora drifts UP
monotonically (the floor gate tolerates that). A row DISAPPEARING is the red
flag — the usual cause is a missing `PRG_LOG_CORPUS` export at record/mine time.

- regenerate the gold set: `PRG_LOG_CORPUS=… ../prg-seed-cases.sh`
- re-record the baseline: `PRG_LOG_CORPUS=… ../prg-regress.sh record`

## Hero scenarios — the canonical end-to-end demos

Beyond the model-free tool cases above, NAMED hero cases exercise the
full orchestration pattern (utterance → search verb → LLM operation →
durable artifact) across BOTH knowledge domains. Re-run them to demo prg
= model-free upstream + LLM downstream. (Plan 41 CKP-5d / CKP-5h.)

| hero | domain     | utterance                                                        | artifact                                              |
|------|------------|------------------------------------------------------------------|-------------------------------------------------------|
| 1    | repo src   | "dig into office-shim and summarize into a doc — what's the scale?" | `.github/REPL/fix.archive/office-shim.md`             |
| 2    | L-server   | "count L-server reqs per model — tools called + tool definitions"  | `.github/REPL/fix.archive/lserver-model-stat.md`      |
| 3    | log→source | "this exception `<paste>` — find it & what's the fix?"            | gated case `case_crash_triage` (SKILL.md Recipe F)    |

- **Hero 1** shows the typo ladder (`office_shim` → real `officeai-shim`)
  + Recipe C fan-out + grapher + scale metrics (763-LOC shim source, gate,
  call-sites) → written tech report.
- **Hero 2** shows the response→request JOIN (`.model` +
  `.output.toolInvocations` joined via `.promptFile` → `.tools`) →
  per-model {reqs, tool_calls, req_w/tools, tooldefs} + top tools. Uses
  the ANCHOR rule (exact identifiers, no fuzz) for the corpus count.
- **Hero 3** chains THREE verbs across TWO domains: jq the exception frame
  from the LOG → map the frame's METHOD (not the dist line) to a SYMBOL →
  `prg-graph.sh` that symbol in SOURCE. Unlike heroes 1–2 it is **gated
  mechanically** by `case_crash_triage`: a pinned exception record is
  replayed through the whole chain, and the case REDs unless jq extracts
  the method AND the def resolves to a `.ts` SOURCE file (never `.js`/dist).
  The load-bearing invariant — *a dist `file:LINE` is a build artifact, not
  a source line; pivot on the symbol* — and the stale-dist-vs-source-bug
  diagnosis are documented in SKILL.md Recipe F.

## More

- **Coverage / axes / RE-MINE mechanics** → `.github/REPL/fix.archive/prg-bench-coverage.md`
- **Architecture & methodology** → `.github/REPL/fix.archive/prg-intelligence.md`
- **Operating manual (all verbs/recipes)** → `../SKILL.md`
