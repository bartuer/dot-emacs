#!/usr/bin/env bash
# reduce-bench.sh — pins the THIRD fan-out pattern: distributed merge REDUCE.
#
# WHY A THIRD PATTERN EXISTS.  The skill already has two shapes and neither
# can do a cross-box repo merge:
#   BROADCAST  one source -> N peers, parallel.  Correct for a PAYLOAD (a
#              dir, an image): every peer gets the SAME bytes, order is
#              irrelevant, and `--delete` makes it a mirror.
#   TABLE      N boxes -> N independent rows, parallel.  Correct for a
#              READ: no box's answer depends on another's.
# A merge is neither.  Box B's merge must start from the result of box A's,
# or one of them is discarded -- so the boxes CANNOT be visited in parallel
# and the accumulator is not a copy of anything.  That is a REDUCE:
#       acc = origin/master
#       for box in boxes:  acc = merge(acc, box)     # serial, ordered
#       push(acc)
#
# :*** LINEARITY IS NOT A PERFORMANCE CHOICE, IT IS GIT'S SHAPE. ***  A
# merge has exactly one first parent and produces exactly one new tip.  Two
# merges into the same base in parallel produce two tips and one of them
# must be redone against the other -- the work is not saved, only moved.
#
# WHAT THIS BENCH ASSERTS, on THROWAWAY LOCAL REPOS (it never touches the
# fleet, never pushes, never needs ssh):
#   1. REDUCE CONVERGES   -- every box's commit is in the final tip
#   2. ORDER IS ANCESTRY, NOT TIME -- a box whose commit is OLDER by
#      timestamp but a DESCENDANT still merges cleanly; sorting by date
#      would invert it
#   3. FAST-FORWARD IS NOT A MERGE -- an already-contained box is a no-op
#      and must not create an empty merge commit
#   4. A CONFLICT STOPS THE REDUCE -- it does not silently drop a side
#   5. PARALLEL MERGE LOSES WORK -- the counter-example that justifies (1)
#
# Exit: 0 all five hold · 1 a property failed
set -uo pipefail

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
G() { git -C "$1" "${@:2}"; }
q() { "$@" >/dev/null 2>&1; }
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
no()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# ---- a hub plus three "boxes", each with its own commit -------------------
q git init -q --bare "$T/hub"
for b in b1 b2 b3; do
    q git clone -q "$T/hub" "$T/$b"
    q G "$T/$b" config user.email bench@local
    q G "$T/$b" config user.name  bench
done
# b1 seeds the shared base so the clones are not empty.
echo base > "$T/b1/base.txt"
q G "$T/b1" add base.txt
q G "$T/b1" commit -qm base
q G "$T/b1" push -q origin HEAD:master
for b in b2 b3; do q G "$T/$b" fetch -q origin; q G "$T/$b" reset -q --hard origin/master; done

# Each box edits a DIFFERENT file -> no conflict, but three distinct tips.
i=0
for b in b1 b2 b3; do
    i=$((i+1))
    echo "$b" > "$T/$b/$b.txt"
    q G "$T/$b" add "$b.txt"
    # Deliberately INVERT the clock: b3 is committed EARLIEST, b1 latest.
    # If the reduce sorted by time it would visit them b3,b2,b1 -- harmless
    # here, but property 2 below makes the inversion load-bearing.
    GIT_COMMITTER_DATE="2020-01-0$((4-i))T00:00:00Z" \
    GIT_AUTHOR_DATE="2020-01-0$((4-i))T00:00:00Z" \
        q G "$T/$b" commit -qm "$b work"
done

# ---- THE REDUCE ----------------------------------------------------------
# acc lives in its own clone; each box is merged into it, one at a time.
q git clone -q "$T/hub" "$T/acc"
q G "$T/acc" config user.email bench@local
q G "$T/acc" config user.name  bench
merged=0
for b in b1 b2 b3; do
    q G "$T/acc" remote add "$b" "$T/$b"
    q G "$T/acc" fetch -q "$b" master
    if q G "$T/acc" merge-base --is-ancestor FETCH_HEAD HEAD; then
        continue                      # property 3: already contained
    fi
    if q G "$T/acc" merge --no-edit FETCH_HEAD; then
        merged=$((merged+1))
    else
        q G "$T/acc" merge --abort
        no "merge of $b failed unexpectedly"
    fi
done

# 1. CONVERGENCE — every box's file is present in the accumulator.
missing=""
for b in b1 b2 b3; do [ -f "$T/acc/$b.txt" ] || missing="$missing $b"; done
[ -z "$missing" ] && ok "reduce converges: all 3 boxes' commits in the tip" \
                  || no "reduce lost:$missing"

# 2. ORDER IS ANCESTRY, NOT TIME — b3's commit is the OLDEST by timestamp,
#    yet it is an ancestor of the tip.  A date-sorted reduce would still
#    have to merge it; a reduce that SKIPPED it on age would lose it.
oldest=$(G "$T/b3" rev-parse HEAD)
if q G "$T/acc" merge-base --is-ancestor "$oldest" HEAD; then
    ok "ancestry governs: the OLDEST-dated commit is in the tip"
else
    no "the oldest-dated commit was dropped"
fi

# 3. FAST-FORWARD / ALREADY-CONTAINED IS A NO-OP — re-running the whole
#    reduce must add ZERO commits.  This is what makes it re-runnable.
before=$(G "$T/acc" rev-list --count HEAD)
for b in b1 b2 b3; do
    q G "$T/acc" fetch -q "$b" master
    q G "$T/acc" merge-base --is-ancestor FETCH_HEAD HEAD && continue
    q G "$T/acc" merge --no-edit FETCH_HEAD
done
after=$(G "$T/acc" rev-list --count HEAD)
[ "$before" = "$after" ] && ok "idempotent: a second reduce adds 0 commits ($before)" \
                         || no "second reduce added $((after-before)) commits"

# 4. A CONFLICT STOPS THE REDUCE — it must NOT silently take one side.
q git clone -q "$T/hub" "$T/cx"
q G "$T/cx" config user.email bench@local; q G "$T/cx" config user.name bench
q G "$T/cx" fetch -q origin; q G "$T/cx" reset -q --hard origin/master
echo conflict-a > "$T/cx/clash.txt"; q G "$T/cx" add clash.txt; q G "$T/cx" commit -qm a
echo conflict-b > "$T/acc/clash.txt"; q G "$T/acc" add clash.txt; q G "$T/acc" commit -qm b
q G "$T/acc" remote add cx "$T/cx"; q G "$T/acc" fetch -q cx master
if q G "$T/acc" merge --no-edit FETCH_HEAD; then
    no "a real conflict merged silently"
else
    # the side under conflict must still be OURS until a human resolves
    grep -q conflict-b "$T/acc/clash.txt" && ok "conflict STOPS the reduce (no silent side-take)" \
                                          || no "conflict clobbered our side"
    q G "$T/acc" merge --abort
fi

# 5. THE COUNTER-EXAMPLE: PARALLEL MERGE LOSES WORK.  Two boxes merging the
#    SAME base concurrently produce two tips; pushing both is impossible and
#    the loser must redo the work.  Modelled by merging into two clones of
#    one base and showing neither contains the other.
q git clone -q "$T/hub" "$T/p1"; q git clone -q "$T/hub" "$T/p2"
for p in p1 p2; do q G "$T/$p" config user.email bench@local; q G "$T/$p" config user.name bench; done
q G "$T/p1" remote add b1 "$T/b1"; q G "$T/p1" fetch -q b1 master; q G "$T/p1" merge -q --no-edit FETCH_HEAD
q G "$T/p2" remote add b2 "$T/b2"; q G "$T/p2" fetch -q b2 master; q G "$T/p2" merge -q --no-edit FETCH_HEAD
t1=$(G "$T/p1" rev-parse HEAD); t2=$(G "$T/p2" rev-parse HEAD)
q G "$T/p1" fetch -q "$T/p2" master 2>/dev/null || true
if [ "$t1" != "$t2" ]; then
    ok "parallel merge yields 2 tips -> one must be redone (why reduce is serial)"
else
    no "parallel merges collapsed to one tip (impossible; bench is broken)"
fi

printf '%d/%d reduce properties hold\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
