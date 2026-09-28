#!/usr/bin/env bash
# prg-regress.sh — regression harness for the whole prg toolchain. NO LLM.
#
# Runs a fixed set of CASES (real queries against the dev corpus: the repo
# for graph/LSP, the PRG_LOG_CORPUS dir for log) and records, per case:
#   name  ok  wall_ms  count   (count = edges / rows / refs the case produced)
#
# Two modes:
#   record   -> write the current run as the baseline (bench/regress.baseline.tsv)
#   check    -> run now, diff vs baseline, FAIL if:
#                 - any case's ok flips 1->0            (correctness regression)
#                 - count drops below baseline*(1-TOL)  (completeness regression)
#                 - wall_ms exceeds baseline*(1+SLOW)   (perf regression)
#
# Agent-first: default output is stable TSV to stdout; a one-line VERDICT to
# stderr. Exit 0 all-green, 1 on any regression, 2 bad args, 4 corpus absent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$HERE/bench/regress.baseline.tsv"
# Repo root: env override, else the enclosing git worktree (so the skill is
# drop-in for any repo), else the CWD.  ZERO hardcoded project coupling.
REPO_ROOT="${PRG_REPO_ROOT:-$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TOL="${PRG_REGRESS_TOL:-0.15}"    # completeness: allow count within 15% below baseline
SLOW="${PRG_REGRESS_SLOW:-1.0}"   # perf: allow up to 2x baseline wall (1.0 = +100%)
MODE="${1:-check}"

command -v jq >/dev/null || { echo "prg-regress: jq required" >&2; exit 2; }

# ---- CASES -----------------------------------------------------------------
# Each case prints, on success, ONE integer to stdout = its "count" metric and
# exits 0; on failure exits non-zero. We time it and capture that count.

# Graph seeds are EXAMPLE FIXTURES (example-only, overridable by env): the case
# emits 0 (a no-op gate) when the seed is absent, so the bench is drop-in for
# any repo.  The default paths below are THIS repo's example seeds; override
# with PRG_TS_SEED / PRG_PY_SEED / PRG_LSP_SEED (+ *_ROOT) in another repo.
TS_SEED="${PRG_TS_SEED:-$REPO_ROOT/modules/core/src/tracing/traceparent.ts}"  # example-only
TS_ROOT="${PRG_TS_ROOT:-$REPO_ROOT/modules}"
PY_SEED="${PRG_PY_SEED:-$REPO_ROOT/agents/excel-agent/ea_mcp/_otel.py}"  # example-only
PY_ROOT="${PRG_PY_ROOT:-$REPO_ROOT/agents}"
case_graph_ts() { # TS cross-file refs must stay >= baseline
  [ -f "$TS_SEED" ] || { echo SKIP; return 0; }
  "$HERE/prg-graph.sh" getActiveTraceparent \
    --seed "$TS_SEED" --root "$TS_ROOT" --out /tmp/prg-reg-gts >/dev/null 2>&1 || return 1
  awk -F'\t' '$5=="ref"' /tmp/prg-reg-gts/edges.tsv | wc -l
}
case_graph_py() { # Python refs via jedi
  [ -f "$PY_SEED" ] || { echo SKIP; return 0; }
  "$HERE/prg-graph.sh" extract_traceparent \
    --seed "$PY_SEED" --root "$PY_ROOT" --out /tmp/prg-reg-gpy >/dev/null 2>&1 || return 1
  awk -F'\t' '$5=="ref"' /tmp/prg-reg-gpy/edges.tsv | wc -l
}
case_lsp_precision() { # LSP must stay tighter than lexical (precision guard):
  # print lexical_edges - lsp_edges ; must stay > 0 (positive gap).
  local sf lsp lex
  sf="${PRG_LSP_SEED:-$REPO_ROOT/modules/core/src/tracing/provider.ts}"
  [ -f "$sf" ] || { echo SKIP; return 0; }   # example fixture; SKIP when absent
  "$HERE/prg-graph.sh" initTracer --seed "$sf" --root "$TS_ROOT" \
    --engine lsp --out /tmp/prg-reg-lsp >/dev/null 2>&1 || return 1
  lsp=$(wc -l < /tmp/prg-reg-lsp/edges.tsv)
  "$HERE/prg-graph.sh" initTracer --root "$TS_ROOT" \
    --engine lexical --out /tmp/prg-reg-lex >/dev/null 2>&1 || return 1
  lex=$(wc -l < /tmp/prg-reg-lex/edges.tsv)
  [ "$lex" -gt "$lsp" ] || return 1
  echo $(( lex - lsp ))
}
# SKIP sentinel: a corpus-dependent case echoes "SKIP" when its corpus is
# absent so run_all omits the row entirely — SYMMETRIC across record/check, so
# a drop-in repo with no L-server corpus never false-REGRESSES (STEP-5 fix).
_have_lserver() { local d="${PRG_LOG_CORPUS:-}"; [ -n "$d" ] && [ -d "$d" ]; }
case_log_models() { # count-by-model must find our model fleet
  _have_lserver || { echo SKIP; return 0; }
  "$HERE/prg-log.sh" count-by-model 2>/dev/null | jq -s 'length'
}
case_log_grep() { # the quoting-bug guard: grep must return the sonnet rows
  _have_lserver || { echo SKIP; return 0; }
  "$HERE/prg-log.sh" grep 'select(.model=="claude-sonnet-4-5")|.requestId' 2>/dev/null | wc -l
}

# ---- BIG-CORPUS THROUGHPUT cases (the SPEED axis on real volume) ------------
# Each scans a BOUNDED but non-trivial slice of a real source and reports
# records/sec as its "count", so the existing completeness gate protects it:
# a throughput DROP below baseline*(1-TOL) fires REGRESS[completeness].  The
# slice is capped (head -N / maxdepth) so we never scan the full 6.6G/27G.
# records/sec = records / max(wall_s, 1ms) — integer, 0 if the source is absent
# (a 0 baseline makes the gate a no-op, so an absent corpus never false-fails).
_rps() { # $1=record_count $2=elapsed_ns  -> integer records/sec
  awk -v n="$1" -v e="$2" 'BEGIN{ s=e/1e9; if(s<0.001)s=0.001; printf "%d", n/s }'
}
case_tput_session() { # scan a bounded slice of session-state events, count events
  local dir="${HOME}/.copilot/session-state"; [ -d "$dir" ] || { echo SKIP; return 0; }
  local f; f=$(find "$dir" -name events.jsonl 2>/dev/null | head -1); [ -n "$f" ] || { echo SKIP; return 0; }
  local t0 t1 n; t0=$(date +%s%N)
  n=$(head -20000 "$f" 2>/dev/null | jq -rc .type 2>/dev/null | wc -l); t1=$(date +%s%N)
  _rps "$n" "$((t1-t0))"
}
case_tput_lserver() { # scan a bounded slice of L-server responses, count models
  local dir="${PRG_LOG_CORPUS:-}"; [ -n "$dir" ] && [ -d "$dir" ] || { echo SKIP; return 0; }
  local t0 t1 n; t0=$(date +%s%N)
  n=$(find "$dir" -maxdepth 1 -name '*.response.json' 2>/dev/null | head -200 \
        | xargs cat 2>/dev/null | jq -rc '.model // empty' 2>/dev/null | wc -l); t1=$(date +%s%N)
  _rps "$n" "$((t1-t0))"
}
case_tput_repo() { # rg-scan a bounded repo slice, count matched lines/sec
  local root="$REPO_ROOT/modules"; [ -d "$root" ] || root="$REPO_ROOT"
  [ -d "$root" ] || { echo SKIP; return 0; }
  local t0 t1 n; t0=$(date +%s%N)
  n=$(rg -c --no-messages -g '!**/node_modules/**' -e 'function|const|class' "$root" 2>/dev/null \
        | awk -F: '{s+=$2} END{print s+0}'); t1=$(date +%s%N)
  _rps "$n" "$((t1-t0))"
}

case_search_json() { # --json search-hit lens is loss-free vs plain rg + well-formed
  # Fixed in-repo target (repo root always present via git rev-parse -> no SKIP).
  local pat='index' file="$HERE/SKILL.md" lens="$JQ_LENS_DIR/search-hit.jq"
  [ -f "$file" ] && [ -f "$lens" ] || { echo SKIP; return 0; }
  local raw jn ok
  raw=$(rg --no-messages "$pat" "$file" 2>/dev/null | wc -l | tr -d ' ')
  # every emitted line must be valid JSON carrying all 6 keys, else count 0 -> RED
  jn=$(rg --json "$pat" "$file" 2>/dev/null | jq -n -c -f "$lens" 2>/dev/null \
        | jq -e 'has("path") and has("line") and has("col") and has("keyword") and has("content") and has("index")' 2>/dev/null \
        | grep -c true)
  # loss-free: json rows must equal plain-rg matched-line count
  [ "$jn" = "$raw" ] && ok="$jn" || ok=0
  echo "$ok"
}

# CRASH-TRIAGE case (HERO 3): the log-exception -> symbol -> source chain.
# Self-contained (a PINNED exception line + an in-repo symbol), so it never
# SKIPs and always gates the capability.  Verifies the load-bearing invariant:
# a stack frame's `dist/...js:LINE` is a BUILD artifact — the workflow must
# pivot on the SYMBOL and resolve the SOURCE (.ts) def, NOT trust the dist line.
# Count metric = source ref-sites found for the symbol; 0 (RED) if any link in
# the chain breaks (jq can't pull the method, or the def resolves to .js/dist).
case_crash_triage() {
  # 1. LOG->FRAME: a real pasted exception record; jq extracts the METHOD.
  local rec method sym src_root
  rec='{"level":"error","err":{"name":"TypeError","message":"ownerAgent?.hasActiveTurn is not a function","frame":"dist/src/websocket/websocket-manager.js:850:33","method":"WebSocketManager.onSessionClosed"}}'
  method=$(printf '%s' "$rec" | jq -r '.err.method' 2>/dev/null)   # WebSocketManager.onSessionClosed
  # 2. FRAME->SYMBOL: the join key is the bare method name, NOT the dist line.
  sym="${method##*.}"                                              # onSessionClosed
  [ -n "$sym" ] && [ "$sym" != "null" ] || { echo 0; return 0; }
  # 3. SYMBOL->SOURCE: graph the symbol in SOURCE; the def MUST be a .ts file
  #    (source), never the .js/dist artifact the frame named.
  src_root="$REPO_ROOT/modules/core/src"
  [ -d "$src_root" ] || { echo SKIP; return 0; }                  # drop-in repos skip
  local out="/tmp/prg-reg-crash.$$"                               # unique: no tmp collision
  "$HERE/prg-graph.sh" "$sym" --root "$src_root" --depth 1 \
      --out "$out" >/dev/null 2>&1 || { echo 0; return 0; }
  # INVARIANT: at least one def-site, and it lives in a .ts SOURCE file, not dist.
  local ts_defs js_defs
  ts_defs=$(awk -F'\t' '$5=="def" && $3 ~ /\.ts$/ && $3 !~ /(\/dist\/|\.js$)/' "$out/edges.tsv" | wc -l)
  js_defs=$(awk -F'\t' '$5=="def" && $3 ~ /(\/dist\/|\.js$)/' "$out/edges.tsv" | wc -l)
  # Count metric = SOURCE (.ts) def-sites for the symbol — the STABLE invariant
  # number (refs jitter run-to-run; def-sites don't).  RED (0) unless the method
  # was extracted, a .ts SOURCE def exists, and NO .js/dist def leaked in.
  if [ "$ts_defs" -ge 1 ] && [ "$js_defs" -eq 0 ]; then
    echo "$ts_defs"
  else
    echo 0
  fi
}

CASES="case_graph_ts case_graph_py case_lsp_precision case_log_models case_log_grep \
case_tput_session case_tput_lserver case_tput_repo case_search_json case_crash_triage"

# ---- MINED SEARCH CASES ----------------------------------------------------
# Each row of bench/gold-search.tsv (4 cols: class pattern flags root) becomes
# a case: replay the real mined pattern against the same pinned gold root and
# emit its LIVE match count. The baseline captured that live count; a rg/engine/
# flag regression makes it drop and the completeness gate fires. The gold file
# carries NO count column — the count lives only in regress.baseline.tsv, which
# is what check gates against. Coverage grows by RE-MINING (prg-seed-cases.sh),
# never by editing this file.
GOLD="$HERE/bench/gold-search.tsv"
GOLD_ROOTS=(modules .github)   # MUST match prg-seed-cases.sh

run_gold_case() { # $1=pattern  $2=flags  -> live match count against gold root
  local p="$1" flags="$2"
  # Globs MUST be ANCHORED (**/) and MUST match prg-seed-cases.sh exactly, or
  # the live count won't equal the mined gold_count and every row false-fails.
  # A bare `!bench/gold-search.tsv` / `!node_modules` never matches (rg globs
  # are root-relative) — see the miner's fix note.
  rg -c --no-messages -g '!**/node_modules/**' -g '!**/gold-search.tsv' \
     $flags -e "$p" "${GOLD_ROOTS[@]/#/$REPO_ROOT/}" 2>/dev/null \
     | awk -F: '{s+=$2} END{print s+0}'
}

# ---- structured-source (jq-lens) gold counting ----------------------------
# A gold row whose class is `jq:<lens>` is counted with the source's jq lens
# (per-source tool matrix: line-JSON -> jq, NOT rg over JSON), not run_gold_case.
#   class = jq:<lens>     e.g. jq:session-tool | jq:lserver-model
#   pattern = match value e.g. grep | claude-opus-4-8
#   flags   = jq field    e.g. .tool | .model
#   root    = corpus tag  e.g. session-state | L-server
# Corpus ABSENT -> caller SKIPS the row (emits nothing), so it is symmetric
# across record/check and never false-fails.  Broken lens -> count 0 -> RED.
JQ_LENS_DIR="$HERE/jq"
jq_corpus_dir() { case "$1" in
  session-state) echo "${HOME}/.copilot/session-state";;
  L-server)      echo "${PRG_LOG_CORPUS:-}";;
  agent-logs)    echo "${PRG_TRACE_CORPUS:-/agent/logs}";;
  *)             echo "";;
esac; }
run_gold_jq() { # $1=lens $2=value $3=field $4=root -> count (or "SKIP")
  local lens="$1" val="$2" field="$3" root="$4"
  local dir; dir="$(jq_corpus_dir "$root")"
  [ -n "$dir" ] && [ -d "$dir" ] || { echo SKIP; return 0; }
  local files
  case "$root" in
    session-state) mapfile -d '' -t files < <(find "$dir" -name events.jsonl -print0 2>/dev/null);;
    L-server)      mapfile -d '' -t files < <(find "$dir" -maxdepth 1 -name '*.response.json' -print0 2>/dev/null);;
    agent-logs)    mapfile -d '' -t files < <(find "$dir" -maxdepth 1 -name '*.jsonl' -print0 2>/dev/null);;
  esac
  [ "${#files[@]}" -gt 0 ] || { echo SKIP; return 0; }
  # Trajectory lenses require a span (--arg FROM/TO); the bench probes a
  # STABLE keyword regardless of time, so pass a wide-open span (ISO stamps
  # sort lexically, all real ts start with '2', so "0".."9" spans everything).
  local jqargs=()
  case "$root" in agent-logs) jqargs=(--arg FROM 0 --arg TO 9);; esac
  cat "${files[@]}" 2>/dev/null \
    | jq -rc "${jqargs[@]}" -f "$JQ_LENS_DIR/${lens}.jq" 2>/dev/null \
    | jq -rc --arg f "${field#.}" --arg v "$val" 'select(.[$f]==$v)' 2>/dev/null \
    | wc -l | tr -d ' '
}

# A gold row whose class is `git:log-s` counts commits that ADD/REMOVE a
# symbol (pickaxe) within a pathspec -> a stable, corpus-free time-sensitive
# trajectory probe.  This is the "attribute changed symbols through git" case:
# we do NOT reinvent a diff parser (read_pr/read_patch own that at runtime);
# the bench just gates that `git log -S` still finds the known commits.
# pat = symbol, flags = pathspec (e.g. *.ts), root = ignored (repo is $HERE).
run_gold_git() { # $1=symbol $2=pathspec -> commit count (deterministic)
  local sym="$1" spec="${2:-}"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo SKIP; return 0; }
  if [ -n "$spec" ]; then
    git -C "$REPO_ROOT" log --oneline -S "$sym" -- "$spec" 2>/dev/null | wc -l | tr -d ' '
  else
    git -C "$REPO_ROOT" log --oneline -S "$sym" 2>/dev/null | wc -l | tr -d ' '
  fi
}

emit_gold_rows() { # -> TSV rows: search_<class>_<NN> ok wall_ms count
  [ -f "$GOLD" ] || return 0
  # The row NAME is the join key between record and check.  It MUST be
  # UNIQUE per gold row, or many same-class rows collapse onto the first
  # baseline row of that class and false-regress (see plan CKP-4c fix).
  # A stable per-class ordinal (gold-file order is reproducible) keeps the
  # name readable while making it a 1:1 key.
  declare -A seen
  while IFS=$'\t' read -r cls pat flags root; do
    [ -z "${cls:-}" ] && continue
    case "$cls" in \#*) continue;; esac
    seen["$cls"]=$(( ${seen["$cls"]:-0} + 1 ))
    local nn; printf -v nn '%02d' "${seen["$cls"]}"
    local t0 t1 out
    t0=$(date +%s%3N)
    case "$cls" in
      jq:*) out=$(run_gold_jq "${cls#jq:}" "$pat" "$flags" "$root")
            [ "$out" = SKIP ] && continue ;;   # corpus absent -> symmetric skip
      git:*) out=$(run_gold_git "$pat" "$flags")
            [ "$out" = SKIP ] && continue ;;   # not a git repo -> symmetric skip
      *)    out=$(run_gold_case "$pat" "$flags") ;;
    esac
    t1=$(date +%s%3N)
    # sanitize the class for the row name (jq:foo -> jqfoo) so it stays a
    # single TSV token.
    local safe="${cls//[^a-zA-Z0-9]/}"
    printf 'search_%s_%s\t1\t%s\t%s\n' "$safe" "$nn" "$((t1-t0))" "$out"
  done < "$GOLD"
}

run_all() { # -> TSV rows: name ok wall_ms count
  for c in $CASES; do
    local t0 t1 out rc
    t0=$(date +%s%3N)
    out=$("$c" 2>/dev/null); rc=$?
    t1=$(date +%s%3N)
    # SKIP sentinel -> corpus/seed absent: omit the row (symmetric across
    # record & check), so a drop-in repo never false-REGRESSES on it.
    [ "$out" = SKIP ] && continue
    [ "$rc" -eq 0 ] && ok=1 || ok=0
    out="${out//[^0-9]/}"; out="${out:-0}"
    printf '%s\t%s\t%s\t%s\n' "$c" "$ok" "$((t1-t0))" "$out"
  done
  emit_gold_rows
}

case "$MODE" in
  record)
    mkdir -p "$HERE/bench"
    run_all | tee "$BASE"
    echo "prg-regress: baseline recorded -> $BASE" >&2
    ;;
  check)
    [ -f "$BASE" ] || { echo "prg-regress: no baseline; run 'prg-regress.sh record' first" >&2; exit 2; }
    now="$(run_all)"
    printf '%s\n' "$now"
    # diff vs baseline
    fail=0
    while IFS=$'\t' read -r name ok wall count; do
      bl=$(awk -F'\t' -v n="$name" '$1==n{print $2"\t"$3"\t"$4}' "$BASE")
      [ -z "$bl" ] && { echo "NEW case (no baseline): $name" >&2; continue; }
      IFS=$'\t' read -r bok bwall bcount <<<"$bl"
      # correctness: ok must not drop 1->0
      if [ "$bok" = 1 ] && [ "$ok" = 0 ]; then
        echo "REGRESS[correctness] $name: ok 1->0" >&2; fail=1; fi
      # THROUGHPUT rows (case_tput_*) measure records/sec, which is wall-clock
      # derived and swings >30% under load — a tight completeness floor would
      # false-fire.  Their real contract (per the :test_tool: gate) is
      # "measured, positive, bounded", so gate ONLY on count>0 here.
      case "$name" in
        case_tput_*)
          if [ "$count" -le 0 ]; then
            echo "REGRESS[throughput] $name: records/sec $count <= 0 (baseline $bcount)" >&2; fail=1; fi
          continue ;;
      esac
      # completeness: count must not fall below baseline*(1-TOL)
      floor=$(awk -v b="$bcount" -v t="$TOL" 'BEGIN{printf "%d", b*(1-t)}')
      if [ "$count" -lt "$floor" ]; then
        echo "REGRESS[completeness] $name: count $count < floor $floor (baseline $bcount)" >&2; fail=1; fi
      # perf: wall must not exceed baseline*(1+SLOW)
      ceil=$(awk -v b="$bwall" -v s="$SLOW" 'BEGIN{printf "%d", b*(1+s)}')
      if [ "$wall" -gt "$ceil" ] && [ "$bwall" -gt 0 ]; then
        echo "REGRESS[perf] $name: wall ${wall}ms > ceil ${ceil}ms (baseline ${bwall}ms)" >&2; fail=1; fi
    done <<<"$now"
    if [ "$fail" -eq 0 ]; then echo "prg-regress: VERDICT green (all cases within baseline)" >&2; exit 0
    else echo "prg-regress: VERDICT RED (regressions above)" >&2; exit 1; fi
    ;;
  -h|--help|"")
    sed -n '2,24p' "$HERE/prg-regress.sh" | sed 's/^# \{0,1\}//'
    exit 2;;
  *) echo "prg-regress: unknown mode '$MODE' (record|check)" >&2; exit 2;;
esac
