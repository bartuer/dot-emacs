#!/usr/bin/env bash
# assert-wpx-commands.sh — replay wpx/SKILL.md's own documented jq steps
# against a real join.prg.jsonl and FAIL when any of them returns 0 rows.
#
# WHY THIS EXISTS (263 G2/G3).  Every selector wpx documents is written
# against the `k=`-tagged dialect.  The C producer publishes an untagged
# flat shape, so each of those commands exits 0 and prints NOTHING.  rc=0
# with zero rows is invisible to any check that only looks at rc -- which
# is exactly how a consumer stayed broken across two repos without a
# single red build.
#
#   THE ASSERTION IS THE ROW COUNT, NOT THE EXIT CODE.  `jq` succeeding on
#   a file it understood but matched nothing in is the failure mode.
#
# Run standalone, unpiped (a gate behind `| head` dies of SIGPIPE at
# rc=141 and reads as a failure):  bash bench/assert-wpx-commands.sh
#
# Env:
#   JOIN   path to a join.prg.jsonl to test   (default: build one)
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../wpx" && pwd)/SKILL.md"
PRG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Same folder and same build-if-absent shape as assert-graph-parity.sh:36
# -- one case, one convention, no fourth way to pick a fixture.
CASE="${CASE:-/workspace/datasets/microcosmo/crossapp-cases-1224/cases/soc-29-2072.00_task-22878_v2/files}"
JOIN="${JOIN:-/tmp/wpx-cmds-join.prg.jsonl}"

# BUILD INTO /tmp, NEVER BESIDE THE SOURCE.  The corpus is read-only, and
# the artifact's natural home (<folder>/join.prg.jsonl) is the very path
# a stray `bin2md --cells --join` clobbers (263/2.3).  Keeping the
# fixture out of the folder means this gate cannot be poisoned by, or
# poison, anything else.
if [ ! -s "$JOIN" ]; then
	[ -d "$CASE" ] || { echo "no CASE dir: $CASE" >&2; exit 2; }
	"$PRG/prg-join.sh" model "$CASE" --budget-tok 32000 > "$JOIN" \
		|| { echo "producer failed" >&2; rm -f "$JOIN"; exit 2; }
fi

fail=0
pass=0

say() { printf '%-46s %-6s %s\n' "$1" "$2" "${3:-}"; }

# A step is (label, jq program, minimum rows).  The minimums are the
# structural facts wpx's prose promises a reader -- not tuned to one
# folder.  Each is >=1 because "the map exists" is the whole claim.
check() {
	local label="$1" prog="$2" min="${3:-1}" n
	n=$(jq -c "$prog" "$JOIN" 2>/dev/null | grep -c . || true)
	n=${n:-0}
	if [ "$n" -ge "$min" ]; then
		say "$label" "PASS" "$n rows"
		pass=$((pass + 1))
	else
		say "$label" "FAIL" "$n rows (need >=$min)"
		fail=$((fail + 1))
	fi
}

if [ -z "$JOIN" ]; then
	echo "assert-wpx-commands: set JOIN=/path/to/join.prg.jsonl" >&2
	exit 2
fi
if [ ! -s "$JOIN" ]; then
	echo "assert-wpx-commands: JOIN is missing or empty: $JOIN" >&2
	exit 2
fi

echo "artifact: $JOIN ($(grep -c . "$JOIN" || true) rows)"
echo "skill:    $SKILL"
echo "----------------------------------------------------------------"

# Step 1 ("read the map") -- the shape census.  If `.k` is absent this
# yields only nulls, which is the break this plan is named for.
check "step1: k census has tagged rows" 'select(.k != null)' 1

# Step 1 cont. -- each documented kind must actually appear.
check "step1: k=schema row present"     'select(.k=="schema")' 1
check "step1: k=node rows present"      'select(.k=="node")'   1
check "step1: k=edge rows present"      'select(.k=="edge")'   1

# Step 1's meta read ("read the meta rows before anything else").
check "step2: schema/warn/trunc select" \
      'select(.k=="schema" or .k=="warn" or .k=="trunc")' 1

# Step 3 ("get hdr_row from the node row") -- hdr_row must be READABLE, never assumed.  The
# skill measures assuming row 1 to be wrong 43% of the time, so a node
# row without hdr_row defeats the point of having node rows at all.
check "step3: node rows carry hdr_row" \
      'select(.k=="node" and has("hdr_row"))' 1

# Step 2's TSV ("resolve edges to names") is the load-bearing one: edges reference
# nodes by ordinal, and a missing index yields BLANK COLUMNS rather than
# an error.  Assert the join RESOLVES, not merely that rows exist.
n=$(jq -r -n '[inputs] as $m
	| ($m|map(select(.k=="node"))|INDEX(.id|tostring)) as $N
	| $m[] | select(.k=="edge")
	| [($N[.l.n|tostring]|.file+"::"+.sheet),
	   ($N[.r.n|tostring]|.file+"::"+.sheet),
	   .l.hdr,.r.hdr,.n_shared,.contain] | @tsv' "$JOIN" 2>/dev/null \
	| grep -c . || true)
n=${n:-0}
if [ "$n" -ge 1 ]; then
	say "step2: edge->node TSV resolves" "PASS" "$n rows"
	pass=$((pass + 1))
else
	say "step2: edge->node TSV resolves" "FAIL" "$n rows (need >=1)"
	fail=$((fail + 1))
fi

# ...and that it is not resolving to BLANKS.  `$N[...]` on a missing id
# yields null, and null+"::"+... makes the whole @tsv field empty while
# the row still counts.  Zero-row checks cannot see that.
blank=$(jq -r -n '[inputs] as $m
	| ($m|map(select(.k=="node"))|INDEX(.id|tostring)) as $N
	| $m[] | select(.k=="edge")
	| ($N[.l.n|tostring]|.file) // "MISSING"' "$JOIN" 2>/dev/null \
	| grep -c '^MISSING$' || true)
blank=${blank:-0}
# GUARD AGAINST A VACUOUS PASS.  "0 dangling" is also what an artifact
# with ZERO EDGES reports, so this check green-lit the fully broken
# artifact on its first run -- caught during RED-verification.  Tie it to
# the edge count so absence can never read as health.
if [ "$n" -lt 1 ]; then
	say "step2: every edge ordinal resolves" "FAIL" "no edges to resolve"
	fail=$((fail + 1))
elif [ "$blank" -eq 0 ]; then
	say "step2: every edge ordinal resolves" "PASS" "0 dangling"
	pass=$((pass + 1))
else
	say "step2: every edge ordinal resolves" "FAIL" "$blank dangling .l.n"
	fail=$((fail + 1))
fi

# 3.2 NEGATIVE CONTROL -- the one check that survives a dialect merge.
#
# Every assertion above is satisfied by a node row that carries
# hdr_row:1 for every sheet.  So an emitter that DROPPED the real header
# analysis and hard-coded 1 would pass all of them, and wpx's Step 3
# ("never assume 1") would be quietly false while the gate stayed green.
#
# MEASURED on this folder: 145 of 268 nodes are hdr_row=1, but 123 are
# NOT (78 at row 3, 42 at row 4, 2 at row 2, 1 null).  Assuming 1 is
# wrong 46% of the time here -- the same order as the 43% wpx cites.
# Assert a header is actually FOUND BELOW ROW 1, so the value has to
# come from analysis and cannot be a constant.
deep=$(jq -c 'select(.k=="node" and .hdr_row != null and .hdr_row > 1)' \
	"$JOIN" 2>/dev/null | grep -c . || true)
deep=${deep:-0}
if [ "$deep" -ge 1 ]; then
	say "3.2: hdr_row>1 exists (not hard-coded)" "PASS" "$deep nodes"
	pass=$((pass + 1))
else
	say "3.2: hdr_row>1 exists (not hard-coded)" "FAIL" \
	    "every node claims hdr_row<=1 -- header analysis lost?"
	fail=$((fail + 1))
fi

# ...and that null is REPRESENTABLE, not coerced.  A sheet that refuses a
# header must say so; silently reporting 1 there is the same lie in the
# other direction.  This folder has exactly one such sheet.
nulls=$(jq -c 'select(.k=="node" and has("hdr_row") and .hdr_row == null)' \
	"$JOIN" 2>/dev/null | grep -c . || true)
nulls=${nulls:-0}
say "3.2: hdr_row null is representable" "INFO" "$nulls nodes"

# DRIFT.  Everything above replays a COPY of the skill's jq.  If SKILL.md
# stops documenting these selectors, every check keeps passing against text
# nobody reads -- the bench would then assert a dialect the SKILL no longer
# teaches.  Cheapest honest tie (kiss rung 6): assert the selectors this
# file replays still literally appear in the page it claims to gate.  Not a
# diff of the programs: that goes red on every whitespace edit and gets
# muted, the failure mode assert-fork-drift.sh:14 already rejected.
# RETARGETED 2026-09-04 (plan 06 item 6.8, user ruling: "make the bench
# works first in bin2md then sync upstream to ssg-agent").
#
# THE ORIGINAL TIE WAS TO FIVE LITERAL SELECTORS, and it went red for being
# RIGHT about a page that changed its job.  MEASURED across all three wpx
# pages that exist:
#     bin2md  wpx/SKILL.md        8,681 B   0 of 5 selectors
#     ssg     wpx/SKILL.md          770 B   0 of 5 selectors
#     ssg     wpx/SKILL.garbage  11,011 B   5 of 5   <- RETIRED on purpose
# Only the retired page teaches jq one-liners.  Both LIVE pages delegate:
# bin2md's says "Reach for .github/skills/prg/ first" and does not mention
# join.prg.jsonl at all; ssg's says "invoke skill /prg" and frames the work
# as source/term/task.  The recipes did not vanish -- they MOVED into the
# skill wpx now calls.
#
# So the selector list was the stale artifact, not the page.
#
# WHAT THE CHECK MUST STILL DO, because its reasoning is sound and is NOT
# retired: stop the nine checks above from "passing against text nobody
# reads".  The honest tie for a DELEGATING page is that it still delegates
# -- if wpx stops pointing at prg, these replays are orphaned again and
# this must go red.  That is a weaker claim than the old one, and saying so
# is the point: a gate that overstates what it proves is worse than one
# that states a smaller true thing.
if [ -r "$SKILL" ]; then
	missing=""
	grep -qE 'skills/prg|/prg\b|prg-[a-z]+\.sh' "$SKILL" \
		|| missing=" a pointer to the prg skill"
	if [ -z "$missing" ]; then
		say "drift: SKILL.md still delegates to prg" "PASS" "pointer present"
		pass=$((pass + 1))
	else
		say "drift: SKILL.md still delegates to prg" "FAIL" "absent:$missing"
		fail=$((fail + 1))
	fi
else
	say "drift: SKILL.md readable" "FAIL" "not found at $SKILL"
	fail=$((fail + 1))
fi

echo "----------------------------------------------------------------"
echo "checks=$((pass + fail)) pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "WPX COMMANDS OK"; exit 0; }
echo "WPX COMMANDS BROKEN -- the skill documents a dialect this artifact does not speak"
exit 1
