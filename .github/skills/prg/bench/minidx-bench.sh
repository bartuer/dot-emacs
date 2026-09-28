#!/usr/bin/env bash
# minidx-bench.sh — does prg-minidx.sh earn its keep over plain `rg`?
#
# The bench for prg-minidx.sh (plan 256 IDX-SLIM).  Per prg tool-authoring
# rule 3, it carries a NAIVE BASELINE arm: raw `rg -lF` over the bundles,
# which needs no index at all.  A tool never compared to plain rg cannot
# prove it is worth existing.
#
# Arms, one stratified symbol list, same machine:
#   RAW    rg -lF over the bundles          — no build, ground truth
#   IDX    rg -F over the slim tsv          — index, unrouted
#   TOOL   prg-minidx.sh find               — index + routing (the product)
#
# The headline is NOT speed.  It is whether ROUTING recovers the short-name
# recall that the bare index throws away, while keeping the long-name speed.
#
# Env: PRG_JS_CORPUS (required), MINIDX_BENCH_N (default 60).
# Exit: 0 ok · 2 bad deps · 4 corpus absent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../prg-minidx.sh"
CORPUS="${PRG_JS_CORPUS:-/workspace/research/wwwrootsdx}"
N="${MINIDX_BENCH_N:-60}"
PRETTY=0
[ "${1:-}" = "--pretty" ] && PRETTY=1

command -v rg >/dev/null || { echo "minidx-bench: ripgrep required" >&2; exit 2; }
[ -d "$CORPUS" ] || { echo "minidx-bench: corpus absent: $CORPUS" >&2; exit 4; }
[ -x "$TOOL" ] || { echo "minidx-bench: $TOOL not executable" >&2; exit 2; }

IDX="$CORPUS/_index/minidx.tsv"
[ -s "$IDX" ] || PRG_JS_CORPUS="$CORPUS" "$TOOL" build --corpus "$CORPUS" >/dev/null 2>&1 || true
[ -s "$IDX" ] || { echo "minidx-bench: could not build index" >&2; exit 4; }

NFILES=$(find "$CORPUS" -maxdepth 1 -name '*.js' | wc -l)
NBYTES=$(find "$CORPUS" -maxdepth 1 -name '*.js' -printf '%s\n' | awk '{s+=$1}END{print s+0}')

# ---- stratified sample.  -a is MANDATORY: ~20% of names carry binary
# payloads and plain grep would emit NOTHING, yielding a green empty run.
ALL=$(mktemp)
cut -f1 "$IDX" | LC_ALL=C grep -aE '^[A-Za-z_$][A-Za-z0-9_$.-]*$' | LC_ALL=C sort -u > "$ALL"
SYMS=$(mktemp)
per=$(( N / 3 )); [ "$per" -lt 1 ] && per=1
LC_ALL=C awk 'length($0)<=8'                  "$ALL" | shuf -n "$per" | sed 's/^/short\t/'  > "$SYMS"
LC_ALL=C awk 'length($0)>=9 && length($0)<=24' "$ALL" | shuf -n "$per" | sed 's/^/mid\t/'   >> "$SYMS"
LC_ALL=C awk 'length($0)>=25'                  "$ALL" | shuf -n "$per" | sed 's/^/long\t/'  >> "$SYMS"
NSYM=$(wc -l < "$SYMS")
[ "$NSYM" -lt 9 ] && { echo "minidx-bench: sample too small ($NSYM) — sampler broken, refusing to report" >&2; exit 5; }

ROWS=/tmp/minidx-bench.rows.tsv
: > "$ROWS"

BUNDLES=$(find "$CORPUS" -maxdepth 1 -name '*.js' | sort | tr '\n' ' ')

run_arm() {  # $1=arm $2=stratum $3=sym  -> emits row, prints file list to stdout
  local arm="$1" st="$2" s="$3" t0 t1 out
  t0=$(date +%s%N)
  case "$arm" in
    RAW)  out=$(LC_ALL=C rg -lF --no-messages -- "$s" $BUNDLES 2>/dev/null | xargs -r -n1 basename | LC_ALL=C sort -u) ;;
    IDX)  out=$(LC_ALL=C rg -aNF -- "$s" "$IDX" 2>/dev/null | awk -F'\t' -v x="$s" '$1==x{print $2}' | xargs -r -n1 basename | LC_ALL=C sort -u) ;;
    TOOL) out=$(PRG_JS_CORPUS="$CORPUS" "$TOOL" find "$s" --corpus "$CORPUS" 2>/dev/null | LC_ALL=C sort -u) ;;
  esac
  t1=$(date +%s%N)
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$s" "$arm" "$(( (t1-t0)/1000000 ))" "$(printf '%s' "$out" | grep -c . || true)" >> "$ROWS"
  printf '%s' "$out"
}

TMPD=$(mktemp -d)
while IFS=$'\t' read -r st s; do
  run_arm RAW  "$st" "$s" > "$TMPD/raw"
  run_arm IDX  "$st" "$s" > "$TMPD/idx"
  run_arm TOOL "$st" "$s" > "$TMPD/tool"
  for a in idx tool; do
    hit=$(LC_ALL=C comm -12 "$TMPD/raw" "$TMPD/$a" 2>/dev/null | grep -c . || true)
    ext=$(LC_ALL=C comm -13 "$TMPD/raw" "$TMPD/$a" 2>/dev/null | grep -c . || true)
    printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$s" "${a}_hit" "$hit" "$ext" >> "$ROWS"
  done
done < "$SYMS"

echo "# minidx-bench: $NFILES files, $NBYTES bytes (depth=1), $NSYM symbols stratified"
echo "# index: $(stat -c%s "$IDX") bytes = $(awk -v i="$(stat -c%s "$IDX")" -v c="$NBYTES" 'BEGIN{printf "%.1f%%",100*i/c}') of corpus"
echo "# recall measured against RAW (rg over real bytes = ground truth)"
echo

awk -F'\t' '
  $3=="RAW"||$3=="IDX"||$3=="TOOL" {n[$3]++; ms[$3]+=$4; ret[$3]+=$5}
  $3=="RAW" {base[$1]+=$5; tbase+=$5}
  $3=="idx_hit"  {ih[$1]+=$4; tih+=$4; ie+=$5}
  $3=="tool_hit" {th[$1]+=$4; tth+=$4; te+=$5}
  END{
    printf "%-6s %8s %8s %10s %8s %8s\n","arm","totms","avgms","returned","recall","falsepos";
    printf "%-6s %8d %8.1f %10d %8.3f %8d\n","RAW",ms["RAW"],ms["RAW"]/n["RAW"],ret["RAW"],1.0,0;
    printf "%-6s %8d %8.1f %10d %8.3f %8d\n","IDX",ms["IDX"],ms["IDX"]/n["IDX"],ret["IDX"],tih/tbase,ie;
    printf "%-6s %8d %8.1f %10d %8.3f %8d\n","TOOL",ms["TOOL"],ms["TOOL"]/n["TOOL"],ret["TOOL"],tth/tbase,te;
    printf "\n# recall by stratum — where routing pays for itself\n";
    printf "%-8s %8s %8s\n","stratum","IDX","TOOL";
    for(k in base) if(base[k]>0) printf "%-8s %8.3f %8.3f\n",k,ih[k]/base[k],th[k]/base[k];
  }' "$ROWS" | { if [ "$PRETTY" = 1 ]; then cat; else cat; fi; }

echo
echo "# rows: $ROWS"
rm -rf "$TMPD" "$ALL" "$SYMS"
