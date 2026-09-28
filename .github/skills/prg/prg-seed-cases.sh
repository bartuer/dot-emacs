#!/usr/bin/env bash
# prg-seed-cases.sh — MINE the regression gold set from the real corpus. NO LLM.
#
# What agents actually search is the source of truth for benchmark coverage.
# This replays every grep tool.execution_start argument recorded across ALL
# session-state events.jsonl, buckets each pattern into an empirical CLASS,
# picks the top-frequency real pattern per class, and checks the pattern is
# VIABLE (non-zero, bounded match count) against a PINNED gold root. The count
# is used ONLY as that viability filter; it is NOT persisted, because
# prg-regress.sh recounts live and gates vs regress.baseline.tsv (a stored
# count would be dead, drift-prone data). Output = bench/gold-search.tsv,
# one row per class:
#
#   class <TAB> pattern <TAB> flags <TAB> root
#
# Classes (from the empirical taxonomy, Context of plan 41 — measured over
# 1032 distinct real patterns across all session-state events.jsonl):
#   alternation  unescaped `|`               ~72% of real queries
#   symbol       identifier camel/snake       ~9%
#   regex        ^ $ metachar / escape        ~7%
#   casei        issued with -i               ~7%
#   phrase       multi-word literal           ~3%
#   literal      single plain word            ~2%
#
# Scale: velixo eval set = 84 stratified cases. We mirror that — a
# GOLD_TARGET (~84) of cases, allocated PER CLASS proportional to the real
# frequency above, each the top-frequency real pattern in that class with a
# non-zero, bounded, reproducible gold count against the pinned root.
#
# The gold root is fixed (modules + .github, node_modules excluded) so counts
# are stable and the whole mine runs in a couple seconds. Re-run to RE-MINE.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root: env override, else enclosing git worktree, else CWD (drop-in).
REPO_ROOT="${PRG_REPO_ROOT:-$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || pwd)}"
SS="${PRG_SESSION_STATE:-$HOME/.copilot/session-state}"
OUT="$HERE/bench/gold-search.tsv"
# PINNED gold root: bounded, representative, fast. Do NOT scan the full 27G.
GOLD_ROOTS=(modules .github)

command -v rg >/dev/null || { echo "prg-seed-cases: ripgrep required" >&2; exit 2; }
command -v jq >/dev/null || { echo "prg-seed-cases: jq required" >&2; exit 2; }
[ -d "$SS" ] || { echo "prg-seed-cases: session-state absent: $SS" >&2; exit 4; }

# ---- 1. harvest every recorded content-search {pattern, -i} across sessions -
# Source of truth = grep + rg tool calls (both carry a content .pattern).  glob
# is EXCLUDED: its .pattern is a PATH glob, not a content regex — different
# semantics, would pollute the class taxonomy.  Measured: grep+rg = 1032
# distinct real patterns, the exact universe the stratified quota is sized to.
harvest() {
  # NOTE: emit with STRING INTERPOLATION + a literal \t, NOT `@tsv`.
  # `@tsv` re-escapes backslashes ( \  ->  \\ ), which corrupts every regex
  # pattern: an agent's `^\* TODO Goal` (54 real hits) became `^\\* TODO Goal`
  # (0 hits — `\\*` = literal backslash) and silently dropped ~20 anchored/
  # regex cases from the gold set.  `jq -r "...\t..."` preserves the single
  # backslash.  (Patterns with an embedded literal tab are not present in the
  # corpus; if they ever appear, they'd split wrong — acceptable, documented.)
  find "$SS" -name events.jsonl -print0 2>/dev/null \
    | xargs -0 cat 2>/dev/null \
    | jq -rc 'select(.type=="tool.execution_start"
                     and (.data.toolName=="grep" or .data.toolName=="rg")
                     and (.data.arguments.pattern!=null))
              | .data.arguments as $a
              | "\($a["-i"] // false)\t\($a.pattern)"' 2>/dev/null
}

# ---- 2. classify a pattern -> one of SIX empirical classes ------------------
# Order is significant (first match wins), mirroring the measured taxonomy:
#   casei (-i flag) > alternation (unescaped |) > regex (metachar) >
#   symbol (bare identifier) > phrase (has space) > literal (plain word).
classify() { # $1=pattern  $2=case_i(true|false)  -> echoes class
  local p="$1" ci="$2"
  # strip escaped pipes so only a TRUE alternation `|` counts
  local stripped="${p//\\|/}"
  [[ "$ci" == "true" ]] && { echo casei; return; }
  [[ "$stripped" == *"|"* ]] && { echo alternation; return; }
  # regex: any regex metachar (^ $ [ ] ( ) * + ? { ) or a backslash escape
  case "$p" in
    *'^'*|*'$'*|*'\'*|*'['*|*'('*|*')'*|*'*'*|*'+'*|*'?'*|*'{'*) echo regex; return;;
  esac
  # symbol: pure identifier with a camel/snake hint (an uppercase or underscore)
  if [[ "$p" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && ( "$p" =~ [A-Z] || "$p" == *_* ) ]]; then
    echo symbol; return; fi
  # phrase: multi-word literal (contains a space, no metachar reached here)
  [[ "$p" == *" "* ]] && { echo phrase; return; }
  echo literal
}

# ---- 3./4. STRATIFIED selection: fill each class up to its velixo quota -----
# (counting is done in the PARALLEL count_one() below — the old serial
# gold_count() was removed once the parallel path replaced it; kiss.)
# Velixo eval set = 84 stratified cases.  We mirror that shape, allocating the
# 84 slots PER CLASS proportional to the measured real frequency:
#   alternation 48  symbol 12  regex 8  casei 8  phrase 5  literal 3  (= 84)
# Within a class, patterns are taken in FREQUENCY-DESC order (the ones agents
# issue most), keeping only the non-zero, bounded (<100000) ones.
GOLD_TARGET="${PRG_GOLD_TARGET:-84}"
declare -A QUOTA=( [alternation]=48 [symbol]=12 [regex]=8 [casei]=8 [phrase]=5 [literal]=3 )
CLASS_ORDER=(alternation symbol regex casei phrase literal)
declare -A FILLED
for c in "${CLASS_ORDER[@]}"; do FILLED[$c]=0; done

mkdir -p "$HERE/bench"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# rank distinct patterns by frequency (desc); classify; keep those still under
# their class quota, writing one candidate line per accepted pattern.  We defer
# the (slower) gold_count to a PARALLEL pass so 84 counts fan across cores.
CAND="$WORK/candidates.tsv"; : > "$CAND"
harvest | sort | uniq -c | sort -rn | while read -r n ci p; do
  # read splits on whitespace: n=freq, ci=case flag, p=rest(pattern w/ spaces)
  [ -z "${p:-}" ] && continue
  cls="$(classify "$p" "$ci")"
  q="${QUOTA[$cls]:-0}"; f="${FILLED[$cls]:-0}"
  [ "$f" -ge "$q" ] && continue          # class already full
  FILLED[$cls]=$((f+1))
  printf '%s\t%s\t%s\n' "$cls" "$ci" "$p" >> "$CAND"
done

# ---- PARALLEL gold_count (race-free: each job writes its OWN tmp file) -------
# Recipe B contract — never let N parallel writers share one > FILE (interleaved
# writes corrupt the TSV).  Each candidate -> its own $WORK/row.NNNN, then cat.
export -f gold_count 2>/dev/null || true
export REPO_ROOT
GR_STR="${GOLD_ROOTS[*]}"; export GR_STR
count_one() { # $1=lineno  $2=cls  $3=ci  $4=pattern
  local ln="$1" cls="$2" ci="$3" p="$4" flag="" gc
  [[ "$ci" == "true" ]] && flag="-i"
  local roots=(); for r in $GR_STR; do roots+=("$REPO_ROOT/$r"); done
  # Globs MUST be anchored with **/ — rg globs are relative to each search
  # root, so a bare `bench/gold-search.tsv` never matches the real path
  # `.github/skills/prg/bench/gold-search.tsv`.  A broken exclusion let the
  # gold file self-match (patterns contain DONE|TODO|Phase|^\*), and since the
  # file GROWS each mine, counts drifted between runs (14219 -> 14224) —
  # breaking reproducibility.  Anchored globs make counts stable.
  gc="$(rg -c --no-messages -g '!**/node_modules/**' -g '!**/gold-search.tsv' \
        $flag -e "$p" "${roots[@]}" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
  # viability: non-zero AND bounded (drop matches-everything patterns).
  # $gc is used ONLY as this mine-time filter; it is NOT written as a column
  # (kiss: prg-regress.sh recounts live and gates vs regress.baseline.tsv, so
  # a persisted count would be dead data that drifts every mine).
  if [ "${gc:-0}" -gt 0 ] && [ "${gc:-0}" -lt 100000 ]; then
    local flags=""; [[ "$ci" == "true" ]] && flags="-i"
    printf '%s\t%s\t%s\t%s\n' "$cls" "$p" "$flags" "modules,.github" \
      > "$WORK/row.$(printf '%05d' "$ln")"
  fi
}
export -f count_one; export WORK
nl -ba -w1 -s$'\t' "$CAND" \
  | parallel -j"$(nproc)" --colsep '\t' count_one {1} {2} {3} {4}

# ---- STRUCTURED-SOURCE rows: one jq-lens case per structured source, so the
#      benchmark measures FLEXIBILITY across every real source (not just flat
#      text).  Line-JSON -> jq lens (per-source tool matrix), NOT rg over JSON.
#      Counted LIVE here (re-mineable, not hand-frozen).  A source whose corpus
#      is absent is simply skipped — the row is not emitted.  Format reuses the
#      4-col schema: class=jq:<lens>  pattern=<value>  flags=<field>  root=<tag>
#      (the live count is used only to decide the row is viable, not written).
STRUCT="$WORK/struct.tsv"; : > "$STRUCT"
# session-state: tally tool.execution_start by tool name; pin the top TOOL.
if [ -d "$SS" ]; then
  n=$(find "$SS" -name events.jsonl -print0 2>/dev/null | xargs -0 cat 2>/dev/null \
       | jq -rc -f "$HERE/jq/session-tool.jq" 2>/dev/null \
       | jq -rc 'select(.tool=="grep")' 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && printf 'jq:session-tool\tgrep\t.tool\tsession-state\n' >> "$STRUCT"
fi
# L-server: tally response objects by model; pin the dominant model.
LS="${PRG_LOG_CORPUS:-}"
if [ -n "$LS" ] && [ -d "$LS" ]; then
  n=$(find "$LS" -maxdepth 1 -name '*.response.json' -print0 2>/dev/null | xargs -0 cat 2>/dev/null \
       | jq -rc -f "$HERE/jq/count-by-model.jq" 2>/dev/null \
       | jq -rc 'select(.model=="claude-opus-4-8")' 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -gt 0 ] && printf 'jq:count-by-model\tclaude-opus-4-8\t.model\tL-server\n' >> "$STRUCT"
fi

# ---- assemble: stable class order; within a class keep freq order (row.NNNN
#      is numbered by descending-frequency rank, so a plain cat preserves it) -
ALLROWS="$WORK/all.tsv"; cat "$WORK"/row.* 2>/dev/null > "$ALLROWS" || : > "$ALLROWS"
{ printf '# example-only: gold-search.tsv is a COMPUTED fixture RE-MINED from THIS repo'"'"'s\n'
  printf '# session history; col-2 PATTERN values are literal strings a real agent searched\n'
  printf '# for here (may name this-repo paths). Another repo re-mines its own via\n'
  printf '# PRG_REPO_ROOT. There is NO count column: prg-regress.sh recounts live\n'
  printf '# and gates vs regress.baseline.tsv, so a persisted count would be dead\n'
  printf '# data that drifts every mine. Do NOT hand-edit. See prg-bench-coverage.md.\n'
  printf '# class\tpattern\tflags\troot\n'
  for c in "${CLASS_ORDER[@]}"; do grep "^$c	" "$ALLROWS" 2>/dev/null; done
  cat "$STRUCT" 2>/dev/null
} > "$OUT"

rows=$(grep -vc '^#' "$OUT")
echo "prg-seed-cases: mined $rows gold rows (target $GOLD_TARGET) -> $OUT" >&2
{ echo "  per-class:"; grep -v '^#' "$OUT" | cut -f1 | sort | uniq -c \
    | awk '{printf "    %-12s %s\n",$2,$1}'; } >&2
[ "$rows" -ge 1 ] || exit 4
