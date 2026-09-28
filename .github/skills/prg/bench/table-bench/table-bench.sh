#!/usr/bin/env bash
# Per-rung table-discovery bench (plan 256, WI 8.6).
#
# WHY THIS EXISTS SEPARATELY FROM score.sh
#   score.sh answers "how good is this detector?" with three aggregate
#   numbers.  8.6 demands four metrics reported PER RUNG, "so a weak rung
#   is visible instead of being averaged away".  That is not a formatting
#   difference, it is a different measurement -- see below.
#
# ⭐ THE TRAP THIS SCRIPT EXISTS TO AVOID
#   The detector is a LADDER: it stops at the first rung that fires.  So
#   tagging each output with its rung and grouping does NOT measure the
#   rungs -- it measures which rung got there first.  In 8.5 that made R3
#   look like a total failure (0 hits) when in truth it had never been
#   TESTED: R1/R2 always fire first on a declared sheet.
#   Therefore each rung here is scored with ALL OTHER RUNGS DISABLED.
#   "R3 alone finds 63/146" is a fact about R3.  "R3 contributed 0 to the
#   ladder" is a fact about the ladder's ordering.  Only the first is a
#   measurement of the rung.
#
# ⭐ WHY RECALL ON R2 IS NOT A RESULT
#   The gold positives were derived from table/af declarations, and R2
#   reads those same declarations.  R2 cannot fail by construction.  Its
#   score is a restatement of the oracle and is labelled CIRCULAR in the
#   output so nobody quotes it as detector quality.
#
# Usage: ./table-bench.sh [path/to/silo-schema.jq]
# Exit:  0 scored · 2 bad args/env · 3 corpus integrity failure
set -uo pipefail
cd "$(dirname "$0")" || exit 2

JQF="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../jq" && pwd)/silo-schema.jq}"
[ -r "$JQF" ] || { echo "no lens: $JQF" >&2; exit 2; }
command -v jq >/dev/null   || { echo "jq required" >&2; exit 2; }
command -v silo >/dev/null || { echo "silo required on PATH" >&2; exit 2; }

for f in gold.positives.jsonl gold.negatives.jsonl MANIFEST.sha256; do
  [ -r "$f" ] || { echo "missing bench file: $f" >&2; exit 2; }
done

# --- corpus integrity: never score against a corpus that has drifted --------
bad=0; miss=0
while read -r sha _bytes rel; do
  case "$sha" in \#*|"") continue;; esac
  p="/workspace/datasets/$rel"
  if [ ! -f "$p" ]; then miss=$((miss+1)); continue; fi
  a=$(sha256sum "$p" | cut -d' ' -f1)
  [ "$a" = "$sha" ] || { echo "DRIFT: $rel" >&2; bad=$((bad+1)); }
done < MANIFEST.sha256
if [ "$bad" -gt 0 ] || [ "$miss" -gt 0 ]; then
  echo "corpus integrity FAILED (drift=$bad missing=$miss) — refusing to score" >&2
  exit 3
fi
echo "corpus integrity OK" >&2

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

jq -r '.path' gold.positives.jsonl gold.negatives.jsonl | sort -u > "$TMP/files.txt"
jq -c '{path,sheet,ref:(.ref|ascii_upcase)}' gold.positives.jsonl | sort -u > "$TMP/gold.txt"
jq -r '.path+"\t"+.sheet' gold.negatives.jsonl | sort -u > "$TMP/negkeys.txt"
GOLD=$(wc -l < "$TMP/gold.txt"); NEG=$(wc -l < "$TMP/negkeys.txt")

# Build an isolated variant of the lens with every rung but $1 disabled.
# The ladder selector lines are `if ($rN | length) > 0 then $rN`, so
# neutering the guard of the others forces the chosen rung to adjudicate.
mkvariant(){ # $1=keep rung (1..4|all) -> stdout
  local keep="$1" s; s=$(cat "$JQF")
  for r in 1 2 3 4; do
    [ "$keep" = "all" ] && break
    [ "$r" = "$keep" ] && continue
    s=$(printf '%s' "$s" \
        | sed -e "s/if   (\$r$r | length) > 0/if   (false)/" \
              -e "s/elif (\$r$r | length) > 0/elif (false)/")
  done
  printf '%s' "$s"
}

pct(){ [ "$2" -eq 0 ] && { echo "  n/a"; return; }
       awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f",a/b}'; }

printf '\n=== per-rung table-discovery bench (WI 8.6) ===\n'
printf 'positives %s rectangles · negatives %s table-free sheets\n\n' "$GOLD" "$NEG"
printf '| rung  | prec  | recall | exact-rect | FP(neg) | fired | note      |\n'
printf '|-------|-------|--------|------------|---------|-------|-----------|\n'

for keep in 1 2 3 4 all; do
  mkvariant "$keep" > "$TMP/v.jq"
  : > "$TMP/pred.jsonl"
  while read -r p; do
    { silo --dump-meta-json "$p"; silo --dump-json "$p"; } 2>/dev/null \
      | jq -s -c -f "$TMP/v.jq" --arg file "$p" 2>/dev/null \
      | jq -c --arg p "$p" 'select(type=="object" and .sheet!=null and .ref!=null)
                            |{path:$p,sheet:.sheet,ref:(.ref|ascii_upcase)}' \
      >> "$TMP/pred.jsonl" 2>/dev/null
  done < "$TMP/files.txt"
  sort -u "$TMP/pred.jsonl" > "$TMP/pred.txt"

  TP=$(comm -12 "$TMP/gold.txt" "$TMP/pred.txt" | wc -l)
  FIRED=$(wc -l < "$TMP/pred.txt")
  FP=$(jq -r '.path+"\t"+.sheet' "$TMP/pred.txt" 2>/dev/null | sort \
       | comm -12 - "$TMP/negkeys.txt" | wc -l)

  # PRECISION CAVEAT: a prediction on a POSITIVE sheet that misses the gold
  # rect may still be a real undeclared table (RUBRIC "Known limits").  So
  # precision here is a LOWER BOUND, not a verdict. Denominator = all fired.
  case "$keep" in
    1) note="independent";;
    2) note="CIRCULAR  ";;
    3) note="shape     ";;
    4) note="shape     ";;
    all) note="ladder    ";;
  esac
  printf '| %-5s | %s | %s  | %s      | %7s | %5s | %s |\n' \
    "$( [ "$keep" = all ] && echo "R1-4" || echo "R$keep" )" \
    "$(pct "$TP" "$FIRED")" "$(pct "$TP" "$GOLD")" "$(pct "$TP" "$GOLD")" \
    "$FP" "$FIRED" "$note"
done

cat <<'EOF'

READ THIS BEFORE QUOTING ANY ROW:
 · R2 is CIRCULAR — gold was derived from the same table/af declarations
   R2 reads, so it cannot fail. Not a measure of detector quality.
 · Each rung above was scored with the OTHER rungs DISABLED. A rung's
   contribution to the full ladder is smaller, because the ladder stops
   at the first rung that fires.
 · precision is a LOWER BOUND: a prediction on a positive sheet that is
   not the declared rect may still be a real undeclared table.
 · exact-rect == recall here: a hit is only counted on an EXACT ref
   match, so there is no partial credit to distinguish the two.
EOF
