#!/usr/bin/env bash
# prg-bench.sh — seed-quality + latency benchmark for the prg loop head (CKP-5b).
#
# WHAT IT DOES
#   For each MODEL (plus the model-free `--no-model` tool baseline), run every
#   DIRECTION in bench/gold.tsv through prg-seed.sh, score the emitted seeds
#   against the gold expected symbols, and time the calls both SOLO and under a
#   parallel FAN-OUT of K branches.  Emits one JSONL row per model:
#
#     {"model","tier","n","recall","precision","p50_ms","p95_ms",
#      "fanout_k","fanout_wall_ms","fanout_speedup"}
#
#   --pretty renders the rows as an aligned table instead of JSONL.
#
# WHY MODEL-FREE STAYS MODEL-FREE
#   Only prg-llm.sh (called INSIDE prg-seed.sh's model tier) ever touches a
#   model.  prg-bench.sh itself calls NO model — it only orchestrates prg-seed.sh
#   runs and does arithmetic.  The `--no-model` row is the tool-only tier: it is
#   the precision floor the model tiers must beat.
#
# SCORING (matches bench/gold.tsv header)
#   A direction PASSES when the emitted seed set CONTAINS >=1 expected symbol
#   (case-insensitive SUBSTRING: a candidate name that contains the gold symbol
#   counts).  recall = passed/total.  precision = expected-hit-seeds / emitted
#   (only meaningful for the model tier, which returns a short list; the tool
#   tier returns the whole ranked window so its precision is ~1/window).
#
# LATENCY
#   SOLO = median/p95 of per-direction wall time run sequentially.
#   FAN-OUT = wall time to run ALL directions concurrently (xargs -P K); the
#   speedup vs solo-sum is what proves the proxy is fan-out-safe (a full
#   `copilot -p` boot at 34.7s/22.4cr cannot be fanned out — that's the whole
#   reason the 11434 proxy is the loop head).
#
# USAGE
#   prg-bench.sh --models "claude-sonnet-4-5 claude-opus-4-8" [opts]
#   prg-bench.sh --models default            # sonnet-4-5 + opus-4-8
#   prg-bench.sh --no-model-only             # just the tool baseline row
#   Options:
#     --gold PATH     gold fixture (default bench/gold.tsv next to this script)
#     --root "R1 R2"  prg-seed roots      (default "modules agents")
#     --top N         prg-seed candidate window (default 30)
#     --fanout K      parallel width       (default 6 — the measured safe width)
#     --pretty        table instead of JSONL
#     --include-baseline   also emit the --no-model tool row (default on)
#     --no-baseline        skip the tool row
#
# ENV
#   PRG_REPO_ROOT   repo root to run from (default: git toplevel, else CWD).
#   PRG_LLM_URL     proxy base (passed through prg-seed.sh -> prg-llm.sh).
#
# EXIT: 0 ok · 2 usage/dep · 3 proxy unreachable (no model row can be scored)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null || { echo "prg-bench: jq required" >&2; exit 2; }

# ---- repo root: prg-seed roots are repo-relative; run from the top ----------
REPO_ROOT="${PRG_REPO_ROOT:-$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

# ---- defaults --------------------------------------------------------------
MODELS=""
GOLD="$HERE/bench/gold.tsv"
ROOT="modules agents"
TOP=30
FANOUT=6
PRETTY=0
INCLUDE_BASELINE=1
NO_MODEL_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --models)           MODELS="$2"; shift 2 ;;
    --gold)             GOLD="$2"; shift 2 ;;
    --root)             ROOT="$2"; shift 2 ;;
    --top)              TOP="$2"; shift 2 ;;
    --fanout)           FANOUT="$2"; shift 2 ;;
    --pretty)           PRETTY=1; shift ;;
    --include-baseline) INCLUDE_BASELINE=1; shift ;;
    --no-baseline)      INCLUDE_BASELINE=0; shift ;;
    --no-model-only)    NO_MODEL_ONLY=1; INCLUDE_BASELINE=1; shift ;;
    -h|--help)          sed -n '2,55p' "$0"; exit 0 ;;
    *) echo "prg-bench: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -f "$GOLD" ] || { echo "prg-bench: gold not found: $GOLD" >&2; exit 2; }
if [ "$MODELS" = default ]; then MODELS="claude-sonnet-4-5 claude-opus-4-8"; fi

# ---- proxy reachability (only needed if we score a model tier) -------------
if [ "$NO_MODEL_ONLY" = 0 ] && [ -n "$MODELS" ]; then
  if ! "$HERE/prg-llm.sh" --probe >/dev/null 2>&1; then
    echo "prg-bench: proxy unreachable (prg-llm.sh --probe != 0) — cannot score model tiers" >&2
    echo "prg-bench: re-run with --no-model-only for the tool baseline" >&2
    exit 3
  fi
fi

# ---- load gold into arrays (skip # and blank) ------------------------------
DIRS=(); WANTS=()
while IFS=$'\t' read -r d w; do
  case "$d" in ''|\#*) continue;; esac
  [ -n "$w" ] || continue
  DIRS+=("$d"); WANTS+=("$w")
done < "$GOLD"
N="${#DIRS[@]}"
[ "$N" -gt 0 ] || { echo "prg-bench: no gold rows in $GOLD" >&2; exit 2; }

now_ms() { date +%s%3N; }

# ---- score ONE direction for a tier. echoes: "<pass 0|1> <hit_seeds> <emitted>"
# tier: the string "" (tool/--no-model) or a model name.
score_one() {
  local dir="$1" want="$2" tier="$3"
  local out
  if [ "$tier" = "--no-model" ]; then
    out="$("$HERE/prg-seed.sh" "$dir" --no-model --root "$ROOT" --top "$TOP" 2>/dev/null | cut -f1 || true)"
  else
    out="$("$HERE/prg-seed.sh" "$dir" --root "$ROOT" --top "$TOP" --model "$tier" 2>/dev/null || true)"
  fi
  local emitted hit pass
  emitted="$(printf '%s\n' "$out" | awk 'NF' | wc -l | tr -d ' ')"
  # hit_seeds = emitted seeds that CONTAIN an expected symbol (substring, ci).
  # want may be pipe-separated alternatives.
  hit="$(printf '%s\n' "$out" | awk 'NF' | grep -icE "$want" || true)"
  pass=0; [ "${hit:-0}" -gt 0 ] && pass=1
  echo "$pass ${hit:-0} ${emitted:-0}"
}

# ---- run a full tier: solo pass over all gold, collect recall/precision/latency
# echoes JSONL row.
run_tier() {
  local tier="$1" label="$2"
  local passed=0 hitsum=0 emitsum=0
  local -a lats=()
  local i
  for i in $(seq 0 $((N-1))); do
    local t0 t1
    t0="$(now_ms)"
    read -r p h e < <(score_one "${DIRS[$i]}" "${WANTS[$i]}" "$tier")
    t1="$(now_ms)"
    lats+=("$((t1-t0))")
    passed=$((passed + p))
    hitsum=$((hitsum + h))
    emitsum=$((emitsum + e))
  done
  # recall / precision
  local recall precision
  recall="$(awk -v a="$passed" -v b="$N" 'BEGIN{printf "%.3f", (b?a/b:0)}')"
  precision="$(awk -v a="$hitsum" -v b="$emitsum" 'BEGIN{printf "%.3f", (b?a/b:0)}')"
  # p50 / p95
  local p50 p95
  p50="$(printf '%s\n' "${lats[@]}" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')"
  p95="$(printf '%s\n' "${lats[@]}" | sort -n | awk '{a[NR]=$1} END{i=int(NR*0.95); if(i<1)i=1; print a[i]}')"
  local solosum=0; for l in "${lats[@]}"; do solosum=$((solosum+l)); done

  # ---- fan-out: run ALL directions concurrently, measure wall --------------
  local fk="$FANOUT" fwall=0 speedup="null"
  if [ "$N" -gt 1 ]; then
    local fj; fj="$(mktemp)"
    for i in $(seq 0 $((N-1))); do printf '%s\t%s\n' "${DIRS[$i]}" "${WANTS[$i]}"; done > "$fj"
    local ft0 ft1
    export HERE ROOT TOP tier
    ft0="$(now_ms)"
    # each line -> one prg-seed run; -P fk gives width-fk concurrency.
    # we only need WALL time here, so discard output.
    if [ "$tier" = "--no-model" ]; then
      cut -f1 "$fj" | xargs -d '\n' -I{} -P "$fk" \
        bash -c '"$HERE/prg-seed.sh" "$1" --no-model --root "$ROOT" --top "$TOP" >/dev/null 2>&1 || true' _ {} || true
    else
      cut -f1 "$fj" | xargs -d '\n' -I{} -P "$fk" \
        bash -c '"$HERE/prg-seed.sh" "$1" --root "$ROOT" --top "$TOP" --model "'"$tier"'" >/dev/null 2>&1 || true' _ {} || true
    fi
    ft1="$(now_ms)"
    fwall=$((ft1-ft0))
    rm -f "$fj"
    speedup="$(awk -v s="$solosum" -v w="$fwall" 'BEGIN{printf "%.2f", (w?s/w:0)}')"
  fi

  jq -cn \
    --arg model "$label" --arg tier "$( [ "$tier" = "--no-model" ] && echo tool || echo model )" \
    --argjson n "$N" --argjson recall "$recall" --argjson precision "$precision" \
    --argjson p50 "$p50" --argjson p95 "$p95" \
    --argjson fk "$fk" --argjson fwall "$fwall" \
    --argjson speedup "$speedup" \
    '{model:$model,tier:$tier,n:$n,recall:$recall,precision:$precision,
      p50_ms:$p50,p95_ms:$p95,fanout_k:$fk,fanout_wall_ms:$fwall,
      fanout_speedup:$speedup}'
}

# ---- drive all tiers, collect JSONL ----------------------------------------
ROWS_JSONL=""
add_row() { ROWS_JSONL="${ROWS_JSONL}${ROWS_JSONL:+$'\n'}$1"; }

if [ "$INCLUDE_BASELINE" = 1 ]; then
  add_row "$(run_tier --no-model 'tool(--no-model)')"
fi
if [ "$NO_MODEL_ONLY" = 0 ]; then
  for m in $MODELS; do
    add_row "$(run_tier "$m" "$m")"
  done
fi

# ---- output ----------------------------------------------------------------
if [ "$PRETTY" = 1 ]; then
  {
    printf 'model\ttier\tn\trecall\tprec\tp50ms\tp95ms\tfanK\tfanWall\tspeedup\n'
    printf '%s\n' "$ROWS_JSONL" | jq -r \
      '[.model,.tier,.n,.recall,.precision,.p50_ms,.p95_ms,.fanout_k,.fanout_wall_ms,.fanout_speedup]|@tsv'
  } | column -t -s $'\t'
else
  printf '%s\n' "$ROWS_JSONL"
fi
