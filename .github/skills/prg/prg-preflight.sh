#!/usr/bin/env bash
# prg-preflight.sh -- the PREFLIGHT BUNDLE: what a model gets BEFORE it
# writes SQL against a bin2md-emitted corpus.  Plan 06 item 3.2.
#
# WHY THIS EXISTS.  Measured on this corpus: building the db is ~1.05 s and a
# query is ~2 ms, while an LLM round trip is seconds to tens of seconds.  The
# machine time is already free; the only expensive thing left is the model's
# ATTEMPTS.  So it is worth spending real local work to make the FIRST query
# correct.
#
# WHAT GOES IN, and each line of it is a measured lever, not a preference
# (see fix.archive/text2sql-methodology.md):
#   - the WHOLE per-case schema as CREATE TABLE, never pruned.  Structured
#     schema crushes no-schema (8.3 -> 59.9 EX), but no serialization
#     dominates (spread ~1-3 pts, model-dependent), and at our scale
#     (10-50 tables) pruning measurably HURTS.  So: ship it all, cheaply.
#   - the REAL header beside every sanitized name.  This is the single
#     largest lever in the literature (+11 to +20 EX): it is the column
#     "description", and we get it for free because the sanitizer threw the
#     information away.  "fuel" means nothing; "Fuel %" means a percentage.
#   - 3 sample values per column, COLUMN-WISE.  Both numbers are measured:
#     the count is an inverted U peaking at 3 (0 rows 59.9 / 1 row 64.8 /
#     3 rows 67.0 / 5 rows 65.3 / 10 rows 63.3), and the REPRESENTATION
#     FLIPS THE SIGN -- the same 3 values shown as INSERT INTO statements
#     HURT (-1.2) while column-wise HELPED (+2.6).  The format is part of
#     the finding, not a detail.
#   - the SHAPE verdict for join key candidates (item 3.1), which is the
#     part no paper has: it targets schema linking, 37-42% of all failures,
#     versus <=3% for un-executable SQL.
#   - a SQLite dialect block, including the one rule that is ours alone:
#     EVERY COLUMN IS TEXT ON PURPOSE, so every numeric or date comparison
#     needs a CAST, and unCAST TEXT sorts lexically ('500' < '9').
#
# WHAT DELIBERATELY STAYS OUT: any schema pruner.  It would be work spent to
# make results worse at this corpus size.
#
# NAMES COME FROM THE DDL, NOT FROM A REIMPLEMENTED SANITIZER.  insert.prg.sql
# is what sqlite will actually see, including uniq()'s _2/_3 disambiguation
# for duplicate headers, which cannot be derived from one column in isolation.
# Verified on the freight corpus: DDL and schema.prg.json align positionally,
# 24/24 tables with zero column-count mismatches.
#
# usage: prg-preflight.sh <folder> [--shapes FILE] [--samples N] [--out FILE]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { printf '%s\n' "$*" >&2; exit 2; }

DIR=""; SHAPES=""; NSAMP=3; OUT="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --shapes)  SHAPES="$2"; shift 2 ;;
    --samples) NSAMP="$2";  shift 2 ;;
    --out)     OUT="$2";    shift 2 ;;
    -h|--help) sed -n '2,44p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)  DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] || die "usage: prg-preflight.sh <folder> [--shapes FILE] [--samples N]"
[ -d "$DIR" ] || die "not a directory: $DIR"
[ -f "$DIR/schema.prg.json" ] || die "no schema.prg.json in $DIR (run --emit-ddl first)"
[ -f "$DIR/insert.prg.sql" ]  || die "no insert.prg.sql in $DIR (run --emit-ddl first)"

# Shapes are OPTIONAL but strongly wanted: without them the bundle cannot
# warn about the zero-row join.  Compute if not supplied.
if [ -z "$SHAPES" ]; then
  SHAPES="$(mktemp)"; trap 'rm -f "$SHAPES"' EXIT
  "$HERE/prg-join.sh" shapes "$DIR" > "$SHAPES" 2>/dev/null || : 
fi

python3 "$HERE/prg-preflight.py" \
  --dir "$DIR" --shapes "$SHAPES" --samples "$NSAMP" --out "$OUT"
