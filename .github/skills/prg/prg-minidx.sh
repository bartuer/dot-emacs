#!/usr/bin/env bash
# prg-minidx.sh — locate a symbol in MINIFIED JS bundles.  NO LLM.
#
# The fifth prg SOURCE, beside repo / log / trace / corpus.  Its corpus is a
# directory of built (minified, webpack-style) .js bundles — the kind where
# every local is renamed to `e`/`t`/`n` and one file is 20MB on ONE line.
#
#   <corpus>/*.js            the bundles (depth=1; subdirs are NOT the corpus)
#   <corpus>/_index/minidx.tsv   name \t file   projection, deduped, sorted
#
# Set via --corpus or PRG_JS_CORPUS; no default, so an unset corpus exits 4
# rather than silently searching a wrong path.
#
# WHY THIS EXISTS AND PLAIN `rg` DOES NOT DO IT
# `rg -lF sym bundles/` is CORRECT — it reads the real bytes, so it is the
# ground truth and this tool falls back to it.  But it re-walks 22MB per
# lookup.  Measured on wwwrootsdx (136 files, 23,479,141 B), plan 256
# IDX-BENCH + IDX-SLIM:
#
#   raw rg -lF over the bundles ......... 33.4 ms/sym   recall 1.000
#   rg -F on jsonl + jq ................. 11.0 ms/sym   recall 0.966 (long)
#   rg -F on this tsv projection ........  4.9 ms/sym   recall 0.966 (long)
#
# ...but the index CANNOT see short names: recall 0.239 for names < 9 chars,
# because in minified code those are locals and string fragments the indexer
# never claimed to capture.  So the interesting part of this tool is not the
# speed — it is the ROUTING.  Short name -> raw rg.  Long name -> index.
# The caller should not have to know that rule; that is the whole point.
#
# COUNTER-MEASUREMENT, recorded so nobody "optimizes" it back:
# pruning short names from the index saves 2% of bytes (3,084,268 ->
# 3,004,965) and costs short-name recall (82 -> 75 files).  The 78% win
# comes from dropping OFFSETS and deduping to name->file, not from pruning.
# --prune-short exists, defaults OFF, and is a bad idea.
#
# TWO TRAPS HANDLED INSIDE THIS TOOL (do not re-discover them)
#  1. The upstream jsonl stores CHARACTER offsets and the bundles are
#     multibyte (968,369 bytes vs 966,653 chars in one file).  Byte-based
#     probes (dd/head -c) mismatch on every row and make a correct index
#     look broken.  This tool therefore does not traffic in offsets at all.
#  2. ~11,290 of 55,182 name rows carry binary payloads; plain `grep` says
#     "binary file matches" and yields NOTHING, so a sample silently comes
#     back empty and everything looks green.  All greps here are `-a`.
#
# Subverbs:
#   find <name> [--verify]   -> file  (one per line)  ROUTED, the default
#   raw  <name>              -> file  via rg -lF over bundles (ground truth)
#   build [--force]          -> (re)build _index/minidx.tsv
#   stat                     -> corpus + index size, row counts, staleness
#
# Exit: 0 ok · 2 bad args/deps · 4 corpus absent · 5 index unbuildable.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="${PRG_JS_CORPUS:-}"
SHORT_MAX="${PRG_MINIDX_SHORT:-8}"   # names <= this route to raw rg
PRUNE_SHORT=0
VERIFY=0
FORCE=0
PRETTY=0

command -v rg >/dev/null || { echo "prg-minidx: ripgrep required" >&2; exit 2; }

usage() { sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; }

VERB=""; TERM=""
while [ $# -gt 0 ]; do
  case "$1" in
    find|raw|build|stat) VERB="$1"; shift ;;
    --corpus) CORPUS="$2"; shift 2 ;;
    --short)  SHORT_MAX="$2"; shift 2 ;;
    --prune-short) PRUNE_SHORT=1; shift ;;
    --verify) VERIFY=1; shift ;;
    --force)  FORCE=1; shift ;;
    --pretty) PRETTY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) if [ -z "$TERM" ]; then TERM="$1"; else echo "prg-minidx: unexpected arg: $1" >&2; exit 2; fi; shift ;;
  esac
done

[ -n "$VERB" ] || { usage; exit 2; }
[ -n "$CORPUS" ] || { echo "prg-minidx: no corpus (use --corpus or PRG_JS_CORPUS)" >&2; exit 4; }
[ -d "$CORPUS" ] || { echo "prg-minidx: corpus absent: $CORPUS" >&2; exit 4; }

IDXDIR="$CORPUS/_index"
IDX="$IDXDIR/minidx.tsv"
SRC_JSONL="${PRG_MINIDX_JSONL:-/tmp/bundle-index.jsonl}"

bundles() { find "$CORPUS" -maxdepth 1 -type f -name '*.js' | sort; }

# The bundle list is walked ONCE per process, not once per lookup.  Measured:
# re-walking + a basename fork per hit made the tool SLOWER than the plain-rg
# baseline it exists to beat (40.8ms vs 34.4ms) — the index win was being
# spent on process overhead.  Keep this cached and keep basename out of loops.
_BUNDLE_LIST=""
bundle_list() { [ -n "$_BUNDLE_LIST" ] || _BUNDLE_LIST="$(bundles | tr '\n' ' ')"; printf '%s' "$_BUNDLE_LIST"; }

# ---- build ---------------------------------------------------------------
# Prefer projecting an existing bundle-index.jsonl (rich: strings + props).
# Fall back to a lexical identifier scan so the tool is never DEAD without
# the upstream builder — degraded recall, but it still works.
do_build() {
  mkdir -p "$IDXDIR"
  local tmp; tmp="$(mktemp)"
  local minlen=1; [ "$PRUNE_SHORT" = 1 ] && minlen=6

  if [ -f "$SRC_JSONL" ] && command -v jq >/dev/null; then
    jq -rc --argjson m "$minlen" \
      'select(.name!=null and (.name|length)>=$m) | [.name,.file] | @tsv' \
      "$SRC_JSONL" 2>/dev/null | LC_ALL=C sort -u > "$tmp" || true
  fi

  if [ ! -s "$tmp" ]; then
    echo "prg-minidx: no $SRC_JSONL — falling back to lexical scan" >&2
    local f b
    while read -r f; do
      b="$(basename "$f")"
      LC_ALL=C rg -oaN '[A-Za-z_$][A-Za-z0-9_$]{5,}' "$f" 2>/dev/null \
        | LC_ALL=C sort -u | awk -v b="$b" '{print $0"\t"b}'
    done < <(bundles) | LC_ALL=C sort -u > "$tmp" || true
  fi

  [ -s "$tmp" ] || { rm -f "$tmp"; echo "prg-minidx: index build produced nothing" >&2; exit 5; }
  mv "$tmp" "$IDX"
  echo "prg-minidx: built $IDX ($(wc -l < "$IDX") rows, $(stat -c%s "$IDX") bytes)" >&2
}

ensure_idx() { [ -s "$IDX" ] && [ "$FORCE" = 0 ] || do_build; }

# ---- lookups -------------------------------------------------------------
raw_find() {  # ground truth: real bytes
  # shellcheck disable=SC2046  # word-splitting the cached list is intended
  LC_ALL=C rg -lF --no-messages -- "$1" $(bundle_list) 2>/dev/null \
    | awk -F/ '{print $NF}' | LC_ALL=C sort -u
}

idx_find() {
  LC_ALL=C rg -aNF -- "$1" "$IDX" 2>/dev/null \
    | awk -F'\t' -v s="$1" '$1==s{n=split($2,p,"/"); print p[n]}' \
    | LC_ALL=C sort -u
}

case "$VERB" in
  build) FORCE=1; do_build ;;

  stat)
    n=$(bundles | wc -l)
    b=$(bundles | xargs -r stat -c%s 2>/dev/null | awk '{s+=$1}END{print s+0}')
    echo "corpus       $CORPUS"
    echo "bundles      $n files, $b bytes (depth=1)"
    if [ -s "$IDX" ]; then
      echo "index        $IDX"
      echo "index rows   $(wc -l < "$IDX")"
      echo "index bytes  $(stat -c%s "$IDX")"
      [ "$b" -gt 0 ] && echo "index ratio  $(awk -v i="$(stat -c%s "$IDX")" -v c="$b" 'BEGIN{printf "%.1f%% of corpus",100*i/c}')"
    else
      echo "index        ABSENT (run: $0 build --corpus $CORPUS)"
    fi
    ;;

  raw)
    [ -n "$TERM" ] || { echo "prg-minidx: raw needs a name" >&2; exit 2; }
    raw_find "$TERM"
    ;;

  find)
    [ -n "$TERM" ] || { echo "prg-minidx: find needs a name" >&2; exit 2; }
    # ROUTING: short names are invisible to the index (recall 0.239) -> raw.
    if [ "${#TERM}" -le "$SHORT_MAX" ] || [ "$VERIFY" = 1 ]; then
      [ "$PRETTY" = 1 ] && echo "# route: raw rg (name<=${SHORT_MAX} chars or --verify) — ground truth" >&2
      raw_find "$TERM"
    else
      ensure_idx
      out="$(idx_find "$TERM" || true)"
      if [ -z "$out" ]; then
        [ "$PRETTY" = 1 ] && echo "# route: index MISS -> falling back to raw rg" >&2
        raw_find "$TERM"
      else
        [ "$PRETTY" = 1 ] && echo "# route: index (${#TERM} chars)" >&2
        printf '%s\n' "$out"
      fi
    fi
    ;;
esac
