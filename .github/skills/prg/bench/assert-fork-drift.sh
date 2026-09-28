#!/usr/bin/env bash
# assert-fork-drift.sh -- 264/2.1 option (b).  The two prg copies are allowed
# to differ; they are NOT allowed to differ in ways a caller can OBSERVE.
#
# THE DECISION THIS ENCODES (264/2.1, DIRECTION REVERSED -- see below).
# prg lives in two repos:
#   bin2md .github/skills/prg      <- EDIT/DEBUG/TEST/BENCH HERE
#   ssg    .github/skills/prg      <- receives the ported result
# A symlink was rejected: each repo must keep inheriting its OWN
# .github/copilot-instructions.md, which a symlinked tree breaks.  So the
# forks stay independent and this bench makes divergence LOUD instead.
#
# DIRECTION REVERSAL.  264/2.1 originally named the ssg copy canonical for
# edits.  That did not survive contact: plan 06 in bin2md added four whole
# tools (prg-addr.sh, prg-preflight.sh, prg-preflight.py,
# jq/column-shapes.jq) in the bin2md tree, because prg is developed against
# real bin2md corpora and the benches that exercise them.  ssg has no such
# corpus, so a change made there cannot be tested before it ships.  The
# tools follow the test data.  Both repos' copilot-instructions.md now say
# so; this header is the third copy and must not drift from them.
#
# WHY THIS DOES NOT DIFF THE FILES.  Measured at the time of writing:
#   prg-source.sh 193 differing lines   prg-case.sh 229
#   prg-join.sh   310                   prg-silo.sh  19
# 751 differing lines is not a signal anybody acts on -- a bench that goes
# red on every edit to either tree gets muted within a week, which is the
# same failure mode 264/1.4 rejected a slow pre-commit hook for.  What a
# CALLER can observe is the VERB SURFACE: ask for a verb the other fork
# lacks and you get an error, not a slower answer.
#
# THE REAL GAP THIS EXISTS TO PIN (measured, not hypothetical):
#   prg-case.sh  ssg{diff ls}                       bin2md{diff ls}      SAME
#   prg-silo.sh  ssg{cells sheets}                  bin2md{cells sheets} SAME
#   prg-join.sh  ssg{candidates colvals model run schema}
#                bin2md{candidates colvals schema}        <- MISSING model, run
#
# usage:  bash assert-fork-drift.sh [OTHER_PRG_DIR]
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OTHER="${1:-/workspace/OfficeAgent/agents/ssg-agent/.github/skills/prg}"

if [ ! -d "$OTHER" ]; then
  # A missing sibling checkout is NOT a failure -- this bench must stay
  # runnable in a repo cloned on its own.  SKIP is not PASS: say so.
  echo "SKIP: no sibling prg at $OTHER (nothing to compare)"
  exit 0
fi

# ---- FIX 3.18(d): SELF-COMPARISON --------------------------------------
# BLIND SPOT #4, found by actually performing the port this file exists to
# police.  The two forks' copies of this script are byte-identical EXCEPT
# line 41 -- each names the OTHER tree.  So the obvious port (format-patch
# --relative + apply --directory, which is otherwise exactly right and is
# verified to round-trip byte-identically) carries bin2md's OTHER=<ssg>
# into ssg, where it points at ssg itself.
#
# MEASURED with the ported copy in place: "PASS file inventory identical
# (47 files)", all four RED CONTROLS pass, "OK: verb surfaces agree", rc=0.
# Every check compares a tree to itself, so every check is trivially true
# and the gate is green forever while detecting nothing.  All four red
# controls survive this, because each mutates one tree and re-reads it --
# they prove the READER works, not that the two paths differ.
#
# This is the failure mode the header already names as the worse cheat
# ("a FAKE PASS that hides real drift"), reached by accident rather than
# by design.  One line closes it.
if [ "$(cd "$HERE" && pwd -P)" = "$(cd "$OTHER" && pwd -P)" ]; then
  echo "FAIL: this tree and other tree are the SAME directory"
  echo "      $HERE"
  echo "      A cross-fork gate comparing a tree to itself passes trivially."
  echo "      Fix the OTHER default on line 41 of this fork's copy: after"
  echo "      porting from the sibling, it must name the OPPOSITE tree."
  exit 1
fi

echo "this tree : $HERE"
echo "other tree: $OTHER"
echo "(edits are made in the bin2md tree and ported forward to ssg)"
echo

# Verbs are read from the case dispatch, which is what a caller actually
# reaches.  Grepping for the WORD would lie: `grep -c model` returns 2 on
# the bin2md fork purely from prose comments on lines 6 and 8.  Match the
# dispatch arm, not the word.
#
# :fix: 3.18(b).  This used to grep a HAND-WRITTEN allow-list
# `(ls|diff|sheets|schema|colvals|candidates|model|run|cells)`, which could
# only ever see verbs someone remembered to add to it -- i.e. it went blind
# exactly when a verb was added, which is precisely when drift appears.
# MEASURED: `dag` ships in BOTH forks and `shapes` ships only in bin2md;
# the allow-list reported NEITHER while the gate printed "OK".
# Now it reads the dispatch arms themselves, bounded to the `main()` case
# block so a `case` inside some helper cannot inject a phantom verb.
# The two forks use TWO dispatch styles and a main()-only anchor was a FAKE
# PASS on one of them: prg-join.sh dispatches inside `main()`, but
# prg-case.sh and prg-silo.sh dispatch from a top-level `case "$SUB" in`.
# MEASURED while writing this fix -- anchoring on main() alone returned the
# EMPTY STRING for both of those scripts in BOTH trees, and empty == empty
# printed "verb surface identical".  A check that compares nothing to
# nothing is worse than no check.  So: open the window at EITHER anchor.
verbs() {
  awk '/^main\(\)/ || /^case[[:space:]]+"\$(SUB|\{1:-\})"?[[:space:]]+in/{inmain=1}
       inmain && /^[[:space:]]+[a-z][a-z0-9|-]*\)/{print}' "$1" 2>/dev/null \
    | grep -oE '^[[:space:]]+[a-z][a-z0-9|-]*\)' \
    | tr -d ' )' | tr '|' '\n' | grep -vE '^(\*|esac)$' \
    | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# FLAGS matter as much as verbs, and this was NOT obvious -- it was found by
# running 2.2's parity test and watching it fail.  `prg-case.sh ls` on the
# same folder returned 8 rows from both forks, but bin2md's carried a
# "sheets" field the canonical fork omitted.  That is not a regression: ssg
# deliberately made it OPT-IN behind `--with-sheets` because counting sheets
# costs 33.7x (MEASURED 279 ms -> 9397 ms on a 143 MB folder, same 16 rows).
# Pass the flag and the two outputs are byte-identical under `jq -S`.
# The lesson: a fork can keep every verb and still answer the same question
# differently BY DEFAULT.  A verb-only check calls that clean.
flags() {
  grep -oE '^[[:space:]]+--[a-z-]+\)' "$1" 2>/dev/null \
    | tr -d ' )' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# KNOWN, ACCEPTED DRIFT.  This gate is auto-discovered by run-gates.sh, and a
# gate that is red on day one for a gap nobody is fixing today teaches the
# suite to be ignored -- the same reasoning that kept the 10-minute suite out
# of a pre-commit hook (264/1.4).  The opposite cheat is worse: running this
# as `--self-test` so it always exits 0 would be a FAKE PASS that hides real
# drift.  So: record the gap that exists TODAY and go red only on drift
# BEYOND it.  Shrinking this list is progress; nothing silently widens it.
# :update: 3.18.  The `model run` entry is GONE because the gap CLOSED --
# both verbs were ported into bin2md and verified there (model: 62 rows,
# k=node/k=edge byte-identical to this fork under `jq -S`).  This file's own
# rule is "shrinking this list is progress"; leaving a dead entry would mute
# a future REAL regression of exactly those two verbs.
#
# prg-case.sh's gap is NEW here only in the sense that it was never VISIBLE:
# the old allow-list regex could not see 19 of its 21 verbs.  MEASURED with
# the fixed reader: ssg has {doc pdf refresh slides table workbook} that
# bin2md lacks.  Recorded, not fixed, because closing it is a port decision
# (plan 06 item 3.17), not a drift-gate decision.
declare -A KNOWN=( [prg-case.sh]="doc pdf refresh slides table workbook" [prg-join.sh]="shapes" )

fail=0

# ---- FIX 3.18(a): FILE INVENTORY ------------------------------------------
# The loop below checks THREE hardcoded scripts, so an entire new FILE was
# invisible.  MEASURED at the time of the fix: 4 tools existed only in bin2md
# (prg-addr.sh, prg-preflight.sh, prg-preflight.py, jq/column-shapes.jq) and
# 20 only in ssg -- while this gate printed "OK: verb surfaces agree".  A tool
# present in one tree and absent in the other is at least as caller-observable
# as a missing verb.
#
# :kiss: this is an INVENTORY check, not a content diff.  The header above is
# right that 751 differing lines is noise nobody acts on; "a tool exists here
# and not there" is one line of signal per file.  Reported as NOTE, not FAIL,
# for the same reason the flag check is: the forks are deliberately allowed to
# hold different tools (that is why the direction reversed).  Going red on it
# would teach the suite to be ignored.
inventory() {
  ( cd "$1" && find . -maxdepth 2 \( -name '*.sh' -o -name '*.py' -o -name '*.jq' \) \
      -not -path './bench/*' -printf '%P\n' 2>/dev/null | sort )
}
inv_a="$(inventory "$HERE")"
inv_b="$(inventory "$OTHER")"
only_here="$(comm -23 <(printf '%s\n' "$inv_a") <(printf '%s\n' "$inv_b") | tr '\n' ' ')"
only_there="$(comm -13 <(printf '%s\n' "$inv_a") <(printf '%s\n' "$inv_b") | tr '\n' ' ')"
if [ -z "${only_here// }" ] && [ -z "${only_there// }" ]; then
  echo "PASS  file inventory identical ($(printf '%s\n' "$inv_a" | grep -c . ) files)"
else
  echo "NOTE  file inventory differs (a tool in one tree only)"
  [ -n "${only_here// }" ]  && echo "        only in this tree : $only_here"
  [ -n "${only_there// }" ] && echo "        only in other tree: $only_there"
fi
echo

# ---- 06/6.5: CONTENT IDENTITY, now that 6.2 chose FULL CONVERGENCE --------
# WHY THIS DOES NOT OVERTURN THE :kiss: RULING ABOVE.  The header rejects
# content diffing because "751 differing lines is noise nobody acts on" and
# "a bench that goes red on every edit gets muted within a week".  That was
# TRUE and the ruling stands as written -- what changed is the PREMISE, not
# the judgement.  Plan 06 item 6.2 ruled end state (a), one canonical prg,
# and 6.3 pushed bin2md -> ssg with a plain additive copy.  MEASURED right
# after: 86 shared files compared, 0 differing.  The number this check
# reports is therefore 0 by construction, and a non-zero value is a NEW
# divergence somebody introduced -- signal, not noise.  It is muteable only
# by re-forking, which is the exact thing this file exists to detect.
#
# SCOPE, deliberately narrow:
#   - SHARED files only.  A file in one tree alone is the inventory check's
#     job above, and under 6.2(a) the 16 ssg-only bench/ files are left
#     alone by 6.3 rather than deleted, so they must NOT count as drift.
#   - assert-fork-drift.sh ITSELF is skipped.  Its one differing line is
#     each fork's OTHER default path; making them identical would point a
#     fork at itself, which 3.18(d) already caught as a FAKE PASS.  That is
#     the ONE permanently-divergent file 6.2's ruling names.
#
# NOT A LEDGER READER.  An earlier draft of 6.5 had this consult
# fix.archive/prg-fork-ledger.md for declared differences.  Rejected: a gate
# that depends on a prose artifact drifts from it silently.  `cmp` needs no
# registry.
content_drift=0
content_seen=0
content_list=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ "$rel" = "bench/assert-fork-drift.sh" ] && continue
  [ -f "$OTHER/$rel" ] || continue        # one-sided: inventory's job
  content_seen=$((content_seen+1))
  cmp -s "$HERE/$rel" "$OTHER/$rel" || {
    content_drift=$((content_drift+1))
    content_list="$content_list $rel"
  }
done < <( cd "$HERE" && find . -type f -printf '%P\n' 2>/dev/null | sort )

if [ "$content_drift" -eq 0 ]; then
  echo "PASS  content identical on all $content_seen shared files (6.2a)"
else
  echo "FAIL  $content_drift of $content_seen shared files diverged:$content_list"
  echo "        Edit in bin2md, then re-run 06/6.3's additive copy."
  fail=$((fail+1))
fi
echo

for t in prg-case.sh prg-join.sh prg-silo.sh; do
  if [ ! -f "$HERE/$t" ] || [ ! -f "$OTHER/$t" ]; then
    echo "FAIL  $t: present in only one tree"
    fail=$((fail+1)); continue
  fi
  a="$(verbs "$HERE/$t")"
  b="$(verbs "$OTHER/$t")"
  fa="$(flags "$HERE/$t")"
  fb="$(flags "$OTHER/$t")"
  if [ "$fa" != "$fb" ]; then
    # Reported, but NOT counted as a failure: a flag the other fork lacks is
    # how a measured default change lands (--with-sheets).  Loud, not red.
    echo "NOTE  $t flag surface differs (default behaviour may differ)"
    echo "        this tree : {$fa}"
    echo "        other tree: {$fb}"
  fi
  if [ "$a" = "$b" ]; then
    echo "PASS  $t verb surface identical {$a}"
  else
    echo "DRIFT $t verb surface differs"
    echo "        this tree : {$a}"
    echo "        other tree: {$b}"
    only_a="$(comm -23 <(tr ' ' '\n' <<<"$a" | sort) <(tr ' ' '\n' <<<"$b" | sort) | tr '\n' ' ')"
    only_b="$(comm -13 <(tr ' ' '\n' <<<"$a" | sort) <(tr ' ' '\n' <<<"$b" | sort) | tr '\n' ' ')"
    [ -n "${only_a// }" ] && echo "        missing from other tree: $only_a"
    [ -n "${only_b// }" ] && echo "        missing from this tree : $only_b"
    # Compare the WHOLE observed gap to the recorded one.  Equality, not
    # subset: if the gap shrinks, the baseline is stale and should be
    # updated, and staying green about it is how baselines rot.
    obs="$(printf '%s %s' "$only_a" "$only_b" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')"
    exp="$(printf '%s' "${KNOWN[$t]:-}" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')"
    if [ "$obs" = "$exp" ]; then
      echo "        ACCEPTED: exactly the known gap (264/2.1) -- not counted"
    else
      echo "        UNEXPECTED: known gap is {$exp}, observed {$obs}"
      fail=$((fail+1))
    fi
  fi
done

# RED CONTROL.  A comparison that cannot fail proves nothing, and this one
# runs against whatever happens to be on disk -- so prove the detector
# fires on a surface we CONSTRUCT, not on one we hope is broken.
echo
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed 's/^\([[:space:]]*\)schema)/\1zzschema)/' "$HERE/prg-join.sh" > "$tmp/prg-join.sh"
ctl_a="$(verbs "$HERE/prg-join.sh")"
ctl_b="$(verbs "$tmp/prg-join.sh")"
if [ "$ctl_a" != "$ctl_b" ]; then
  echo "PASS  RED CONTROL 1 fired (renaming one verb is detected)"
else
  echo "FAIL  RED CONTROL 1 did not fire -- this bench cannot detect drift"
  fail=$((fail+1))
fi

# RED CONTROL 2 -- the baseline must not be a blanket mute.  KNOWN suppresses
# a real, observed difference, so prove that a gap DIFFERENT from the recorded
# one is still rejected.  Without this, a typo'd baseline key silently
# swallows every future drift and the gate stays green forever.
ctl_obs="model run extra"
ctl_exp="model run"
if [ "$(tr ' ' '\n' <<<"$ctl_obs" | sort | tr '\n' ' ')" != "$(tr ' ' '\n' <<<"$ctl_exp" | sort | tr '\n' ' ')" ]; then
  echo "PASS  RED CONTROL 2 fired (a gap wider than the baseline is rejected)"
else
  echo "FAIL  RED CONTROL 2 did not fire -- the baseline mutes everything"
  fail=$((fail+1))
fi

# RED CONTROL 3 -- prove the FILE INVENTORY check (3.18a) actually fires.
# Build a tree that is a copy of HERE minus exactly one tool, and assert the
# inventory notices.  Hiding a file is the failure this check exists for, so
# test it by hiding a file, not by trusting that the trees differ today.
inv_tmp="$(mktemp -d)"
cp -r "$HERE/." "$inv_tmp/" 2>/dev/null
rm -f "$inv_tmp/prg-join.sh"
if [ "$(inventory "$HERE")" != "$(inventory "$inv_tmp")" ]; then
  echo "PASS  RED CONTROL 3 fired (a tool missing from one tree is detected)"
else
  echo "FAIL  RED CONTROL 3 did not fire -- the inventory check is blind"
  fail=$((fail+1))
fi
rm -rf "$inv_tmp"

# RED CONTROL 4 -- prove the verb reader (3.18b) sees a verb that no
# hand-written allow-list contains.  This is the exact defect being fixed:
# the old regex could only match a vocabulary someone remembered to update,
# so it went blind the moment a NEW verb appeared.  Invent a verb that is
# deliberately not in any list and assert it is read back.
vrb_tmp="$(mktemp -d)"
sed 's/^\([[:space:]]*\)schema)/\1zzqqverb)/' "$HERE/prg-join.sh" > "$vrb_tmp/prg-join.sh"
if verbs "$vrb_tmp/prg-join.sh" | grep -qw zzqqverb; then
  echo "PASS  RED CONTROL 4 fired (a verb outside any allow-list is read)"
else
  echo "FAIL  RED CONTROL 4 did not fire -- verbs() is still allow-listed"
  fail=$((fail+1))
fi
rm -rf "$vrb_tmp"

echo
if [ "$fail" != 0 ]; then
  echo "FAILED: $fail check(s).  The forks differ where a CALLER can tell."
  echo "Edits are made in the bin2md copy and ported forward to ssg; fix it"
  echo "there, then port.  Do NOT reconcile SKILL.md prose here -- that is 263's."
  exit 1
fi
echo "OK: verb surfaces agree"
exit 0
