#!/usr/bin/env bash
# Score a table detector against the pinned bench.
#
# Usage: ./score.sh '<detector-cmd>'
#   The detector is invoked as: <detector-cmd> <xlsx-path>
#   It must emit JSONL on stdout, one object per detected rectangle:
#       {"sheet":"<name>","ref":"A1:D9"}
#   Extra keys are ignored. No output for a file == "no tables here".
#
# Exit: 0 scored ok · 2 bad args · 3 corpus integrity failure
set -uo pipefail
cd "$(dirname "$0")" || exit 2

DET="${1:-}"
[ -n "$DET" ] || { echo "usage: $0 '<detector-cmd>'" >&2; exit 2; }

for f in gold.positives.jsonl gold.negatives.jsonl MANIFEST.sha256; do
  [ -r "$f" ] || { echo "missing bench file: $f" >&2; exit 2; }
done
command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }

# --- corpus integrity: never score against a corpus that has drifted --------
# A bench whose inputs changed silently reports a number about nothing.
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
echo "corpus integrity OK ($(grep -vc '^#' MANIFEST.sha256) files)" >&2

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- run detector once per file, cache by path ------------------------------
jq -r '.path' gold.positives.jsonl gold.negatives.jsonl | sort -u > "$TMP/files.txt"
: > "$TMP/pred.jsonl"
while read -r p; do
  # shellcheck disable=SC2086
  $DET "$p" 2>/dev/null \
    | jq -c --arg p "$p" 'select(type=="object" and .sheet!=null and .ref!=null)
                          |{path:$p,sheet:.sheet,ref:(.ref|ascii_upcase)}' \
    >> "$TMP/pred.jsonl" 2>/dev/null
done < "$TMP/files.txt"

jq -c '{path,sheet,ref:(.ref|ascii_upcase)}' gold.positives.jsonl | sort -u > "$TMP/gold.txt"
sort -u "$TMP/pred.jsonl" > "$TMP/pred.txt"

TP=$(comm -12 "$TMP/gold.txt" "$TMP/pred.txt" | wc -l)
FN=$(comm -23 "$TMP/gold.txt" "$TMP/pred.txt" | wc -l)

# False positives are counted ONLY on negative sheets. On positive sheets an
# undeclared-but-real table would be scored as an error (see RUBRIC "Known
# limits"), so we do not punish the detector for it.
jq -r '.path+"\t"+.sheet' gold.negatives.jsonl | sort -u > "$TMP/negkeys.txt"
FP=$(jq -r '.path+"\t"+.sheet' "$TMP/pred.txt" 2>/dev/null | sort \
     | comm -12 - "$TMP/negkeys.txt" | wc -l)
NEG=$(wc -l < "$TMP/negkeys.txt")
CLEAN=$((NEG - $(jq -r '.path+"\t"+.sheet' "$TMP/pred.txt" 2>/dev/null | sort -u \
        | comm -12 - "$TMP/negkeys.txt" | wc -l)))

pct(){ [ "$2" -eq 0 ] && { echo "n/a"; return; }; awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f",a/b}'; }

cat <<EOF
=== table-discovery bench ===
corpus     SpreadsheetBench (pinned, case-level, input arm)
positives  $(wc -l < "$TMP/gold.txt") rectangles
negatives  $NEG table-free sheets (from $(jq -r .path gold.negatives.jsonl|sort -u|wc -l) files)

exact-ref recall     $TP/$((TP+FN))  = $(pct "$TP" $((TP+FN)))
negative-sheet clean $CLEAN/$NEG  = $(pct "$CLEAN" "$NEG")
spurious rects on negatives: $FP

note: recall is over DECLARED rectangles only; a detector that finds real
      undeclared tables is not credited here. See RUBRIC.md "Known limits".
EOF
