#!/usr/bin/env bash
# jail-bench.sh — can prg survive an ssg-sim jail with bench/ dropped?
#
# The bench for the prg SKILL ITSELF (plan 256), not for one tool.  ssg-sim
# grades a skill by copying skills/<name>/ into a throwaway jail through
# server.py's `_jail_ignore`, which strips `bench/` wholesale so the child
# model never sees the answer key.  prg keeps its golds in bench/
# (gold.tsv, gold-search.tsv, regress.baseline.tsv), so a jailed prg is a
# prg with NO answer key -- exactly the intent.
#
# Two things must hold, and they pull in OPPOSITE directions:
#   A. NO LEAK   -- no gold/baseline/expected file reaches the jail.
#   B. NO VOID   -- a tool that NEEDS its stripped gold must fail LOUDLY
#                   (nonzero), never print a shrug and exit 0.  A green exit
#                   on a missing answer key is a void measurement reported
#                   as a pass, which is worse than a crash.
# Tools that do not need the gold must still RUN, or the jail is useless.
#
# WHY a bench and not a one-off check: `_jail_ignore` matches answer keys by
# SHAPE (*.golden.json, *.gold.json, queries.jsonl) plus the exact name
# `bench`.  prg's golds are .TSV -- covered ONLY by the `bench` directory
# rule.  Any gold that migrates out of bench/ silently stops being excluded,
# and no glob would catch it.  This bench is the tripwire for that.
#
# TRAP encoded here (cost me a wrong conclusion once): never pipe the tool
# under test into `head` to grab its exit code -- `$?` then belongs to head,
# and a correct `exit 2` reads as 0.  Redirect to a file, THEN inspect.
#
# Usage:  bash bench/jail-bench.sh [--pretty] [--keep]
# Exit:   0 all invariants hold · 2 bad deps · 3 LEAK · 4 VOID (silent pass)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$HERE")"                 # .../skills/prg
SKILLS_ROOT="$(dirname "$SKILL_DIR")"          # .../skills
SERVER="$SKILLS_ROOT/ssg-sim/server.py"

PRETTY=0; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) PRETTY=1; shift ;;
    --keep)   KEEP=1;   shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "jail-bench: unknown arg $1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null || { echo "jail-bench: python3 required" >&2; exit 2; }
[ -f "$SERVER" ] || { echo "jail-bench: ssg-sim/server.py not found: $SERVER" >&2; exit 2; }

# ---- build a real jail using ssg-sim's OWN ignore fn -----------------------
# Importing the real _jail_ignore is the whole point: a reimplementation here
# would drift from the thing that actually runs and prove nothing.
JAIL_ROOT="$(mktemp -d /tmp/prg-jailbench-XXXXXX)"
trap '[ "$KEEP" = 1 ] || rm -rf "$JAIL_ROOT"' EXIT

python3 - "$SERVER" "$SKILL_DIR" "$JAIL_ROOT/prg" <<'PY' || { echo "jail-bench: jail build failed" >&2; exit 2; }
import importlib.util, shutil, sys
server, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("ssgsrv", server)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
shutil.copytree(src, dst, ignore=m._jail_ignore)
PY

JAIL="$JAIL_ROOT/prg"

# ---- A. leak scan ----------------------------------------------------------
# Match the SHAPE of an answer key, not a name list -- same discipline
# ssg-sim learned the hard way when a per-recipe .golden.json slipped past
# an exact-name rule.
LEAKS="$(find "$JAIL" -type f \
          \( -iname '*gold*' -o -iname '*baseline*' -o -iname '*expected*' \
             -o -iname '*answer*' -o -iname 'queries.jsonl' \) | sort || true)"
LEAK_N=$(printf '%s' "$LEAKS" | grep -c . || true)

# ---- B. behaviour of jailed tools ------------------------------------------
# NEEDS_GOLD must fail loudly; RUNS_ANYWAY must still work.
NEEDS_GOLD=("prg-bench.sh" "prg-regress.sh check")
RUNS_ANYWAY=("prg-minidx.sh stat")

rows=""; VOID_N=0; DEAD_N=0
for t in "${NEEDS_GOLD[@]}"; do
  set +e
  ( cd "$JAIL" && timeout 60 bash $t ) >/tmp/jb.out 2>/tmp/jb.err
  rc=$?
  set -e
  verdict=LOUD; [ "$rc" = 0 ] && { verdict=VOID; VOID_N=$((VOID_N+1)); }
  rows+=$(printf 'needs-gold\t%s\t%s\t%s\n' "${t%% *}" "$rc" "$verdict")$'\n'
done

CORPUS="${PRG_JS_CORPUS:-/workspace/research/wwwrootsdx}"
for t in "${RUNS_ANYWAY[@]}"; do
  set +e
  ( cd "$JAIL" && timeout 60 bash $t --corpus "$CORPUS" ) >/tmp/jb.out 2>/tmp/jb.err
  rc=$?
  set -e
  # 4 == corpus absent is an environment fact, not a jail defect.
  verdict=RUNS
  if [ "$rc" != 0 ] && [ "$rc" != 4 ]; then verdict=DEAD; DEAD_N=$((DEAD_N+1)); fi
  rows+=$(printf 'runs-anyway\t%s\t%s\t%s\n' "${t%% *}" "$rc" "$verdict")$'\n'
done

FILE_N=$(find "$JAIL" -type f | wc -l | tr -d ' ')
printf '%s' "$rows" > /tmp/prg-jail-bench.rows.tsv

if [ "$PRETTY" = 1 ]; then
  echo "jail      $JAIL"
  echo "files     $FILE_N copied (bench/ stripped by ssg-sim _jail_ignore)"
  echo "leaks     $LEAK_N"
  [ "$LEAK_N" -gt 0 ] && printf '  LEAK %s\n' $LEAKS
  echo
  printf '%-12s %-18s %-5s %s\n' class tool exit verdict
  printf '%-12s %-18s %-5s %s\n' ------------ ------------------ ----- -------
  while IFS=$'\t' read -r c t r v; do
    [ -z "$c" ] && continue
    printf '%-12s %-18s %-5s %s\n' "$c" "$t" "$r" "$v"
  done <<< "$rows"
  echo
  echo "rows -> /tmp/prg-jail-bench.rows.tsv"
else
  printf '%s' "$rows"
fi

[ "$LEAK_N" -gt 0 ] && { echo "jail-bench: FAIL answer key leaked into jail" >&2; exit 3; }
[ "$VOID_N" -gt 0 ] && { echo "jail-bench: FAIL tool exits 0 with its gold stripped (void pass)" >&2; exit 4; }
[ "$DEAD_N" -gt 0 ] && { echo "jail-bench: FAIL gold-independent tool cannot run in jail" >&2; exit 4; }
echo "jail-bench: OK  no leak, ${#NEEDS_GOLD[@]} loud, ${#RUNS_ANYWAY[@]} runnable" >&2
exit 0
