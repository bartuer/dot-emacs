#!/usr/bin/env bash
# prg-cyclic.sh -- the join graphs that no edge rule can straighten out.
#
# WHEN TO REACH FOR THIS.  Only after `prg-join.sh dag --escalate` has climbed
# the whole ladder (name -> value -> pk) and STILL reports a cycle.  Measured
# corpus-wide that is 62/1224 = 5.1% of cases; 55.4% of value-cyclic cases go
# acyclic under `pk` alone, which is why tightening the EVIDENCE comes first and
# this script comes second.  Keeping it separate is deliberate (plan 261
# Context :decision:): the common 80% path must not pay for the 5.1% path, and
# `prg-join.sh` keeps its refuse-on-cycle contract -- refusal is CORRECT
# behaviour there, not a bug to be papered over.
#
# WHAT IT DOES -- and pointedly does NOT do:
#   a. REPORTS the cycle, so "these tables form a cycle" is a citable finding
#      rather than an absence (exactly as rejects.tsv is for broken joins).
#   b. BREAKS it by dropping the single weakest MEASURED edge -- lowest
#      n_shared, ties broken by lowest contain -- then re-checks, looping while
#      progress is made.  The dropped edge is emitted as counter-evidence.
#   c. STOPS.  No GYO reduction, no spanning-tree join engine, no Yannakakis.
#      Out of scope until a real case proves (b) insufficient.
#
# :decision: the edge to drop is chosen by MEASURED overlap, never by name or
# by file order.  The whole plan's rule is that the verdict comes from values;
# a tie-break on filename would smuggle name-agreement back in through the
# side door.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOIN="$HERE/prg-join.sh"

die() { printf '%s\n' "$*" >&2; exit 2; }

usage() {
  cat <<'EOF'
usage: prg-cyclic.sh <folder> --edges FILE [--out DIR] [--rule name|value|pk]

  Break a CYCLIC join graph by dropping the weakest measured edges.
  Runs ONLY on a graph that is genuinely cyclic; on an acyclic graph it
  emits nothing and exits non-zero (use prg-join.sh dag for those).

  Outputs into --out (default cwd):
    cycle.txt    the participating nodes -- the finding
    dropped.tsv  each edge removed, with the evidence that made it weakest
    edges.tsv    the surviving acyclic edge set
    dag.mmd      mermaid of the survivors

  Exit: 0 broke the cycle, 2 usage/error, 4 input was already acyclic,
        5 could not break it within the drop budget.
EOF
}

dir=""; edges=""; out="."; rule="pk"; maxdrop=25
while [ $# -gt 0 ]; do
  case "$1" in
    --edges)   edges="$2";   shift 2 ;;
    --out)     out="$2";     shift 2 ;;
    --rule)    rule="$2";    shift 2 ;;
    --maxdrop) maxdrop="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)  dir="$1"; shift ;;
  esac
done
[ -n "$dir" ]   || { usage >&2; exit 2; }
[ -d "$dir" ]   || die "not a directory: $dir"
[ -n "$edges" ] || die "--edges is required: this script VERIFIES a proposal, it does not invent one"
[ -f "$edges" ] || die "no such edge file: $edges"
mkdir -p "$out" || die "cannot create out dir: $out"

work="$(mktemp)"; res="$(mktemp)"
cleanup() { rm -f "$work" "$res"; }
trap cleanup EXIT
cp "$edges" "$work" || die "cannot read edge file"

: > "$out/dropped.tsv"
printf 'iter\tsrc\tdst\tlcol\trcol\tn_shared\tcontain\twhy\n' > "$out/dropped.tsv"

# prg-join.sh prints a SUMMARY on stdout (edges/rejects stripped) and writes the
# FULL verdict to $out/verdict.json.  We need the full one: picking the weakest
# survivor requires the edge list.
run_dag() {
  "$JOIN" dag "$dir" --edges "$work" --rule "$rule" --out "$out" >/dev/null 2>&1
  local r=$?
  cp "$out/verdict.json" "$res" 2>/dev/null
  return $r
}

run_dag; rc=$?
[ -s "$res" ] || die "dag verification produced no output"

# :red: guard -- refuse to be a silent alternative path for graphs that
# prg-join.sh already handles.  An acyclic input is a USAGE error here.
if [ "$rc" -eq 0 ]; then
  printf 'input graph is ALREADY ACYCLIC under rule=%s -- prg-join.sh dag handles this; nothing to break\n' \
    "$rule" >&2
  rm -f "$out/dropped.tsv"
  exit 4
fi

# (a) REPORT the cycle before touching it.
jq -r '(if .cycle then "directed cycle: " + (.cycle | join(" -> ")) else empty end),
       (if .undirected_cyclic then "undirected join graph is CYCLIC" else empty end),
       "rule: " + .rule, "edges: " + (.n_edges|tostring)' "$res" > "$out/cycle.txt"

n=0
while [ "$n" -lt "$maxdrop" ]; do
  n=$((n+1))
  # (b) weakest MEASURED edge among the SURVIVORS: lowest n_shared, then
  # lowest contain.  Only verified edges are candidates for dropping --
  # rejected ones are already gone and dropping them would be a no-op loop.
  weak="$(jq -r '.edges | sort_by(.n_shared, .contain) | .[0]
                 | [.src, .dst, .lcol, .rcol, .n_shared, .contain] | @tsv' "$res")"
  [ -n "$weak" ] && [ "$weak" != "null" ] || die "no edges left to drop"

  IFS=$'\t' read -r ws wd wl wr wn wc <<< "$weak"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tweakest measured overlap among survivors\n' \
    "$n" "$ws" "$wd" "$wl" "$wr" "$wn" "$wc" >> "$out/dropped.tsv"

  # Remove exactly that proposal line (all four fields must match).
  awk -F'\t' -v s="$ws" -v d="$wd" -v l="$wl" -v r="$wr" \
      '!($1==s && $2==d && $3==l && $4==r)' "$work" > "$work.new" && mv "$work.new" "$work"

  grep -q '[^[:space:]]' "$work" || { printf 'dropped every edge without breaking the cycle\n' >&2; exit 5; }

  run_dag; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'broke the cycle after %d drop(s) under rule=%s\n' "$n" "$rule" >&2
    jq -c 'del(.edges, .rejects) + {drops: '"$n"'}' "$res"
    exit 0
  fi
done

printf 'still cyclic after %d drops -- giving up rather than guessing\n' "$maxdrop" >&2
exit 5
