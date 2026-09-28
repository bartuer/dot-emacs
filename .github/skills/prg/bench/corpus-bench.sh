#!/usr/bin/env bash
# corpus-bench.sh — FEATURE + PERF + JAIL bench for prg-corpus.sh.
#
# The bench for prg-corpus.sh, the fourth prg SOURCE (plan 256).  Per prg
# tool-authoring rule 3 it carries a NAIVE BASELINE arm -- plain `rg`, no
# index, no post-processing -- because a tool never compared to bare rg
# cannot prove it should exist.  Three sections, all required:
#
#   FEATURE  every subverb answers, on the shape it promises
#   PERF     wall-clock vs the naive baseline, both directions reported
#   JAIL     no answer key leaks, and a gold-stripped tool fails LOUDLY
#
# THE CLAIM UNDER TEST CHANGED WHEN THE LAYOUT DID, and the old bench is
# worth keeping as a cautionary tale.  It scored ATTRIBUTION: md/ used to be
# a FLAT dir of collision-mangled names, so a plain rg hit named a file whose
# CASE was unrecoverable, and the tool's value was rejoining hits to
# index.jsonl .out.  Sidecars now live BESIDE their source, i.e. inside the
# case folder, so the hit path already carries the case id and plain rg
# attributes just as well.  That join was DELETED, not optimised.  A bench
# still scoring attribution would now report 1.000 for BOTH arms and call it
# a win -- a green table measuring something no longer at stake.
#
# What prg-corpus.sh still does that plain rg does NOT:
#   1. PRECISION.  Line 1 of every artifact is bin2md provenance JSON that
#      RESTATES the source path, so bare rg reports it as a hit -- one
#      duplicate per document.  The tool drops it by WITNESS (line 1 parses
#      as bin2md provenance), never by line number, so a corpus-own .md that
#      matches on its own first line survives.
#   2. STRUCTURE.  {case,path,line,content} JSON per hit vs rg's text, and
#      case-level rollups no file-level grep can express.
# So the metric is PRECISION, and the baseline is expected to be FASTER and
# noisier.  Both halves of that trade get reported.
#
# TRAP (cost a wrong reading once): never pipe the tool under test through
# `head` to read its exit status -- `$?` becomes head's and a real failure
# reads as success.  Redirect to a file, THEN inspect.
#
# TRAP 2 (this bench's own history): it hard-required $CORPUS/md and died
# exit 4 the day that dir was retired.  A bench pinned to a layout stops
# running exactly when the layout moves -- i.e. when you most need it.  It
# now derives its search root the same way the tool does.
#
# Env:   PRG_DOC_CORPUS (default /workspace/crawler/microcosmo-index)
# Usage: bash bench/corpus-bench.sh [--pretty] [--corpus DIR] [--no-jail]
# Exit:  0 ok · 1 feature/perf failed · 2 bad deps · 3 JAIL LEAK
#        4 corpus absent · 5 degenerate sample (0 hits, or stale index)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$HERE")"
SKILLS_ROOT="$(dirname "$SKILL_DIR")"
SERVER="$SKILLS_ROOT/ssg-sim/server.py"
TOOL="$SKILL_DIR/prg-corpus.sh"
CORPUS="${PRG_DOC_CORPUS:-/workspace/crawler/microcosmo-index}"
PRETTY=0; DO_JAIL=1

while [ $# -gt 0 ]; do
  case "$1" in
    --pretty)  PRETTY=1; shift ;;
    --no-jail) DO_JAIL=0; shift ;;
    --corpus)  CORPUS="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "corpus-bench: unknown arg $1" >&2; exit 2 ;;
  esac
done

for b in rg jq; do command -v $b >/dev/null || { echo "corpus-bench: need $b" >&2; exit 2; }; done
[ -f "$TOOL" ] || { echo "corpus-bench: tool not found: $TOOL" >&2; exit 2; }
[ -d "$CORPUS" ] || { echo "corpus-bench: corpus absent: $CORPUS" >&2; exit 4; }

# Resolve the search root EXACTLY as the tool does, so the bench cannot drift
# from the thing it measures.
SUM="$CORPUS/summary.json"; IDX="$CORPUS/index.jsonl"
DOCROOT="$CORPUS"
[ ! -f "$SUM" ] || DOCROOT="$(jq -r --arg d "$CORPUS" '.corpus // $d' "$SUM" 2>/dev/null || echo "$CORPUS")"
[ -d "$DOCROOT" ] || { echo "corpus-bench: search root absent: $DOCROOT" >&2; exit 4; }

# A STALE INDEX MUST NOT BENCH GREEN.  Manifests outlive their artifacts
# whenever a re-index or cleanup removes the .md but leaves index.jsonl --
# every arm then returns 0 hits, which reads as a clean sheet.  Require that
# the artifacts the index promises actually exist.  (This fired for real:
# index.jsonl listed 2730 artifacts while the tree held none.)
if [ -f "$IDX" ]; then
  OUTS=$(jq -r 'select(.ok==true and (.out//empty)!="")|.out' "$IDX" 2>/dev/null | head -200 || true)
  SAMPLE=$(printf '%s' "$OUTS" | { grep -c . || true; } | tr -d ' ')
  PRESENT=0
  while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && PRESENT=$((PRESENT+1)); done <<< "$OUTS"
  if [ "${SAMPLE:-0}" -gt 0 ] && [ "$PRESENT" -eq 0 ]; then
    echo "corpus-bench: STALE INDEX — 0 of ${SAMPLE} sampled artifacts exist under ${DOCROOT}." >&2
    echo "corpus-bench: re-run index_folder.sh; refusing to report green on absent data." >&2
    exit 5
  fi
fi

now_ms() { date +%s%3N; }
run_tool() { timeout 300 bash "$TOOL" --corpus "$CORPUS" "$@" 2>/dev/null || true; }

# Fixed pattern set: domain terms that actually occur in cross-app office
# docs.  Fixed rather than sampled so runs are comparable across commits -- a
# resampled set would make every diff look like a regression.  One pattern is
# deliberately near-zero-hit to keep the empty path exercised.
PATTERNS=(revenue forecast PivotTable macro consolidat variance)

# The PRECISION probe: a token appearing ONLY in bin2md provenance lines,
# never in extracted prose.  RAW must find it ~once per document; the TOOL
# must find it zero times.  This is the only arm that fails if the provenance
# filter regresses, so a vacuous probe (RAW==0) is reported as UNTESTED
# rather than passed.
PROV_PAT='extractor_version'

# ============================ PERF + PRECISION ==============================
rows=""; TOTAL_NOCASE=0; TOTAL_TOOL_HITS=0; RAW_MS=0; TOOL_MS=0
TOOL_CASES_TOTAL=0; HITS_REGRESSION=0

for p in "${PATTERNS[@]}"; do
  # `|| true` INSIDE the pipeline, not after it: `set -o pipefail` makes the
  # pipeline inherit rg's exit 1 on ZERO MATCHES, so an absent pattern would
  # abort the bench under `set -e`.  A zero-hit pattern is data, not an error.
  t0=$(now_ms)
  raw_hits=$({ rg -c --no-filename -g '*.md' -- "$p" "$DOCROOT" 2>/dev/null || true; } \
             | awk '{s+=$1} END{print s+0}')
  t1=$(now_ms); raw_ms=$((t1-t0))

  t0=$(now_ms); out="$(run_tool search "$p")"; t1=$(now_ms); tool_ms=$((t1-t0))

  # grep -c exits 1 on zero lines and jq exits nonzero on empty input, so
  # every stage is guarded and normalised to an integer.
  tool_hits=$({ printf '%s' "$out" | grep -c . || true; } | tr -d ' ')
  tool_cases=$({ printf '%s' "$out" | jq -r 'select(.case!="«nocase»")|.case' 2>/dev/null || true; } \
                | sort -u | { grep -c . || true; } | tr -d ' ')
  nocase=$({ printf '%s' "$out" | jq -r 'select(.case=="«nocase»")|.case' 2>/dev/null || true; } \
                | { grep -c . || true; } | tr -d ' ')
  tool_hits=${tool_hits:-0}; tool_cases=${tool_cases:-0}; nocase=${nocase:-0}

  # The tool only ever REMOVES noise, so it can never out-hit the baseline.
  # More tool hits than raw hits means double-counting.
  [ "$tool_hits" -le "$raw_hits" ] || HITS_REGRESSION=$((HITS_REGRESSION+1))

  RAW_MS=$((RAW_MS+raw_ms)); TOOL_MS=$((TOOL_MS+tool_ms))
  TOTAL_NOCASE=$((TOTAL_NOCASE+nocase)); TOTAL_TOOL_HITS=$((TOTAL_TOOL_HITS+tool_hits))
  TOOL_CASES_TOTAL=$((TOOL_CASES_TOTAL+tool_cases))
  rows+=$(printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$raw_ms" "$raw_hits" "$tool_ms" "$tool_hits" "$tool_cases")$'\n'
done

prov_raw=$({ rg -c --no-filename -g '*.md' -- "$PROV_PAT" "$DOCROOT" 2>/dev/null || true; } \
           | awk '{s+=$1} END{print s+0}')
prov_out="$(run_tool search "$PROV_PAT")"
prov_tool=$({ printf '%s' "$prov_out" | grep -c . || true; } | tr -d ' '); prov_tool=${prov_tool:-0}

# A run that found nothing is a broken harness reporting a clean sheet.
[ "$TOTAL_TOOL_HITS" -gt 0 ] || {
  echo "corpus-bench: degenerate sample (0 hits) — harness broken, not a pass" >&2; exit 5; }
ATTR=$(awk -v n="$TOTAL_NOCASE" -v h="$TOTAL_TOOL_HITS" 'BEGIN{printf "%.3f", (h-n)/h}')

# ================================ FEATURE ===================================
# Every subverb, not just `search`.  A perf bench over one verb lets the other
# five rot: they share the manifest-validation and case-join paths, so a
# schema change breaks them silently while `search` stays green.
# Each row asserts the SHAPE promised in the tool's own header, not merely
# exit 0 -- a subverb that exits 0 with empty output is the void pass this
# bench exists to catch.
frows=""; FEAT_FAIL=0
feature() {                      # name · needs-rows · cmd...
  local name="$1" need="$2"; shift 2
  local o n verdict
  o="$(run_tool "$@")"
  n=$({ printf '%s' "$o" | grep -c . || true; } | tr -d ' '); n=${n:-0}
  verdict=OK
  if [ "$need" = 1 ] && [ "$n" -eq 0 ]; then verdict=EMPTY; FEAT_FAIL=$((FEAT_FAIL+1)); fi
  # Every JSON-emitting subverb must emit PARSEABLE json; a partial jq stream
  # is the plan-256 G2b.1 defect (partial counts reported as complete).
  if [ "$n" -gt 0 ] && ! printf '%s' "$o" | jq -e . >/dev/null 2>&1; then
    verdict=BADJSON; FEAT_FAIL=$((FEAT_FAIL+1))
  fi
  frows+=$(printf '%s\t%s\t%s\n' "$name" "$n" "$verdict")$'\n'
  printf '%s' "$o"
}

feature "search"      1 search 'revenue'                                  >/dev/null
feature "stat/kind"   1 stat --by kind                                    >/dev/null
feature "stat/case"   1 stat --by case                                    >/dev/null
feature "docs"        1 docs 'select(.ok==true)'                          >/dev/null
feature "sheets"      1 sheets 'select((.formulas//0)>0)'                 >/dev/null
# `failed` is legitimately empty on a clean corpus, so it may not assert rows.
feature "failed"      0 failed                                            >/dev/null
# `case` needs a real id; take one the tool itself just reported, so the
# bench cannot go stale against the corpus.
CASE_ID=$(run_tool stat --by case | jq -r '.key? // .case? // empty' 2>/dev/null | head -1 || true)
if [ -n "${CASE_ID:-}" ]; then
  feature "case"      1 case "$CASE_ID"                                   >/dev/null
else
  frows+=$(printf '%s\t%s\t%s\n' "case" 0 "SKIP-noid")$'\n'
fi

# ================================= JAIL =====================================
# ssg-sim grades a skill by copying skills/<name>/ through server.py's
# _jail_ignore, which strips `bench/` wholesale so the child model never sees
# the answer key.  Two invariants pull in OPPOSITE directions:
#   A. NO LEAK -- no gold/baseline/expected file reaches the jail.
#   B. NO VOID -- a tool whose gold was stripped must fail LOUDLY (nonzero),
#      never print a shrug and exit 0.  A green exit on a missing answer key
#      is a void measurement reported as a pass -- worse than a crash.
# Importing the REAL _jail_ignore is the point; a reimplementation here would
# drift from what actually runs and prove nothing.
JAIL_N=0; JAIL_RC=""; JAIL_VERDICT=SKIP; LEAK_N=0; LEAKS=""; CORPUS_LEAK_N=0
if [ "$DO_JAIL" = 1 ] && command -v python3 >/dev/null && [ -f "$SERVER" ]; then
  JR="$(mktemp -d /tmp/prg-corpus-jail-XXXXXX)"; trap 'rm -rf "$JR"' EXIT
  if python3 - "$SERVER" "$SKILL_DIR" "$JR/prg" <<'PY' 2>/dev/null
import importlib.util, shutil, sys
spec = importlib.util.spec_from_file_location("ssgsrv", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
shutil.copytree(sys.argv[2], sys.argv[3], ignore=m._jail_ignore)
PY
  then
    JAIL_N=$(find "$JR/prg" -type f | wc -l | tr -d ' ')
    # Match the SHAPE of an answer key, not a name list -- the same discipline
    # ssg-sim learned when a per-recipe .golden.json slipped past exact names.
    LEAKS="$(find "$JR/prg" -type f \
              \( -iname '*gold*' -o -iname '*baseline*' -o -iname '*expected*' \
                 -o -iname '*answer*' -o -iname 'queries.jsonl' \) | sort || true)"
    LEAK_N=$(printf '%s' "$LEAKS" | { grep -c . || true; } | tr -d ' ')

    # 2026-08-25: the lens dir MOVED from bench/jq/ to jq/ (a sibling of
    # bench/).  It was never test data -- 10 of the 16 lenses are runtime
    # dependencies of shipping prg-*.sh tools, so filing them under bench/
    # misdescribed them AND made them collateral damage of the jail, which
    # strips bench/ wholesale.  Before the move the jailed tool could not
    # run at all (exit 2, "jq: Could not open .../bench/jq/search-hit.jq").
    # Now jq/ survives the jail and the tool actually RUNS there.
    # VERIFIED at move time: the jail still strips bench/ (gold/baseline
    # files) and the leak grep still reports 0 -- the move restored
    # function WITHOUT weakening the answer-key barrier.
    set +e
    ( cd "$JR/prg" && timeout 120 bash prg-corpus.sh --corpus "$CORPUS" search revenue ) \
      >/tmp/cb-jail.out 2>/tmp/cb-jail.err
    JAIL_RC=$?
    set -e
    jail_lines=$({ grep -c . </tmp/cb-jail.out || true; } | tr -d ' ')
    if [ "$JAIL_RC" = 0 ] && [ "${jail_lines:-0}" -eq 0 ]; then
      JAIL_VERDICT=VOID          # exits clean having answered nothing
    elif [ "$JAIL_RC" = 0 ]; then
      JAIL_VERDICT=RUNS          # bench/ became optional — fine, but note it
    else
      JAIL_VERDICT=LOUD          # stripped dep, nonzero exit: correct
    fi
  fi

  # THE CORPUS COPY IS THE SECOND LEAK SURFACE, and the subtler one.
  # server.py applies _jail_ignore to the corpus too, because a corpus is
  # crawler output and nothing stops it carrying an answer-key-shaped file.
  # For a DOCUMENT corpus that filter is a hazard in the OTHER direction:
  # "answer", "baseline" and "gold" are ordinary business words, so real
  # documents ("Pre-Post Test 2024 ANSWER KEY.docx", "Baseline WB v3.xlsx")
  # get silently deleted from the jailed corpus and every count computed
  # there is quietly short.  Measured: 15 such files in microcosmo.  Report
  # the number; do not fail on it -- it is ssg-sim's policy, not prg's bug.
  #
  # Count TRUE SOURCES only.  Counting artifacts too makes the figure
  # index-state-dependent -- it read 15 on a de-indexed tree and 25 after a
  # re-index (the same 15 docs plus 10 of their .prg sidecars), which would
  # look like corpus drift on every run.  Sources are the stable quantity.
  CORPUS_LEAK_N=$(find "$DOCROOT" -type f \
                    \( -iname '*gold*' -o -iname '*baseline*' -o -iname '*expected*' \
                       -o -iname '*answer*' \) 2>/dev/null \
                  | grep -v '\.prg\.' | wc -l | tr -d ' ')
fi

# ================================ REPORT ====================================
printf '%s' "$rows"  > /tmp/prg-corpus-bench.rows.tsv
printf '%s' "$frows" > /tmp/prg-corpus-bench.feature.tsv

if [ "$PRETTY" = 1 ]; then
  echo "corpus   $CORPUS"
  echo "root     $DOCROOT"
  echo
  echo "-- PERF + PRECISION (naive rg vs tool) --"
  printf '%-14s %8s %8s | %8s %8s %8s\n' pattern raw_ms raw_hit tool_ms tool_hit tool_case
  printf '%-14s %8s %8s | %8s %8s %8s\n' -------------- -------- -------- -------- -------- --------
  while IFS=$'\t' read -r p rm rh tm th tc; do
    [ -z "$p" ] && continue
    printf '%-14s %8s %8s | %8s %8s %8s\n' "$p" "$rm" "$rh" "$tm" "$th" "$tc"
  done <<< "$rows"
  echo
  echo "RAW  total ${RAW_MS}ms   (faster and noisier — expected)"
  echo "TOOL total ${TOOL_MS}ms  cases ${TOOL_CASES_TOTAL}  attribution ${ATTR}  «nocase» ${TOTAL_NOCASE}"
  echo "PRECISION '${PROV_PAT}': RAW ${prov_raw} provenance hits -> TOOL ${prov_tool}"
  echo
  echo "-- FEATURE (every subverb) --"
  printf '%-12s %8s  %s\n' subverb rows verdict
  while IFS=$'\t' read -r n c v; do
    [ -z "$n" ] && continue; printf '%-12s %8s  %s\n' "$n" "$c" "$v"
  done <<< "$frows"
  echo
  echo "-- JAIL (ssg-sim _jail_ignore) --"
  if [ "$JAIL_VERDICT" = SKIP ]; then
    echo "skipped (no python3/server.py, or --no-jail)"
  else
    echo "files ${JAIL_N} copied · skill leaks ${LEAK_N} · jailed search exit ${JAIL_RC} -> ${JAIL_VERDICT}"
    [ "$LEAK_N" -gt 0 ] && printf '  LEAK %s\n' $LEAKS
    echo "corpus docs matching answer-key globs: ${CORPUS_LEAK_N}" \
         "(deleted from a jailed corpus copy — see note in source)"
  fi
  echo
  echo "rows -> /tmp/prg-corpus-bench.rows.tsv · features -> /tmp/prg-corpus-bench.feature.tsv"
else
  printf '%s' "$rows"
fi

# =============================== ACCEPTANCE =================================
[ "$LEAK_N" -le 0 ] || { echo "corpus-bench: FAIL(JAIL) answer key leaked into jail" >&2; exit 3; }

fail=0
if [ "$TOTAL_NOCASE" -gt 0 ]; then
  echo "corpus-bench: FAIL(attribution) ${TOTAL_NOCASE} hits not joined to a case" >&2; fail=1
fi
if [ "$prov_raw" -le 0 ]; then
  echo "corpus-bench: FAIL(precision) probe '${PROV_PAT}' matched 0 provenance lines —" \
       "the probe is vacuous, so the claim is UNTESTED, not passed" >&2; fail=1
elif [ "$prov_tool" -ne 0 ]; then
  echo "corpus-bench: FAIL(precision) ${prov_tool} provenance lines leaked the filter" >&2; fail=1
fi
if [ "$HITS_REGRESSION" -gt 0 ]; then
  echo "corpus-bench: FAIL(sanity) ${HITS_REGRESSION} pattern(s) where tool out-hit baseline" >&2; fail=1
fi
if [ "$FEAT_FAIL" -gt 0 ]; then
  echo "corpus-bench: FAIL(feature) ${FEAT_FAIL} subverb(s) empty or unparseable" >&2; fail=1
fi
if [ "$JAIL_VERDICT" = VOID ]; then
  echo "corpus-bench: FAIL(JAIL) jailed tool exits 0 having answered nothing (void pass)" >&2; fail=1
fi
[ "$fail" -eq 0 ] || exit 1

echo "corpus-bench: OK attribution ${ATTR} · precision ${prov_raw}->${prov_tool}" \
     "· features $(printf '%s' "$frows" | grep -c . ) · jail ${JAIL_VERDICT}" >&2
exit 0
