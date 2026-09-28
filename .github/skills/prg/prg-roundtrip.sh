#!/usr/bin/env bash
# prg-roundtrip.sh — ONE worked round trip, end to end:
#   question -> SQL -> answer -> address -> the cell it came from.
# NO LLM.  Plan 07, item A.4.
#
# Deliberately ONE case, not a framework.  prg-addr.sh check already
# validates the lookup side (22 ok / 0 mismatch / 4,767 rows); what
# nothing tested before this is the JOIN between a QUERY RESULT and an
# address.  A general write-back layer built before a single round trip
# is proven would be a layer over an unproven join.
#
# THE WORKED CASE
#   Q: which carrier has the highest minimum charge?
#   SQL answer:        rowid=4, FedEx Freight, $129.00
#   address lookup:    (Award Summary, ord=4, col=7) -> G9
#   workbook says:     G9 = "$129.00"                 <- agrees
#
# Three independent sources agree on the value, so the address is
# right.  The check is only meaningful because a WRONG address would
# still look fine:
#
#   hdr_row(3) + rowid(4) = G7 = "$112.50"
#
# G7 is a real currency value on a real carrier row.  Writing there
# succeeds, corrupts a different carrier's rate, and raises nothing.
# That is why this test asserts the value MATCHES rather than merely
# that an address was produced.
#
# EXIT 0 round trip closes   1 mismatch   2 usage/missing corpus
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
corpus=${1:-}
db=${2:-}
[ -n "$corpus" ] && [ -d "$corpus" ] && [ -n "$db" ] && [ -f "$db" ] || {
	echo "usage: prg-roundtrip.sh CORPUS_DIR DB" >&2
	exit 2
}

sqlite=${SQLITE3:-/app/officepy/bin/sqlite3}
command -v "$sqlite" >/dev/null 2>&1 || sqlite=sqlite3
command -v "$sqlite" >/dev/null 2>&1 || {
	echo "prg-roundtrip: no sqlite3" >&2
	exit 2
}

TBL=_2024_ltl_bid_award_final_v2_jt_copy_xlsx_award_summary
SHEET="Award Summary"
COL=7 # min_charge, 1-based within the sheet

echo "Q: which carrier has the highest minimum charge?"

# 1. SQL.  rowid is carried because it is the only handle the result has
#    on where the row came from.
ans=$("$sqlite" "$db" "select rowid || '|' || carrier || '|' || min_charge
      from $TBL
      order by cast(replace(replace(min_charge,'\$',''),',','') as real) desc
      limit 1")
ord=${ans%%|*}
rest=${ans#*|}
carrier=${rest%%|*}
val=${rest#*|}
echo "   SQL      -> ord=$ord  $carrier  $val"

# 2. Address, looked up -- never computed.
cell=$("$here/prg-addr.sh" cell "$corpus" --sheet "$SHEET" --ord "$ord" --col "$COL")
a=$(printf '%s' "$cell" | python3 -c 'import json,sys;print(json.load(sys.stdin)["a"])')
echo "   address  -> $a"

# 3. Independent check against the workbook stream itself.
wb=$(python3 - "$corpus" "$SHEET" "$a" <<'PY'
import glob, json, os, sys
corpus, sheet, addr = sys.argv[1], sys.argv[2], sys.argv[3]
for p in glob.glob(os.path.join(corpus, "*.xlsx.prg.jsonl")):
    with open(p, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("k") == "cell" and d.get("a") == addr and d.get("s") == sheet:
                print(d.get("v", ""))
                sys.exit(0)
print("")
PY
)
echo "   workbook -> $a = ${wb:-<not found>}"

if [ "$wb" != "$val" ]; then
	echo "FAIL: query said '$val' but $a holds '${wb:-<nothing>}'" >&2
	exit 1
fi

# The counter-example, printed every run so the pass is not mistaken for
# "any address would have worked".
hdr=3
bad="G$((hdr + ord))"
badv=$(python3 - "$corpus" "$SHEET" "$bad" <<'PY'
import glob, json, os, sys
corpus, sheet, addr = sys.argv[1], sys.argv[2], sys.argv[3]
for p in glob.glob(os.path.join(corpus, "*.xlsx.prg.jsonl")):
    with open(p, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("k") == "cell" and d.get("a") == addr and d.get("s") == sheet:
                print(d.get("v", ""))
                sys.exit(0)
print("")
PY
)
echo
echo "ok: round trip closes -- $a holds exactly what the query returned"
echo "    counter-example: hdr_row($hdr)+ord($ord) = $bad = ${badv:-<empty>}"
echo "    a real value on a different carrier's row; that write would"
echo "    have succeeded and corrupted silently"
