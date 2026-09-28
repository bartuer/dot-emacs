#!/usr/bin/env bash
# ckp1c.0 -- THE BOUNDARY CONTRACT GATE  (plan 253)
#
# THE CONTRACT, in one line:
#
#     sig:"boundary"  =>  the row HAS .s AND .ref
#
# Nothing is tagged unless it can honour that.  This is what makes the
# downstream one-liner
#
#     jq -c 'select(.sig=="boundary")|{s,ref}'
#
# correct ON FIRST WRITE, which is the entire point: the cost we are
# optimising is LLM round trips, not parse microseconds.  A consumer that
# has to discover by experiment that `frozen` rows carry no `.ref` has
# already cost more than every parse this tool will ever do.
#
# `conf` is the tier, NOT the truth:
#     conf 2 = DECLARED exact   (table, autoFilter -- the author wrote it)
#     conf 1 = HINT             (frozen -- measured 66.7% vs the oracle)
#
# WHY THIS SCRIPT EXISTS RATHER THAN THE ONE-LINER IN THE PLAN
# -----------------------------------------------------------
# The plan originally specified the gate as:
#
#     silo --dump-meta-json "$F" \
#       | jq -e 'select(.sig=="boundary")|select(.s==null or .ref==null)' \
#       && echo FAIL && exit 1
#
# Measured 2026-08-25: that gate PASSES on a silo that implements NONE of
# this, and PASSES on a crash.  Two independent holes:
#
#   1. VACUITY.  `jq -e` exits 4 when nothing is selected.  "no violating
#      rows" and "no rows at all" are the same exit code.  A gate that
#      cannot tell an empty stream from a clean one is not a gate.
#      => this script asserts a MINIMUM boundary-row count first.
#
#   2. THE PIPE EATS THE EXIT CODE.  `silo | jq` reports jq's status, so
#      a segfaulting silo reads as green -- the repo's "never pipe a gate
#      you intend to trust" rule (copilot-instructions.md:314).
#      => this script runs silo UNPIPED to a temp file and checks it.
#
# USAGE
#     silo-boundary-contract.sh FILE...          # explicit files
#     silo-boundary-contract.sh -                # paths on stdin
# Exit 0 = contract holds AND was non-vacuously exercised.
set -uo pipefail

SILO="${SILO:-/workspace/research/silo/target/release/silo}"
MIN_ROWS="${MIN_ROWS:-1}"   # non-vacuity floor: how many boundary rows must exist

[ -x "$SILO" ] || { echo "FAIL: no silo binary at $SILO"; exit 1; }
command -v jq >/dev/null || { echo "FAIL: jq not on PATH"; exit 1; }

if [ "${1:-}" = "-" ]; then mapfile -t FILES; else FILES=("$@"); fi
[ "${#FILES[@]}" -gt 0 ] || { echo "FAIL: no input files"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
n_bound=0; n_bad=0; n_files=0; n_crash=0

for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    n_files=$((n_files + 1))

    # UNPIPED: silo's own exit code is readable here, not jq's.
    "$SILO" --dump-meta-json "$f" >"$TMP/m.jsonl" 2>"$TMP/err"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        n_crash=$((n_crash + 1))
        echo "CRASH rc=$rc  $f"
        head -2 "$TMP/err" | sed 's/^/      /'
        continue
    fi

    # Every row claiming the tag ...
    b=$(jq -c 'select(.sig=="boundary")' "$TMP/m.jsonl" | wc -l)
    # ... that cannot honour it.
    v=$(jq -c 'select(.sig=="boundary")|select(.s==null or .ref==null)' \
            "$TMP/m.jsonl")
    n_bound=$((n_bound + b))
    if [ -n "$v" ]; then
        n_bad=$((n_bad + $(printf '%s\n' "$v" | wc -l)))
        echo "VIOLATION  $f"
        printf '%s\n' "$v" | head -3 | sed 's/^/      /'
    fi
done

echo "----"
echo "files=$n_files  boundary_rows=$n_bound  violations=$n_bad  crashes=$n_crash"

[ "$n_crash" -eq 0 ] || { echo "FAIL: silo exited non-zero on $n_crash file(s)"; exit 1; }
[ "$n_bad"   -eq 0 ] || { echo "FAIL: $n_bad row(s) tagged boundary without .s/.ref"; exit 1; }
# The check the plan's one-liner could not make.
[ "$n_bound" -ge "$MIN_ROWS" ] || {
    echo "FAIL: VACUOUS -- only $n_bound boundary rows (need >= $MIN_ROWS)."
    echo "      Zero violations is meaningless if nothing was tagged."
    exit 1; }

echo "PASS: contract holds over $n_bound boundary rows"
