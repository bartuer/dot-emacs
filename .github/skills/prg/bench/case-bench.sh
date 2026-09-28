#!/usr/bin/env bash
# case-bench.sh — FEATURE + PERF + CORRECTNESS bench for prg-case.sh diff.
#
# Per prg tool-authoring rule 3 this carries a NAIVE BASELINE arm: plain
# `jq` over the whole sidecar stream, no rg prefilter, no guards.  A tool
# not compared against the obvious one-liner cannot prove it earns its keep.
#
# THE CLAIM UNDER TEST.  `prg-case.sh diff` says three things a hand-rolled
# jq/join does not:
#   1. it is FASTER, because it rg-prefilters the sidecar before jq parses
#   2. it REFUSES a non-unique key instead of fabricating changes
#   3. it reports a value that splits INSIDE the target file, which an
#      A-vs-B compare cannot see at all
# Each is scored below.  (1) is perf; (2) and (3) are correctness, and both
# were REAL DEFECTS observed on this corpus, not hypotheticals -- see the
# CORRECTNESS section comments for the measured wrong answers.
#
# THE GOLD NUMBER IS DERIVED, NOT TYPED.  32 movers is recomputed here from
# the workbooks by an INDEPENDENT route (group-by over the raw sidecar, no
# prg-case.sh involved) so the bench cannot pass by agreeing with itself.
# Read fix.archive/prg-bench-coverage.md before hand-editing any count.
#
# Exit: 0 all pass · 2 deps/corpus absent · 1 a scored arm FAILED.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../prg-case.sh"
CASE="${PRG_CASE_CORPUS:-/workspace/datasets/microcosmo/crossapp-cases-1224/cases/soc-15-2051.01_task-16144_cv-be521f30}"
V5="Channel Margin & Mix_FY24_v5_KR.xlsx"
V6="Channel Margin & Mix_FY24_v6_KR.xlsx"
SHEET="SQL Pull"

command -v rg >/dev/null && command -v jq >/dev/null || {
  echo "case-bench: rg + jq required" >&2; exit 2; }
[ -d "$CASE/files" ] || {
  echo "case-bench: corpus absent ($CASE) -- set PRG_CASE_CORPUS" >&2; exit 2; }
S5="$CASE/files/$V5.prg.jsonl"; S6="$CASE/files/$V6.prg.jsonl"
[ -s "$S5" ] && [ -s "$S6" ] || {
  echo "case-bench: sidecars absent; this bench needs the indexed corpus" >&2; exit 2; }

fail=0
ok()   { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
ms()   { local s=$1 e=$2; echo $(( (e - s) / 1000000 )); }
now()  { date +%s%N; }

# ---- GOLD: recompute the mover set INDEPENDENTLY of the tool ---------------
# Raw sidecar -> (CustID,CustName) -> set of Cust Grp values, per file.
# Deliberately does NOT call prg-case.sh: a bench that scores a tool with
# the tool's own code path measures nothing.
gold_side() {
  rg -N '"c":[234][,}]' "$1" \
    | jq -r --arg sh "$SHEET" 'select(.s==$sh and .r>=2)|"\(.r)\t\(.c)\t\(.v)"' \
    | awk -F'\t' '{d[$1][$2]=$3} END{for(r in d) printf "%s|%s\t%s\n", d[r][2],d[r][3],d[r][4]}' \
    | sort -u
}
gold_side "$S5" > /tmp/cb.g5
gold_side "$S6" > /tmp/cb.g6
GOLD_MOVERS="$(join -t$'\t' /tmp/cb.g5 <(sort -u /tmp/cb.g6) 2>/dev/null \
                | awk -F'\t' '$2!=$3' | cut -f1 | sort -u | wc -l)"
# Sanity: refuse to score against a degenerate gold set (idx-bench.sh lesson --
# an all-empty table with exit 0 is worse than a loud failure).
if [ "${GOLD_MOVERS:-0}" -lt 10 ]; then
  echo "case-bench: gold set degenerate ($GOLD_MOVERS movers) -- refusing to report" >&2
  exit 2
fi
echo "gold: $GOLD_MOVERS movers (derived from sidecars, not typed)"

echo
echo "== FEATURE =="
"$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2,3 --val 4 > /tmp/cb.out 2>/tmp/cb.err
rc=$?
[ $rc -eq 0 ] && ok "diff exits 0" || bad "diff exit=$rc ($(head -1 /tmp/cb.err))"

n_changed="$(jq -r 'select(.status=="changed")|.key[0]' /tmp/cb.out | wc -l)"
[ "$n_changed" -eq "$GOLD_MOVERS" ] \
  && ok "found $n_changed movers == gold" \
  || bad "found $n_changed movers, gold says $GOLD_MOVERS"

# Counts agreeing is NOT the tool agreeing: two different 32-element sets
# would pass the arm above.  Compare the MEMBERS.
join -t$'\t' /tmp/cb.g5 <(sort -u /tmp/cb.g6) 2>/dev/null \
  | awk -F'\t' '$2!=$3' | cut -f1 | sort -u > /tmp/cb.gold.keys
jq -r 'select(.status=="changed")|.key|join("|")' /tmp/cb.out | sort -u > /tmp/cb.tool.keys
if diff -q /tmp/cb.gold.keys /tmp/cb.tool.keys >/dev/null; then
  ok "mover SET is identical to gold (not just the count)"
else
  bad "mover set differs from gold: $(comm -3 /tmp/cb.gold.keys /tmp/cb.tool.keys | tr '\n' ' ')"
fi

# every emitted record must carry the full contract
miss="$(jq -r 'select((.key|type)!="array" or (.status|type)!="string"
                      or (has("split_in_b")|not)) | .key[0]' /tmp/cb.out | wc -l)"
[ "$miss" -eq 0 ] && ok "every record carries key/status/split_in_b" \
                  || bad "$miss records violate the output contract"

# status must partition: nothing may be emitted as "same"
[ "$(jq -r 'select(.status=="same")' /tmp/cb.out | wc -l)" -eq 0 ] \
  && ok "unchanged rows suppressed" || bad "'same' rows leaked into output"

echo
echo "== CORRECTNESS =="
# (2) NON-UNIQUE KEY.  Keying on CustID alone is the natural first attempt and
# it is WRONG here: 77 of 862 ids map to 2+ names, so the join fabricates
# moves.  The tool must REFUSE (exit 5), not emit a plausible larger number.
"$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2 --val 4 >/tmp/cb.dup 2>&1
[ $? -eq 5 ] && ok "refuses non-unique key (exit 5)" \
             || bad "non-unique key not refused -- fabricated $(wc -l </tmp/cb.dup) rows"

# (3) SPLIT-IN-TARGET.  The reclassification is EFFECTIVE-DATED: each mover
# holds its old group for 12 months and NA-01 only in 2024-10, inside the
# same file.  A naive A-vs-B compare cannot represent that.  All movers here
# must be flagged.
n_split="$(jq -r 'select(.status=="changed" and .split_in_b)|.key[0]' /tmp/cb.out | wc -l)"
[ "$n_split" -eq "$GOLD_MOVERS" ] \
  && ok "all $n_split movers flagged split_in_b (effective-dated)" \
  || bad "only $n_split of $GOLD_MOVERS flagged split_in_b"

# (3b) ORDER INDEPENDENCE.  An earlier build INDEX()ed to one value per key,
# which keeps the LAST duplicate -- so with values sorted alphabetically the
# OEM-04 -> NA-01 mover silently vanished (31 instead of 32).  Assert every
# distinct source group survives, which is what that bug destroyed.
n_from="$(jq -r 'select(.status=="changed")|.from[]' /tmp/cb.out | sort -u | wc -l)"
[ "$n_from" -ge 3 ] \
  && ok "all $n_from source groups survive (no last-duplicate loss)" \
  || bad "only $n_from source groups survive -- duplicate-key collapse regressed"

# (4) ABSENCE IS NOT CHANGE.  A key seen on one side only must never be
# reported as changed.
leak="$(jq -r 'select(.status=="changed" and ((.from|length)==0 or (.to|length)==0))' /tmp/cb.out | wc -l)"
[ "$leak" -eq 0 ] && ok "absent-on-one-side never scored as changed" \
                  || bad "$leak absent rows mislabelled changed"

# (5) SCOPE.  The overlapping month is generated identically in both files,
# so a like-for-like slice must produce NO changes.  This is the control that
# proves --scope filters rather than silently passing everything through.
"$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2,3 --val 4 \
        --scope 1=2024-09 > /tmp/cb.scope 2>/dev/null
[ ! -s /tmp/cb.scope ] && ok "--scope 1=2024-09 -> no changes (history not restated)" \
                       || bad "--scope leaked $(wc -l </tmp/cb.scope) changes in a stable month"

# (5b) THE ARM ABOVE PASSES ON EMPTY, so it must be paired with a check that
# empty means "compared, found nothing" and not "matched nothing".  A typo'd
# --scope produced exactly the same silence + exit 0 before guard 0 existed.
"$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2,3 --val 4 \
        --scope 1=1999-01 >/dev/null 2>&1
[ $? -eq 5 ] && ok "un-matchable --scope refused (exit 5), not silently empty" \
             || bad "un-matchable --scope returned empty+0 -- indistinguishable from stable"

# ...but a ONE-sided scope is a legitimate question ("what is new in Oct?"),
# and must still answer.  Guards that over-refuse are their own defect.
n_oct="$("$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2,3 --val 4 \
          --scope 1=2024-10 2>/dev/null | jq -rc 'select(.status=="only_b")' | wc -l)"
[ "$n_oct" -gt 100 ] && ok "one-sided scope still answers ($n_oct only_b)" \
                     || bad "one-sided scope over-refused: got $n_oct rows"

echo
echo "== PERF =="
# BASELINE ARM: the obvious hand-rolled move -- jq the whole stream, no rg
# prefilter.  No index build, no setup cost, so the comparison is honest.
i=0
s=$(now)
for f in "$S5" "$S6"; do
  i=$((i+1))
  jq -r --arg sh "$SHEET" 'select(.s==$sh and .r>=2 and (.c==2 or .c==3 or .c==4))
                           |"\(.r)\t\(.c)\t\(.v)"' "$f" \
   | awk -F'\t' '{d[$1][$2]=$3} END{for(r in d) printf "%s|%s\t%s\n", d[r][2],d[r][3],d[r][4]}' \
   | sort -u > "/tmp/cb.base.$$.$i"
done
e=$(now); base_ms=$(ms "$s" "$e")
# The baseline must actually have produced the rows it was timed on, or the
# "speedup" is just measuring a failed pipeline running fast.
for i in 1 2; do
  [ -s "/tmp/cb.base.$$.$i" ] || { bad "baseline arm produced no rows -- timing meaningless"; break; }
done

s=$(now)
"$TOOL" diff "$CASE" "$V5" "$V6" --sheet "$SHEET" --key 2,3 --val 4 >/dev/null 2>&1
e=$(now); tool_ms=$(ms "$s" "$e")
rm -f "/tmp/cb.base.$$."*

printf '  %-34s %6s ms\n' "baseline (jq whole stream)" "$base_ms"
printf '  %-34s %6s ms\n' "prg-case.sh diff (rg prefilter)" "$tool_ms"
if [ "$tool_ms" -gt 0 ]; then
  printf '  %-34s %6s x\n' "speedup" "$(awk -v b="$base_ms" -v t="$tool_ms" 'BEGIN{printf "%.1f", b/t}')"
fi
# The prefilter is the whole perf claim; if it ever stops paying, say so
# rather than printing a green table.
[ "$tool_ms" -lt "$base_ms" ] \
  && ok "tool beats the naive baseline" \
  || bad "tool is NOT faster than plain jq -- the prefilter stopped paying"

echo
echo "== DECOY SIGNALS (ls) =="
# Both arms score the SAME failure mode from opposite sides: `ls` used to
# present a decoy and its authoritative twin as identical records, so the
# caller had nothing to go on and picked wrong.  Measured on 16943, where a
# committed answer was 26% low for exactly this reason.
#
# GOLD IS DERIVED, NOT TYPED, in both arms -- unzip and a filename sort,
# neither of which goes through prg-case.sh.
DCASE="${PRG_DECOY_CORPUS:-/workspace/datasets/microcosmo/crossapp-cases-1224/cases/soc-19-3099.01_task-16943_v1}"
if [ ! -d "$DCASE/files" ] || ! command -v unzip >/dev/null; then
  echo "  SKIP  decoy corpus or unzip absent ($DCASE)"
else
  inv="$("$TOOL" ls "$DCASE/files" 2>/dev/null)"

  # --- media arm ---------------------------------------------------------
  # A sidecar indexes CELLS.  An embedded figure is not a cell, so a file
  # can be fully "indexed" and still be partly unreadable -- silently.
  m_bad=0; m_seen=0
  while IFS=$'\t' read -r f rep; do
    case "${f,,}" in *.xlsx|*.docx|*.pptx) ;; *) continue ;; esac
    m_seen=$((m_seen+1))
    truth=$(unzip -l "$DCASE/files/$f" 2>/dev/null | grep -c '/media/')
    [ "$truth" = 0 ] && truth=""
    [ "$rep" = "$truth" ] || { bad "media mismatch on $f: ls=${rep:-null} unzip=${truth:-null}"; m_bad=1; }
  done < <(printf '%s\n' "$inv" | jq -rc '[.path, (.media//""|tostring)]|@tsv')
  [ "$m_seen" -gt 0 ] && [ "$m_bad" = 0 ] \
    && ok "media:N matches unzip on all $m_seen office files" \
    || { [ "$m_seen" -eq 0 ] && bad "media arm scored nothing -- inventory empty?"; }

  # --- near-duplicate arm ------------------------------------------------
  # The JR pair is the case's real trap: same name, same mtime order, and
  # ONE sheet apart.  `ls` must GROUP them and expose the discriminator; it
  # must NOT pick a winner (filename recency picks the Copy, and loses).
  jr="$(printf '%s\n' "$inv" | jq -rc 'select(.path|test("Maple_Ave_LOS_calcs_v2_JR"))|[.path,(.peer//0),(.sheets//0)]|@tsv')"
  n_jr=$(printf '%s\n' "$jr" | grep -c . )
  n_grp=$(printf '%s\n' "$jr" | awk -F'\t' '$2>1' | wc -l)
  [ "$n_jr" = 2 ] && [ "$n_grp" = 2 ] \
    && ok "near-duplicate pair grouped (peer>1 on both JR files)" \
    || bad "JR pair not grouped: $n_jr found, $n_grp carry peer>1"
  # sheets is the free discriminator that actually separates them.
  sh_hi=$(printf '%s\n' "$jr" | awk -F'\t' '{print $3}' | sort -rn | head -1)
  sh_lo=$(printf '%s\n' "$jr" | awk -F'\t' '{print $3}' | sort -n  | head -1)
  [ -n "$sh_hi" ] && [ "$sh_hi" != "$sh_lo" ] \
    && ok "grouped pair carries a discriminator (sheets $sh_lo vs $sh_hi)" \
    || bad "grouped pair exposes no discriminator -- caller still has nothing"
  # ...and it must stay FLAG-ONLY.  Any field that ranks or elects a member
  # is a regression: which file supersedes which is stated in prose only.
  printf '%s\n' "$inv" | jq -e 'has("supersedes") or has("authoritative") or has("winner")' \
      >/dev/null 2>&1 \
    && bad "ls emits a winner field -- must flag only, never auto-pick" \
    || ok "ls stays flag-only (no supersedes/authoritative/winner field)"

  # A signal that fires on everything is not a signal.  The 4 non-family
  # files in this folder must stay null.
  n_null=$(printf '%s\n' "$inv" | jq -rc 'select(.peer==null)|.path' | grep -c .)
  [ "$n_null" = 4 ] \
    && ok "peer stays null on the 4 non-family files (no blanket flagging)" \
    || bad "expected 4 unflagged files, got $n_null"
fi

echo
[ "$fail" -eq 0 ] && echo "case-bench: ALL PASS" || echo "case-bench: FAILURES above"
exit "$fail"
