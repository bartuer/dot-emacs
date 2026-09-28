#!/usr/bin/env bash
# prg-sameanswer.sh — the gate a typed column must pass before it is
# allowed to exist.  NO LLM.  Plan 07, item T.1.
#
# WHY THIS EXISTS
# The bin2md DDL is all-TEXT on purpose (src/emitsql.c:24).  Making it
# typed is worth 4.4x on a warm query, so there is real pressure to do
# it.  This tool is the thing that stops that pressure from quietly
# changing answers, because CAST IS NOT A FREE CONVERSION:
#
#   min_charge  '$118.00'  ->  CAST AS REAL  ->  0.0
#   discount    '72.5%'    ->  CAST AS REAL  ->  72.5
#
# Those two fail in OPPOSITE and both-bad ways.  The money case
# collapses every row to 0.0, which at least destroys the ordering
# visibly.  The percent case is far worse: 72.5 looks perfectly
# correct and IS correct as a display number, but any query that
# multiplies by it as a rate is off by 100x, and NOTHING in the result
# says so.  A gate that only checked "does it parse" would pass both.
#
# MEASURED on the freight corpus, distinct non-plain values:
#   percent-suffixed .... 7   e.g. award_summary.discount   '72.5%'
#   currency-prefixed ... 6   e.g. award_summary.min_charge '$118.00'
#
# And the reason this is not academic — the same ranking question,
# asked three ways, gives three different answers:
#   order by min_charge ................................. SAIA third
#   order by cast(min_charge as real) ................... ODFL third
#   order by cast(replace(min_charge,'$','') as real) ... SAIA third
# Only the third is right, and the middle one is what a naive "just
# type it" migration produces.
#
# THE RULE THIS ENFORCES
# A typed expression may replace a text expression ONLY IF it returns
# the same rows in the same order.  A difference is A DEFECT IN THE
# TYPING, never a tolerance to be accepted.  That framing is the whole
# point: it makes the typing prove itself against the text it replaces,
# rather than asking a human to eyeball two result sets.
#
# USAGE
#   prg-sameanswer.sh <db> <text-expr> <typed-expr> [--from TABLE]
#   prg-sameanswer.sh <db> --scan          audit every column for
#                                          CAST-hostile values
#
# EXIT  0 same answer (typing is safe)   1 diverged (typing is a defect)
#       2 usage
set -euo pipefail

SQLITE=${SQLITE:-/app/officepy/bin/sqlite3}
command -v "$SQLITE" >/dev/null 2>&1 || {
	# not on PATH in this environment; the absolute default is normal
	[ -x "$SQLITE" ] || { echo "prg-sameanswer: no sqlite3 at $SQLITE" >&2; exit 2; }
}

db=${1:-}
[ -n "$db" ] && [ -f "$db" ] || {
	echo "usage: prg-sameanswer.sh <db> <text-expr> <typed-expr> [--from T]" >&2
	echo "       prg-sameanswer.sh <db> --scan" >&2
	exit 2
}
shift

# ---- --scan : find the columns where typing would be dangerous -------
# Reported BEFORE anyone writes a typed view, so the risky columns are
# known rather than discovered by a wrong answer in production.
if [ "${1:-}" = "--scan" ]; then
	python3 - "$db" "$SQLITE" <<'PY'
import subprocess, sys, re
db, S = sys.argv[1], sys.argv[2]

def q(sql):
    r = subprocess.run([S, db, sql], capture_output=True, text=True)
    return r.stdout.strip().splitlines() if r.returncode == 0 else []

# A value is "plain" if CAST round-trips it losslessly.  Anything else
# is a place where typing changes meaning, so it is what we report.
plain = re.compile(r'^-?\d+(\.\d+)?$')
# Each pattern must anchor on the WHOLE value, not just find a symbol
# in it.  A first cut matched anything ending in '%' and reported the
# footnote "- CRST spot only, no tender accept %" as a percent; that is
# a true "do not type this column" but a FALSE REASON, and a wrong
# reason in a report is worse than no report.  Prose gets its own class.
klass = [
    ('money',  re.compile(r'^\(?[$€£]\s*-?[\d,]+(\.\d+)?\)?$')),
    ('pct',    re.compile(r'^-?[\d,]+(\.\d+)?\s*%$')),
    ('paren',  re.compile(r'^\([\d,]+(\.\d+)?\)$')),   # accounting negative
    ('comma',  re.compile(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$')),
    ('lead0',  re.compile(r'^0\d+$')),        # zip codes: NOT numbers
    # Free text in an otherwise-numeric column: a footnote parked in a
    # data cell.  Not convertible at all, and the reason typing this
    # column is unsafe is different from a formatting prefix.
    ('prose',  re.compile(r'[A-Za-z]{3,}.*\s.*[A-Za-z]')),
]
rows = 0
for t in q("select name from sqlite_master where type='table'"):
    for line in q("pragma table_info('%s')" % t):
        c = line.split('|')[1]
        seen = {}
        for v in q('select distinct "%s" from "%s" where "%s" is not null'
                   % (c, t, c)):
            if plain.match(v) or not v.strip():
                continue
            for name, p in klass:
                if p.search(v):
                    seen.setdefault(name, v)
        # 'prose' alone is not news -- most columns are text and always
        # will be.  It is only a finding when it CONTAMINATES a column
        # that is otherwise numeric, because that is the column someone
        # will try to type.  Report it only alongside a numeric class.
        if set(seen) == {'prose'}:
            seen = {}
        if seen:
            rows += 1
            print("%s.%s" % (t, c))
            for k, v in sorted(seen.items()):
                print("    %-6s %r" % (k, v))
if not rows:
    print("no CAST-hostile values found")
PY
	exit 0
fi

# ---- the gate itself -------------------------------------------------
text=${1:-}
typed=${2:-}
[ -n "$text" ] && [ -n "$typed" ] || {
	echo "usage: prg-sameanswer.sh <db> <text-expr> <typed-expr>" >&2
	exit 2
}

a=$("$SQLITE" "$db" "$text" 2>&1) || { echo "text query failed: $a" >&2; exit 1; }
b=$("$SQLITE" "$db" "$typed" 2>&1) || { echo "typed query failed: $b" >&2; exit 1; }

if [ "$a" = "$b" ]; then
	n=$(printf '%s\n' "$a" | grep -c . || true)
	echo "SAME  ($n rows) — typing is safe for this predicate"
	exit 0
fi
echo "DIVERGED — the typed form is a DEFECT, not a tolerance"
echo "--- text  ---"; printf '%s\n' "$a" | head -8
echo "--- typed ---"; printf '%s\n' "$b" | head -8
# A row-count difference is the loud case; same count with different
# values is the quiet one, so say which happened.
na=$(printf '%s\n' "$a" | grep -c . || true)
nb=$(printf '%s\n' "$b" | grep -c . || true)
[ "$na" = "$nb" ] &&
	echo "note: SAME row count ($na), different values — the quiet failure" ||
	echo "note: row count $na -> $nb"
exit 1
