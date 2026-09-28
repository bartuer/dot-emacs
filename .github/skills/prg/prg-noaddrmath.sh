#!/usr/bin/env bash
# prg-noaddrmath.sh — fail if any A1 address was COMPUTED rather than
# read verbatim from the silo.  NO LLM.  Plan 07, item A.2.
#
# WHY THIS EXISTS
# The wrong answer is one obvious line away and nothing else catches it.
# The DDL comment publishes `hdr_row`, `rowid` survives every query, so
#
#     a1_row = hdr_row + rowid
#
# is trivially available and produces a VALID CELL REFERENCE EVERY TIME.
# That is the whole problem: a computed address does not fail, it
# succeeds at the wrong cell.  A write lands on the wrong carrier's row
# and no error is raised anywhere.
#
# MEASURED on `Award Summary` (hdr_row=3), predicted vs the address the
# silo actually reports:
#
#     ord    1  2  3  4  5  6  7   8
#     pred   4  5  6  7  8  9 10  11
#     real   6  7  8  9 10 11 12  15      8 of 8 WRONG
#
# Note ord=8: the sheet jumps 12 -> 15.  A gap like that cannot be
# modelled by any offset, so this is not fixable by choosing a better
# constant.  Corpus-wide the same arithmetic is wrong on 20 of 24
# sheets (83%); the COLUMN recovers perfectly (0/976) and it is the ROW
# that breaks (964/976).
#
# WHAT IT CHECKS
#   --sheet S   for every data row of S, compare the silo's real address
#               against hdr_row+ord.  Reports how many rows the
#               arithmetic would place wrongly.  This is the EVIDENCE
#               mode: it proves the trap is live on this corpus.
#   --source    grep the tree for address arithmetic in code.  This is
#               the REGRESSION mode: it fails if someone reintroduces
#               the shortcut.
#
# A note on what "pass" means in --sheet mode: a sheet where the
# arithmetic HAPPENS to agree is not evidence the arithmetic is sound.
# MEASURED by running this tool over every distinct sheet name in the
# corpus: 3 AGREE, 10 MISPLACED, 5 have no data rows (18 sheet names
# behind 24 tables).  The 3 agree only because their header sits
# directly above contiguous data -- a property of those sheets, not of
# the method.  The tool therefore reports agreement as COINCIDENCE,
# never as validation.
#
# EXIT 0 no computed address found   1 arithmetic would misplace rows
#      2 usage
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
mode=${1:-}

case "$mode" in
--source)
	# Regression guard.  Looks for the shortcut in C and shell.
	root=${2:-$(cd "$here/../../.." && pwd)}
	# Match ONLY hdr_row combined with a PER-ROW ORDINAL (rowid/ord/
	# ordinal).  Deliberately NOT `hdr_row + rows`: that is a stream
	# EXTENT (a count of rows, used by emitsql.c:604 to clamp trailing
	# junk) and is legitimate.  An earlier revision of this gate matched
	# `hdr_row +` generally and fired on that clamp plus a help string
	# -- two false positives out of two hits.  A gate that cries wolf
	# gets switched off, so the pattern is narrowed to the actual trap:
	# turning an ordinal into an A1 ROW.
	hits=$(grep -rnE 'hdr_row[[:space:]]*\+[[:space:]]*(rowid|ord\b|ordinal)|(rowid|ord\b|ordinal)[[:space:]]*\+[[:space:]]*hdr_row' \
		"$root/src" "$root/.github/skills/prg" 2>/dev/null |
		grep -v 'prg-noaddrmath.sh' |
		# Drop comment lines.  prg-addr.sh's own header WARNS about
		# `hdr_row + rowid` in prose; flagging the documentation of a
		# trap as an instance of it would be exactly backwards.  Only
		# the leading token is inspected, so code with a trailing
		# comment still gets caught.
		grep -vE ':[0-9]+:[[:space:]]*(#|\*|/\*|//|--)' || true)
	if [ -n "$hits" ]; then
		echo "FAIL: address arithmetic found in source" >&2
		printf '%s\n' "$hits" >&2
		exit 1
	fi
	echo "ok: no hdr_row+ord arithmetic in src/ or prg/"
	exit 0
	;;
--sheet)
	sheet=${2:-}
	corpus=${3:-}
	[ -n "$sheet" ] && [ -n "$corpus" ] || {
		echo "usage: prg-noaddrmath.sh --sheet SHEET CORPUS" >&2
		exit 2
	}
	;;
*)
	echo "usage: prg-noaddrmath.sh --sheet SHEET CORPUS" >&2
	echo "       prg-noaddrmath.sh --source [REPO_ROOT]" >&2
	exit 2
	;;
esac

"$here/prg-addr.sh" rows "$corpus" --sheet "$sheet" 2>/dev/null |
	python3 -c '
import json, sys, re

rows = [json.loads(l) for l in sys.stdin if l.strip()]
if not rows:
    sys.stderr.write("prg-noaddrmath: no rows for that sheet\n")
    sys.exit(2)

# Recover hdr_row the way a naive consumer would: the DDL publishes it,
# and r is the stream row.  hdr = r - ord for the first data row.
hdr = rows[0]["r"] - rows[0]["ord"]
bad = []
for d in rows:
    a = d["cells"][0]["a"]
    real = int(re.sub(r"[^0-9]", "", a))
    pred = hdr + d["ord"]
    if pred != real:
        bad.append((d["ord"], pred, real))

print("sheet rows: %d   inferred hdr_row: %d" % (len(rows), hdr))
if bad:
    print("MISPLACED by hdr_row+ord: %d/%d rows" % (len(bad), len(rows)))
    for o, p, r in bad[:8]:
        print("  ord=%-3d would write row %-4d actual row %d" % (o, p, r))
    print("every one of those is a VALID cell reference -- the write")
    print("succeeds, at the wrong row, with no error raised")
    sys.exit(1)
print("arithmetic AGREES on this sheet -- recorded as COINCIDENCE, not")
print("validation: it agrees only where the header sits directly above")
print("contiguous data, which is 3 of the 13 sheets that have data rows")
sys.exit(0)
'
