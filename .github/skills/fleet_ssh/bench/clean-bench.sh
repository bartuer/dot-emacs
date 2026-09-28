#!/usr/bin/env bash
# clean-bench.sh -- grade `recipes.sh clean` against a FIXTURE, never the fleet.
#
# WHY A FIXTURE AND NOT THE BOXES.  Every other bench in this skill may run
# against the real fleet because every other sweep READS.  `clean` deletes
# directories and signals processes, so "test it on a box" means "perform the
# destructive act and see what happened" -- and the failure mode being tested
# for is precisely deleting something that should have been kept.  A fixture
# makes the wrong answer observable without costing a live agent.
#
# The fixture is 11 session dirs covering every class the classifier has, plus
# a fake /proc so pid liveness is controllable, plus a fake `kill` so the
# reaping arm can be exercised with no signal ever leaving this process tree.
# `ghcp-clean.sh` reads HOMEROOT / PROCFS / KILLCMD for exactly this purpose;
# all three default to the real ones, so a live run is untouched by them.
#
# MUTATION-TESTED, which is the only thing that makes a green bench mean
# anything: four rules are broken one at a time and each must produce a
# DIFFERENT survivor set.  A mutant that still passes means the bench is
# decoration.  (`floor` initially did pass -- the fixture had no young
# lockless dir to protect, so the rule was untested.  That gap is why the
# kkkk-starting case exists.)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN="$HERE/../ghcp-clean.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ---- the fixture ---------------------------------------------------------
build_fixture() {
    local R=$1 S now
    rm -rf "$R"; mkdir -p "$R/root/.copilot/session-state"
    S="$R/root/.copilot/session-state"; now=$(date +%s)
    mk() { # id state age-seconds pid('-' = no lock)
        local id=$1 st=$2 age=$3 pid=$4 t
        mkdir -p "$S/$id"/{checkpoints,files}
        [ "$pid" != "-" ] && echo "$pid" > "$S/$id/inuse.$pid.lock"
        if [ "$st" != NOLOG ]; then
            case $st in
                WAIT) t=assistant.turn_end;;
                ERR)  t=session.error;;
                *)    t=tool.execution_start;;
            esac
            printf '{"type":"user.message","data":{"content":"q %s"}}\n{"type":"%s"}\n' \
                "$id" "$t" > "$S/$id/events.jsonl"
            touch -d "@$(( now - age ))" "$S/$id/events.jsonl"
        fi
        printf 'name: sess-%s\n' "$id" > "$S/$id/workspace.yaml"
        # mtime LAST: writing a file into the dir resets it, so an earlier
        # touch is silently undone.  (Found by this bench: a 300000s-old dir
        # reported 26s and the age rule could not be graded at all.)
        touch -d "@$(( now - age ))" "$S/$id"
    }
    mk aaaa-stale-old    WAIT  400000 -        # STALE  no lock at all
    mk bbbb-stale-nolog  NOLOG 300000 -        # STALE  no lock, no log
    mk cccc-deadpid      WAIT  200000 999001   # STALE  lock, but pid is dead
    mk dddd-busy         BUSY       3 900001   # LIVE   working now
    mk eeee-idle         WAIT  200000 900002   # IDLE   parked, pid is ALONE
    mk ffff-self         WAIT  200000 900003   # SELF   protected by PROTECT
    mk gggg-pair-idle    WAIT  200000 900004   # IDLE   but pid shared with...
    mk hhhh-pair-busy    BUSY       5 900004   # ...this one -> HAZARD 1 VETO
    mk iiii-fresh-nolog  NOLOG     10 900005   # LIVE   started, log not yet
    mk jjjj-idle-young   WAIT     600 900006   # LIVE   parked under IDLE_AGE
    mk kkkk-starting     NOLOG     30 -        # YOUNG  dir before its lock
    cat > "$R/root/.copilot/open-sessions-state.json" <<'J'
{
  "aaaa-stale-old": {"schemaVersion":1,"working":false},
  "zzzz-long-gone": {"schemaVersion":1,"working":true},
  "dddd-busy":      {"schemaVersion":1,"working":true}
}
J
    # fake /proc: 999001 deliberately ABSENT so cccc-deadpid is a dead lock
    rm -rf "$R/proc"; mkdir -p "$R/proc"
    local p
    for p in 900001 900002 900003 900004 900005 900006; do
        mkdir -p "$R/proc/$p"
        printf 'copilot --model claude-opus-5 --allow-all\0' > "$R/proc/$p/cmdline"
    done
    # fake kill: removes the fake /proc entry, signals nothing
    cat > "$R/kill.sh" <<'K'
#!/usr/bin/env bash
case "$1" in -TERM|-KILL) rm -rf "$PROCFS/$2";; *) exit 1;; esac
K
    chmod +x "$R/kill.sh"
}

run_clean() { # $1=script  $2=mode  -> prints counts line + SURVIVORS
    local script=$1 mode=$2 R="$WORK/tree"
    build_fixture "$R"
    HOMEROOT="$R" PROCFS="$R/proc" KILLCMD="$R/kill.sh" \
    PROTECT="ffff-self" MODE="$mode" IDLE_AGE=86400 KILL_IDLE=1 MIN_AGE=3600 \
        bash "$script" | head -1
    printf 'SURVIVORS: %s\n' "$(ls "$R/root/.copilot/session-state" | paste -sd,)"
    printf 'REGISTRY: %s\n' "$(jq -c 'keys' "$R/root/.copilot/open-sessions-state.json" 2>/dev/null)"
}

pass=0; fail=0
ck() { # name expected actual
    if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
    else fail=$((fail+1)); printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$1" "$2" "$3"; fi
}

echo "== APPLY on the fixture =="
out=$(run_clean "$CLEAN" apply)
printf '%s\n' "$out" | sed 's/^/   /'
counts=$(printf '%s\n' "$out" | head -1)
surv=$(printf '%s\n'  "$out" | sed -n 's/^SURVIVORS: //p')
reg=$(printf '%s\n'   "$out" | sed -n 's/^REGISTRY: //p')

# 1. the four STALE/IDLE dirs go, the seven keepers stay
ck "removes 3 stale + 1 idle, keeps 7" \
   "RM=4 KILL=1 VETO=1 KEPT=6 PRUNED=2 MODE=apply" "$counts"
# 2. HAZARD 1: the shared pid's idle session SURVIVES
ck "HAZARD 1 -- shared pid vetoes its idle session" \
   "dddd-busy,ffff-self,gggg-pair-idle,hhhh-pair-busy,iiii-fresh-nolog,jjjj-idle-young,kkkk-starting" \
   "$surv"
# 3. HAZARD 2: registry pruned to exactly the surviving keys
ck "HAZARD 2 -- registry pruned to live dirs only" '["dddd-busy"]' "$reg"

echo
echo "== REPORT mode must CHANGE NOTHING (the default is not destructive) =="
R="$WORK/tree"; build_fixture "$R"
before=$(ls "$R/root/.copilot/session-state" | paste -sd,)
HOMEROOT="$R" PROCFS="$R/proc" KILLCMD="$R/kill.sh" PROTECT="ffff-self" \
  MODE=report IDLE_AGE=86400 KILL_IDLE=1 MIN_AGE=3600 bash "$CLEAN" >/dev/null
after=$(ls "$R/root/.copilot/session-state" | paste -sd,)
ck "report leaves every dir in place" "$before" "$after"
ck "report leaves every pid alive"    "900001,900002,900003,900004,900005,900006" \
   "$(ls "$R/proc" | paste -sd,)"

echo
# THE FINGERPRINT IS COUNTS + SURVIVORS, NOT SURVIVORS ALONE.  Found by this
# bench: the `deadpid` mutant (treat every locked pid as alive) leaves the
# IDENTICAL survivor set -- cccc-deadpid is removed either way -- but reaches
# it by SIGNALLING A PROCESS that the baseline never touches (KILL=1 -> 2).
# "Same dirs remain" and "same acts performed" are different claims, and only
# the second one is safety.  Graded on survivors alone the mutant passed.
echo "== MUTATION: each broken rule must give a DIFFERENT answer =="
base_surv="$surv"
base_fp="$counts|$base_surv"
for m in veto self floor deadpid idleage; do
    cp "$CLEAN" "$WORK/mut.sh"
    case $m in
      veto)    sed -i 's/if \[ -n "${PID_HAS_BUSY\[\$p\]:-}" \]; then/if false; then/' "$WORK/mut.sh";;
      self)    sed -i 's/^PROTECT=" ${PROTECT:-} "$/PROTECT="  "/'                     "$WORK/mut.sh";;
      floor)   sed -i 's/^MIN_AGE=${MIN_AGE:-3600}$/MIN_AGE=0/'                        "$WORK/mut.sh";;
      deadpid) sed -i 's/if grep -aqs copilot "\$PROCFS\/\$q\/cmdline"; then/if true; then/' "$WORK/mut.sh";;
      idleage) sed -i 's/\[ "\$ag" -ge "\$IDLE_AGE" \]/true/'                          "$WORK/mut.sh";;
    esac
    mo=$(run_clean "$WORK/mut.sh" apply)
    ms="$(printf '%s\n' "$mo" | head -1)|$(printf '%s\n' "$mo" | sed -n 's/^SURVIVORS: //p')"
    if [ "$ms" = "$base_fp" ]; then
        fail=$((fail+1)); printf 'FAIL mutant %-8s UNDETECTED -- the rule is not graded\n' "$m"
    else
        pass=$((pass+1)); printf 'ok   mutant %-8s caught (%s)\n' "$m" "${ms%%|*}"
    fi
done

echo
printf '%d/%d\n' "$pass" $((pass+fail))
[ "$fail" -eq 0 ]
