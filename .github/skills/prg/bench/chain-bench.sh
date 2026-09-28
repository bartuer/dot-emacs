#!/usr/bin/env bash
# chain-bench.sh — SMOOTH-DOWNSTREAM gate for the case-folder chain (G10 10.4).
#
# THE CLAIM UNDER TEST.  A case folder is a first-class SOURCE, so the six
# numbers 8.14 derived by hand must come back FROM THE CASE DIR ALONE,
# through the chain, with no per-file command typed by the caller:
#
#   prg-case.sh (which files, how to read) -> read (cells as JSONL)
#     -> jq (decode flat) -> awk (pivot by row) -> counts
#
# WHY AN ASSERTING BENCH AND NOT A DEMO.  A chain that PRINTS numbers passes
# on the day extraction silently breaks.  Every arm below compares against a
# LITERAL from 8.14's answer key (transcript turn 163, the practitioner
# correcting herself off the file), so a regression fails loudly.
#
# !! THE NEGATIVE ARM IS THE TEST.  Arm A counts padj<0.05 and arm B adds
# the PDF's own |LFC|>1.  Without B, a chain hard-wired to emit 83/77/84
# would pass A perfectly.  B must return DIFFERENT numbers (76/75/78 — the
# workbook-vs-figure disagreement 8.14 found) or the filter is not biting
# and the chain is theatre.
#
# !! NO ADAPTER BETWEEN HOPS.  The chain uses `prg-case.sh read`, which
# resolves index/binary/text itself.  An earlier draft piped `plan`'s
# .sidecar through a shell `while read` loop to build an rg argument — that
# is a bespoke inter-tool convention, exactly what 10.4's :hard-rule:
# forbids, and it hard-codes the sidecar layout into the caller.
#
# Exit: 0 all pass · 1 a scored arm FAILED · 2 deps/corpus absent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../prg-case.sh"
CASE="${PRG_CHAIN_CORPUS:-/workspace/datasets/microcosmo/crossapp-cases-1224/cases/soc-15-2099.01_task-17709_v3}"
WB="Delgado_monocyte_IFN_DEresults_2024-06-14_v2.xlsx"

command -v rg >/dev/null && command -v jq >/dev/null || {
  echo "chain-bench: rg + jq required" >&2; exit 2; }
[ -d "$CASE/files" ] || {
  echo "chain-bench: corpus absent ($CASE) -- set PRG_CHAIN_CORPUS" >&2; exit 2; }

fail=0
ok()   { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s — got %s, want %s\n' "$1" "$2" "$3"; fail=1; }
cmp_() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

# The pivot: cells arrive one-per-record, so a two-column predicate
# (padj AND log2FC) cannot be written over single records.  Key by
# (sheet,row) and join in a streaming hash.  $1=sheet $2=row $3=col $4=val.
# !! ITERATE SEEN ROWS, NOT THE VALUE ARRAY — a blank cell emits no record,
# so keying on one column silently drops real rows.
pivot() {  # $1 = extra |LFC| threshold ("" = none)
  awk -F'\t' -v lfc="$1" '
    $3==4 { fc[$1"\t"$2]=$4; seen[$1"\t"$2]=1 }
    $3==8 { pa[$1"\t"$2]=$4; seen[$1"\t"$2]=1 }
    END {
      # !! `next` IS ILLEGAL IN END (gawk errors, mawk may not) — the guards
      # below are nested conditionals for that reason.  Do not "simplify".
      for (k in seen) {
        split(k,a,"\t"); s=a[1]
        keep = (k in pa) && pa[k] != "" && (pa[k]+0 < 0.05)   # absence != value
        if (keep && lfc != "") { v=fc[k]+0; if (v<0) v=-v; keep = (v > lfc+0) }
        if (keep) { sig[s]++; if (fc[k]+0 > 0) up[s]++ }
      }
      for (s in sig) printf "%s\t%d\t%d\n", s, sig[s], up[s]
    }'
}

# ONE chain, case dir in.  `read` resolves the access path per file.
cells() { "$TOOL" read "$CASE/files" "$WB" | jq -rc 'select(.r>1)|[.s,.r,.c,.v]|@tsv'; }

echo "chain-bench: $(basename "$CASE")"

# ---- provenance: the workbook is chosen by INVENTORY, not by filename ----
# 8.14's discriminator: the delivered copy is the one carrying a README tab.
readme=$("$TOOL" read "$CASE/files" "$WB" 2>/dev/null | jq -rc '.s' | sort -u | grep -c '^README$')
cmp_ "delivered copy has README tab (inventory discriminator)" "$readme" "1"

t0=$(date +%s%N)
A=$(cells | pivot "")
t1=$(date +%s%N)

# ---- ARM A: padj<0.05 — the practitioner's own corrected numbers ----
while IFS=$'\t' read -r s sig up; do
  case "$s" in
    IFNb_vs_UT)   cmp_ "A IFNb_vs_UT"   "$sig/$up" "83/76" ;;
    IFNg_vs_UT)   cmp_ "A IFNg_vs_UT"   "$sig/$up" "77/71" ;;
    IFNb_vs_IFNg) cmp_ "A IFNb_vs_IFNg" "$sig/$up" "84/73" ;;
  esac
done <<< "$A"
cmp_ "A contrast count" "$(printf '%s\n' "$A" | grep -c .)" "3"

# ---- ARM B (NEGATIVE): + |LFC|>1 must MOVE the numbers ----
B=$(cells | pivot 1)
while IFS=$'\t' read -r s sig up; do
  case "$s" in
    IFNb_vs_UT)   cmp_ "B IFNb_vs_UT strict"   "$sig" "76" ;;
    IFNg_vs_UT)   cmp_ "B IFNg_vs_UT strict"   "$sig" "75" ;;
    IFNb_vs_IFNg) cmp_ "B IFNb_vs_IFNg strict" "$sig" "78" ;;
  esac
done <<< "$B"

# the two arms MUST disagree, else the filter is inert and A proves nothing
[ "$A" != "$B" ] && ok "arms differ (filter bites; A is not hard-wired)" \
                 || bad "arms differ" "identical" "different"

printf 'chain-bench: %s ms end-to-end\n' "$(( (t1-t0)/1000000 ))"
[ "$fail" -eq 0 ] && echo "chain-bench: ALL PASS" || echo "chain-bench: FAILURES"
exit "$fail"
