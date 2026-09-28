#!/usr/bin/env bash
# model-bench.sh — does a REAL model, given only SKILL.md's description,
# produce the right parse for the utterances that once failed?
#
# WHY THIS EXISTS AND parse-bench.sh DOES NOT COVER IT: parse-bench.sh grades a
# model-FREE reference implementation of the three sentences. That proves the
# rules are mechanical enough to implement -- it CANNOT prove a model reading
# the prose actually follows them. This arm closes that gap: the description is
# the prompt, so a description that reads well but parses badly shows up here.
#
# Model calls go through prg-llm.sh (local proxy, ~1.5s, zero credits), so this
# is cheap enough to fan out. Exit 3 (proxy down) is passed through as SKIP, not
# failure -- an unreachable proxy is not a bad parse.
#
# Grades SCOPE and COLS-arity only, the same two slots parse-bench.sh grades,
# so the two arms are directly comparable and neither invents an expectation
# the other does not hold.
#
# !! READ THE NUMBER CORRECTLY -- 9/9 DOES NOT VALIDATE THE DESCRIPTION.
# Control measured: replacing $desc with the generic string "Parse the query."
# ALSO scores 9/9, because parse.schema.json's field descriptions restate the
# rules and the schema is FORCED. So this arm currently proves the task is
# easy for a model given a good schema -- NOT that SKILL.md's prose teaches it.
# Measured A/B on schema richness (9 rows each, same gold set):
#   rich schema (shipped)  desc 9/9 · control 9/9  -> NOT description-sensitive
#   neutral schema         desc 6/9 · control 5/9  -> sensitive by ONE row
#   bare schema            desc 0/9               -> unusable: with no hint the
#       model cannot know "all" is the sentinel and returns scope="fleet_ssh"
# So description-sensitivity and gate stability trade off directly. We SHIP the
# rich schema because a 9/9 gate catches real regressions (transport, output
# shape, IFS corruption) while a 6/9 arm gates on nothing. Quote this as a
# capability floor, never as evidence the description is well written.
#
# Subverbs:
#   (none)   run every gold row through the model, print a table + totals
#   --quiet  totals only
# Exit: 0 all pass · 1 any fail · 2 missing dep/gold · 3 proxy down (SKIP)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gold="${here}/gold-parse.tsv"
skill="${here}/../SKILL.md"
llm="${here}/../../prg/prg-llm.sh"
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1

[ -r "$gold" ]  || { echo "MISSING gold set: $gold" >&2; exit 2; }
[ -r "$skill" ] || { echo "MISSING skill: $skill" >&2; exit 2; }
[ -x "$llm" ]   || { echo "MISSING prg-llm.sh: $llm" >&2; exit 2; }

# The DESCRIPTION is the prompt -- that is the point. If it is unclear, this
# arm degrades, which is the signal we want.
desc=$(sed -n '3p' "$skill" | sed 's/^description: //')

# The schema is FORCED via tool_choice. Prose formatting instructions are NOT
# honored by this proxy: asked in prose, the model ignored the format and
# HALLUCINATED fake ripgrep output (invented 14.1.0; the boxes run 15.1.0).
# --tool-schema is the enforceable path -- see prg-llm.sh's header.
schema="${here}/parse.schema.json"
[ -r "$schema" ] || { echo "MISSING schema: $schema" >&2; exit 2; }
sys="You parse a /fleet_ssh utterance into its slots. The rules are exactly:
${desc}
Do NOT answer the question or run anything -- only report the parse."

pass=0; total=0; fails=0
rows=()
# NOTE: `IFS=$'\t' read` COLLAPSES adjacent tabs, so a row with an empty
# field silently shifts every later column left (the empty-utterance row
# read probe="no" as cols, scoring it 1 instead of 0). Split in awk instead,
# which honours empty fields.
while IFS='|' read -r utt scope cols probe; do
    case "$utt" in \#*|"") continue ;; esac
    want_cols=$(printf '%s' "$cols" | tr ',' '\n' | sed '/^$/d' | grep -c . || true)
    total=$((total+1))

    out=$("$llm" "$utt" --system "$sys" --tool-schema "$schema" --tool-name parse 2>/dev/null) || {
        rc=$?
        [ "$rc" = 3 ] && { echo "proxy DOWN -> SKIP (exit 3)"; exit 3; }
        out=""
    }
    got_scope=$(printf '%s' "$out" | jq -r '.scope // empty' 2>/dev/null | tr -d ' ')
    got_cols=$(printf  '%s' "$out" | jq -r '.cols  // empty' 2>/dev/null)
    [ -n "$got_scope" ] || got_scope="?"
    [ -n "$got_cols" ]  || got_cols="?"

    ok_s=0; [ "$got_scope" = "$scope" ] && ok_s=1
    ok_c=0; [ "$got_cols" = "$want_cols" ] && ok_c=1
    if [ "$ok_s" = 1 ] && [ "$ok_c" = 1 ]; then pass=$((pass+1)); else fails=$((fails+1)); fi
    rows+=("$utt|$scope|$got_scope|$want_cols|$got_cols|$ok_s$ok_c")
done < <(awk -F'\t' 'NF>=4 && $0 !~ /^#/ && NF {print $1"|"$2"|"$3"|"$4}' "$gold")

if [ "$quiet" = 0 ]; then
    printf "%-46s %-16s %-10s %s\n" "UTTERANCE" "SCOPE" "COLS" "OK"
    printf '%.0s-' $(seq 1 84); echo
    for r in "${rows[@]}"; do
        IFS='|' read -r u ws gs wc gc f <<< "$r"
        [ ${#u} -gt 45 ] && u="${u:0:42}..."
        s="$gs"; [ "${f:0:1}" = 0 ] && s="$gs!=$ws"
        c="$gc"; [ "${f:1:1}" = 0 ] && c="$gc!=$wc"
        o=FAIL; [ "$f" = 11 ] && o=ok
        printf "%-46s %-16s %-10s %s\n" "$u" "$s" "$c" "$o"
    done
    printf '%.0s-' $(seq 1 84); echo
fi
echo "$pass/$total model parse rows pass"
[ "$fails" = 0 ]
