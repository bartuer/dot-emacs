#!/usr/bin/env bash
# prg-seed.sh — turn a natural-language DIRECTION into a ranked SEED set.
#
# The R1 opener of the orchestration loop: given a question like
# "trace propagation across a process boundary", find the handful of real
# SYMBOLS in this repo that a dive should start from.  Two tiers:
#
#   tool tier (always runs, model-free):
#     - pull identifier-shaped tokens out of the direction
#     - for each, rg for DEF-ANCHORED hits (export function/const/class/... ,
#       function|const|class|def NAME, or `NAME: (async)(` ) across the repo
#     - RANK by def-hit count, but DOWN-WEIGHT vendored/generated noise
#       (node_modules, dist, *.d.ts) so a 2378x `context` in a .d.ts never
#       outranks the real seed.  This is the measured failure mode 5b fixes.
#     - emit ranked candidates: symbol <TAB> defhits <TAB> top_def_path:line
#
#   model tier (default ON; the ONLY model call, via prg-llm.sh):
#     - hand the direction + the ranked candidate list to prg-llm.sh and ask
#       it to return the seed symbols (subset, def-backed) as a plain list.
#     - if the proxy is unreachable (prg-llm.sh exit 3) DEGRADE to the tool
#       ranking automatically — the seed list is never empty just because the
#       model is down.
#
# --no-model returns the PURE-TOOL ranking (the baseline AND the fallback).
#
# Usage:
#   prg-seed.sh '<direction>' [--no-model] [--top N] [--root "modules .github"]
#               [--glob '*.ts'] [--model M] [--k 8]
#     --top N   candidates to consider / print (default 12)
#     --k   K   seeds to ask the model for (default 6)
#     --root    space-separated roots to search (default: repo, vendor excluded)
#     --glob    restrict rg to a glob (repeatable via comma)
#
# Output:
#   default    one seed symbol per line (model-picked; def-backed)
#   --no-model TSV: symbol <TAB> defhits <TAB> path:line   (ranked)
#
# Exit: 0 ok · 2 usage/dep · (model-down is NOT an error — falls back to tool)
set -euo pipefail

command -v rg >/dev/null || { echo "prg-seed: ripgrep (rg) required" >&2; exit 2; }
command -v jq >/dev/null || { echo "prg-seed: jq required"          >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"

DIRECTION=""
USE_MODEL=1
TOP=12
K=6
ROOTS=""
GLOBS=()
MODEL_ARG=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-model) USE_MODEL=0; shift ;;
    --top)      TOP="$2"; shift 2 ;;
    --k)        K="$2"; shift 2 ;;
    --root)     ROOTS="$2"; shift 2 ;;
    --glob)     IFS=',' read -ra _g <<< "$2"; GLOBS+=("${_g[@]}"); shift 2 ;;
    --model)    MODEL_ARG=(--model "$2"); shift 2 ;;
    -h|--help)  sed -n '2,34p' "$0"; exit 0 ;;
    -*)         echo "prg-seed: unknown flag $1" >&2; exit 2 ;;
    *)          DIRECTION="${DIRECTION:+$DIRECTION }$1"; shift ;;
  esac
done
[ -n "$DIRECTION" ] || { echo "prg-seed: empty direction" >&2; exit 2; }

# ---- token extraction: identifier-shaped words from the direction ----------
# keep camelCase / snake_case / dotted words >=3 chars; drop pure stopwords.
STOP=" the a an of to in on at for and or by across into from with is are be this that it its as via when where how what which "
mapfile -t TOKENS < <(
  printf '%s\n' "$DIRECTION" \
  | tr 'A-Z' 'a-z' \
  | grep -oE '[a-z][a-z0-9_.]{2,}' \
  | while read -r w; do case "$STOP" in *" $w "*) : ;; *) echo "$w" ;; esac; done \
  | sort -u
)
[ "${#TOKENS[@]}" -gt 0 ] || { echo "prg-seed: no seed-shaped tokens in direction" >&2; exit 2; }

# ---- rg roots / globs ------------------------------------------------------
RG_ARGS=(--no-heading --line-number -i)
RG_ARGS+=(-g '!**/node_modules/**' -g '!**/.git/**')   # hard-exclude .git
for g in "${GLOBS[@]}"; do RG_ARGS+=(-g "$g"); done
PATHS=()
if [ -n "$ROOTS" ]; then read -ra PATHS <<< "$ROOTS"; else PATHS=("."); fi

# A DEF whose NAME CONTAINS the token (substring, case-insensitive).  The
# direction says "propagation"; the real seed is `propagatePriorTurnFiles` —
# an exact-word match would miss it, so we match the token as a substring of
# the declared identifier and CAPTURE that identifier as the candidate symbol.
# One rg over all tokens (alternation), then awk extracts the real def name.
#
# PREFIX MUST BE OPTIONAL (0+), not a REQUIRED first char.  If it were
# `[A-Za-z_$][A-Za-z0-9_$]*` (1+), a token that matches the identifier from
# its very start (e.g. token `getactivetraceparent` vs `getActiveTraceparent`,
# or token `traceparent` when the ident IS `traceparent`) would leave nothing
# for the required first char to consume, and the whole def would fail to
# match.  `[A-Za-z0-9_$]*` (0+) matches the same defs a 1+ prefix would AND the
# start-anchored ones.  The `\s+` after the keyword already guarantees the name
# starts here, and valid identifiers never begin with a digit, so this is safe.
TOKALT="$(IFS='|'; echo "${TOKENS[*]}")"
DEFRE="(export\\s+(async\\s+)?)?(function|const|class|interface|type|enum|def)\\s+[A-Za-z0-9_\$]*(${TOKALT})[A-Za-z0-9_\$]*"

# ---- score each DISCOVERED symbol by DOWN-WEIGHTED def-hit count ------------
# weight: normal source = 1.0 ; dist/ = 0.2 ; *.d.ts = 0.1 (generated noise).
# The candidate is the DECLARED NAME (not the search token), so the seed list
# is real symbols the dive can start from.
# NOTE: the trailing `head` closes the pipe early; under `set -o pipefail`
# that makes rg/sort die with SIGPIPE (exit 141) and `set -e` would abort the
# whole script. Trap that ONE expected failure with `|| true` — the data is
# already captured; only the exit status needs swallowing.
RANK_TSV="$(
  rg "${RG_ARGS[@]}" --only-matching -e "$DEFRE" "${PATHS[@]}" 2>/dev/null \
    | awk -F: '
        { path=$1; line=$2
          # $3.. is the matched def text (may contain ":"), rejoin
          m=$3; for(i=4;i<=NF;i++) m=m":"$i
          # declared name = last identifier token in the match
          n=split(m, a, /[^A-Za-z0-9_$]+/); name=a[n]
          if (name=="") next
          w=1.0
          if (path ~ /\.d\.ts$/)      w=0.1
          else if (path ~ /\/dist\//) w=0.2
          sum[name]+=w
          if (!(name in best)) best[name]=path":"line
        }
        END { for (s in sum) printf "%s\t%.1f\t%s\n", s, sum[s], best[s] }
      ' \
    | sort -t$'\t' -k2,2 -nr | head -n "$TOP" || true
)"

if [ -z "$RANK_TSV" ]; then
  echo "prg-seed: no def-anchored candidates for: $DIRECTION" >&2
  exit 0
fi

# ---- tool-only mode: print the ranked TSV and stop -------------------------
if [ "$USE_MODEL" = 0 ]; then
  printf '%s\n' "$RANK_TSV"
  exit 0
fi

# ---- model tier: prg-llm.sh picks the seed subset --------------------------
CANDS="$(printf '%s\n' "$RANK_TSV" | awk -F'\t' '{printf "  %s  (defhits=%s, %s)\n",$1,$2,$3}')"
PROMPT="Direction: ${DIRECTION}

Candidate symbols (def-anchored, ranked by weighted def-hit count; vendored/
generated files already down-weighted):
${CANDS}

Pick the up to ${K} symbols that are the best SEEDS to start a code dive for
this direction. Return ONLY the chosen symbol names, one per line, no prose,
no numbering. Choose from the candidate list."

if SEEDS="$("$HERE/prg-llm.sh" "$PROMPT" "${MODEL_ARG[@]}" --max-tokens 200 2>/dev/null)"; then
  # keep only lines that are one of our candidate symbols (guard against prose).
  # grep exits 1 on no-match -> would abort under `set -e`; `|| true` swallows
  # that. If the model returned nothing usable, fall back to the tool ranking.
  PICKED="$(printf '%s\n' "$SEEDS" \
    | grep -oE '[A-Za-z_][A-Za-z0-9_.]+' \
    | grep -Fxf <(printf '%s\n' "$RANK_TSV" | cut -f1) \
    | awk 'NF && !seen[$0]++' || true)"
  if [ -n "$PICKED" ]; then
    printf '%s\n' "$PICKED"
  else
    echo "prg-seed: model returned no candidate-backed seed, using tool ranking" >&2
    printf '%s\n' "$RANK_TSV" | cut -f1
  fi
else
  # prg-llm.sh exit 3 (proxy down) or any failure -> degrade to tool ranking
  echo "prg-seed: model tier unavailable, falling back to tool ranking" >&2
  printf '%s\n' "$RANK_TSV" | cut -f1
fi
