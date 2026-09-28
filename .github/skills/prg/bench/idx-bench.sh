#!/usr/bin/env bash
# idx-bench.sh - does a symbol index beat plain rg on minified JS?
#
# Four arms over the SAME stratified symbol list:
#   A  rg -F prefilter on bundle-index.jsonl, then jq the hits
#   B  jq alone over the 14MB jsonl (no prefilter)
#   C  rg -lF over the raw bundles          <- NO-INDEX BASELINE (truth)
#   D  _index/symbols.json via jq            (committed 1.9MB projection)
#
# Recall is measured against C, which is ground truth by construction:
# C greps the actual bytes, so any file it finds really contains the token.
# An arm that is fast but misses files is WORSE than a slow complete one.
set -uo pipefail

CORPUS="${IDX_BENCH_CORPUS:-/workspace/research/wwwrootsdx}"
JSONL="${IDX_BENCH_JSONL:-/tmp/bundle-index.jsonl}"
SYMJSON="$CORPUS/_index/symbols.json"
N="${IDX_BENCH_N:-60}"
PRETTY=0; [ "${1:-}" = "--pretty" ] && PRETTY=1

for t in rg jq; do command -v "$t" >/dev/null || { echo "MISSING: $t" >&2; exit 2; }; done
[ -d "$CORPUS" ] || { echo "corpus absent: $CORPUS" >&2; exit 4; }
[ -f "$JSONL" ]  || { echo "index absent: $JSONL (regenerate; /tmp is volatile)" >&2; exit 4; }
[ -f "$SYMJSON" ]|| { echo "projection absent: $SYMJSON" >&2; exit 4; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# depth=1 only: midgard/ is out of the index's declared corpus, so
# including it would charge arm C with files the index never claimed.
find "$CORPUS" -maxdepth 1 -name '*.js' -type f | sort > "$WORK/files.txt"
NFILES=$(wc -l < "$WORK/files.txt")
NBYTES=$(xargs -a "$WORK/files.txt" -d '\n' stat -c %s 2>/dev/null | awk '{s+=$1} END{print s+0}')

# ---- stratified sampling -------------------------------------------------
# A flat shuf is dominated by long distinctive names and hides the generic
# -token failure mode entirely.  Three strata, sampled independently.
half=$((N/3))
# Restrict to clean ASCII identifiers: the raw name column carries
# binary/unicode string payloads (11290 of 55182) which make grep bail
# with "binary file matches" and silently yield an EMPTY sample.
jq -rc 'select(.name!=null and .file!=null and (.file|test("/")|not)) | .name' "$JSONL" \
  | LC_ALL=C grep -aE '^[A-Za-z_$][A-Za-z0-9_$.-]*$' \
  | sort -u > "$WORK/allnames.txt"

LC_ALL=C grep -aE '^.{1,8}$'  "$WORK/allnames.txt" | shuf -n "$half" > "$WORK/s_short.txt"
LC_ALL=C grep -aE '^.{9,24}$' "$WORK/allnames.txt" | shuf -n "$half" > "$WORK/s_mid.txt"
LC_ALL=C grep -aE '^.{25,}$'  "$WORK/allnames.txt" | shuf -n "$half" > "$WORK/s_long.txt"
awk '{print "short\t"$0}' "$WORK/s_short.txt"  > "$WORK/syms.tsv"
awk '{print "mid\t"$0}'   "$WORK/s_mid.txt"   >> "$WORK/syms.tsv"
awk '{print "long\t"$0}'  "$WORK/s_long.txt"  >> "$WORK/syms.tsv"
NSYM=$(wc -l < "$WORK/syms.tsv")

now_ms(){ date +%s%3N; }

: > "$WORK/rows.tsv"
while IFS=$'\t' read -r stratum sym; do
  [ -z "$sym" ] && continue

  t0=$(now_ms)
  rg -F "\"name\":\"$sym\"" "$JSONL" 2>/dev/null | jq -r '.file' | sort -u > "$WORK/a.out"
  a_ms=$(( $(now_ms) - t0 ))

  t0=$(now_ms)
  jq -rc --arg s "$sym" 'select(.name==$s)|.file' "$JSONL" 2>/dev/null | sort -u > "$WORK/b.out"
  b_ms=$(( $(now_ms) - t0 ))

  t0=$(now_ms)
  xargs -a "$WORK/files.txt" -d '\n' rg -lF -- "$sym" 2>/dev/null \
    | xargs -r -n1 basename | sort -u > "$WORK/c.out"
  c_ms=$(( $(now_ms) - t0 ))

  t0=$(now_ms)
  jq -r --arg s "$sym" '.symbols[$s] // {} | keys[]' "$SYMJSON" 2>/dev/null | sort -u > "$WORK/d.out"
  d_ms=$(( $(now_ms) - t0 ))

  # normalise every arm to bare basenames so set-compare is meaningful
  for f in a b c d; do
    sed 's|.*/||' "$WORK/$f.out" | sort -u > "$WORK/$f.n"; done

  c_n=$(wc -l < "$WORK/c.n")
  for arm in a b d; do
    n=$(wc -l < "$WORK/$arm.n")
    hit=$(comm -12 "$WORK/$arm.n" "$WORK/c.n" | grep -c . || true)
    extra=$(comm -23 "$WORK/$arm.n" "$WORK/c.n" | grep -c . || true)
    case $arm in a) ms=$a_ms;; b) ms=$b_ms;; d) ms=$d_ms;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$stratum" "$sym" "${arm^^}" "$ms" "$n" "$hit" "$extra" >> "$WORK/rows.tsv"
  done
  printf '%s\t%s\tC\t%s\t%s\t%s\t0\n' \
    "$stratum" "$sym" "$c_ms" "$c_n" "$c_n" >> "$WORK/rows.tsv"
done < "$WORK/syms.tsv"

cp "$WORK/rows.tsv" /tmp/idx-bench.rows.tsv

if [ "$PRETTY" = 1 ]; then
  echo "# idx-bench: $NFILES files, $NBYTES bytes (depth=1), $NSYM symbols stratified"
  echo "# recall measured against arm C (rg over raw bytes = ground truth)"
  echo
  awk -F'\t' '
    { ms[$3]=ms[$3]" "$4; tot[$3]+=$4; n[$3]++; ret[$3]+=$5; hit[$3]+=$6; ex[$3]+=$7; truth[$3]+=0 }
    $3=="C" { T+=$5 }
    END{
      printf "%-4s %8s %8s %9s %9s %8s\n","arm","totalms","avgms","returned","recall","falsepos"
      split("A B C D",o," ")
      for(i=1;i<=4;i++){k=o[i]; if(n[k]==0) continue
        printf "%-4s %8d %8.1f %9d %8.3f %8d\n", k, tot[k], tot[k]/n[k], ret[k], (T>0? hit[k]/T : 0), ex[k]}
    }' "$WORK/rows.tsv"
  echo
  echo "# recall by stratum (where the averages lie)"
  awk -F'\t' '
    $3=="C"{truth[$1]+=$5}
    $3!="C"{h[$1"|"$3]+=$6}
    END{ printf "%-8s %7s %7s %7s\n","stratum","A","B","D"
      split("short mid long",s," ")
      for(i=1;i<=3;i++){k=s[i]; if(truth[k]==0) continue
        printf "%-8s %7.3f %7.3f %7.3f\n",k,h[k"|A"]/truth[k],h[k"|B"]/truth[k],h[k"|D"]/truth[k]}
    }' "$WORK/rows.tsv"
  echo
  echo "# rows: /tmp/idx-bench.rows.tsv"
else
  cat "$WORK/rows.tsv"
fi
