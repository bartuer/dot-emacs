#!/usr/bin/env bash
# room-swarm-e2e.sh -- plan 36 B.4 :test_tool: (v2 goals V1-V4 in one run).
#
# 2 boxes (cj07 wsl, cj01 wsl) + 1 container (c10c), scratch channel +
# scratch registry on the real hubs, one room-dispatch.py.  No worker is
# joined when the tasks land; each worker is a scripted fake CLI
# (.github/REPL/36.u3.fake-copilot.py) in a tmux pane on its box, so the
# test costs no LLM and is repeatable.  The slot-spawn path (a REAL CLI) is
# covered by 36.u3.dispatch.test.sh case B, not repeated here.
#
#   T1 needs tier:ctr        -> claimed by the c10c fake (held), claimant
#                               killed -> reopened, reclaimed by fake #2
#   T2 deps on T1            -> not claimable until T1 done; wsl fake does it
#   T3 review:true           -> done -> review (to human) -> human ack closes
#   T4 ctr + excel           -> no container has wserver -> "no worker"
#   T5 wsl, claimant in ask_user -> NOT reclaimed, hitl to=human
#   dispatcher restarted mid-run -> reattach, 0 new placements
#
# No sleep/timeout (R-AWAIT): every wait is `tail -F | grep -m1` on a log.
set -u
cd "$(dirname "$0")/../../.."
N=$$ S=/tmp/swarm.$N; mkdir -p "$S"
CH=swarm$N
export ORCH_REGISTRY=/var/lib/orch/swarm.$N.jsonl ROOM_SPAWN_CAP=1
# Pinned hubs: the container reaches cj10wsl/cj11wsl through its distro
# (c10c ~/.ssh/config "room hubs" block); it has no gateway aliases yet.
export ROOM_HUBS=${ROOM_HUBS:-cj10wsl,cj11wsl}; HUBS=$ROOM_HUBS
W=cj07 C=c10c                 # wsl worker box, container worker host
FAKE=.github/REPL/36.u3.fake-copilot.py
fails=0
ok() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1  ($2)"; fails=$((fails+1)); fi; }
await() { grep -m1 -q -- "$2" < <(tail -n +1 -F "$1" 2>/dev/null); }
hub() { ssh -o BatchMode=yes "${HUBS%%,*}" "$@"; }
reg() { hub "cat $ORCH_REGISTRY 2>/dev/null" | grep "\"unit\": \"$1\"" | grep -c "\"event\": \"$2\""; }
lines() { hub "cat /var/lib/agent-room/$CH.jsonl"; }
kind_re() { lines | python3 -c "import json,sys;print(sum(1 for l in sys.stdin if (m:=json.loads(l))['kind']=='$1' and m.get('reply_to')=='$2' ${3:+and $3}))"; }
post() { ROOM_FROM=swarm-human bin/room.sh -c "$CH" post "$@"; }
task() { local t=$1; shift; post task "$t" --ref none --repo cluster@master --done-when true "$@"; }
disp() { setsid env ROOM_BRIDGE="cat >> $S/bridge.jsonl" bin/room-dispatch.py "$CH" --watch --boxes cj07,cj01 >"$1" 2>&1 & echo $!; }
# fake NAME HOST MODE: a joined scripted CLI in tmux on HOST; its stdout -> $S/NAME.out
fake() {
    ssh -o BatchMode=yes "$2" "cd /workspace/cluster && tmux new-session -d -s $1 -c /workspace/cluster \
        -e ROOM_FROM=$1 -e FAKE_MODE=$3 -e ROOM_HUBS=$HUBS \
        'bin/room.sh -c $CH post join \"swarm fake up\" --repos cluster >/dev/null; exec python3 $FAKE > /tmp/$1.out 2>&1'"
    ( ssh -o BatchMode=yes "$2" "tail -n +1 -F /tmp/$1.out" > "$S/$1.out" 2>/dev/null & )
    await "$S/$1.out" "FAKE sid="
}
kill_fake() { ssh -o BatchMode=yes "$2" "tmux kill-session -t '=$1:' 2>/dev/null; true"; }
cleanup() {
    [ -n "${DP:-}" ] && kill -- -"$DP" 2>/dev/null
    for f in sw-ctr1-$N sw-ctr2-$N; do kill_fake "$f" $C; done
    for f in sw-wsl-$N sw-hitl-$N; do kill_fake "$f" $W; done
    for h in $W $C; do ssh -o BatchMode=yes $h "rm -f /tmp/sw-*-$N.out; \
        grep -l swarm$N ~/.copilot/session-state/*/events.jsonl 2>/dev/null | xargs -r dirname | xargs -r rm -rf"; done
    for h in ${HUBS//,/ }; do ssh -o BatchMode=yes "$h" "rm -f /var/lib/agent-room/$CH.jsonl* $ORCH_REGISTRY $ORCH_REGISTRY.lock"; done
    pkill -f "tail -n +1 -F /tmp/sw-.*-$N.out" 2>/dev/null; pkill -f "tail -n +1 -F $S" 2>/dev/null
    rm -rf "$S"
}
trap cleanup EXIT
for h in $W $C cj01; do ssh -o BatchMode=yes $h 'cd /workspace/cluster && git pull -q --ff-only 2>&1 | grep -v -i lfs'; done >/dev/null

# ---- tasks first, no worker joined (open tasks wait for a join, V2)
T1=$(task "swarm T1: ctr work" --needs '{"tier":"ctr"}')
T2=$(task "swarm T2: after T1" --needs '{"tier":"wsl"}' --deps "$T1")
T3=$(task "swarm T3: reviewed" --needs '{"tier":"wsl"}' --review)
T4=$(task "swarm T4: excel in a ctr" --needs '{"tier":"ctr","excel":true}')
echo "T1=$T1 T2=$T2 T3=$T3 T4=$T4"
DP=$(disp "$S/d1.log")
# T4: every container lacks wserver -> the claimant's gate passes it; with
# no ctr worker yet and no ctr spawn box, the human hears "no worker" (V4).
await "$S/bridge.jsonl" "no worker for $T4"
ok "T4 no worker -> human"  'grep -q "no worker for $T4" "$S/bridge.jsonl"'

# ---- the container worker claims T1 and holds it
fake sw-ctr1-$N $C hold
await "$S/sw-ctr1-$N.out" "HOLD $T1"
ok "T1 claimed by ctr fake"  'bin/room.sh -c $CH tasks | grep -q "^$T1	claimed	.*by=sw-ctr1-$N"'
ok "T2 blocked by T1"        'bin/room.sh -c $CH tasks | grep "^$T2" | grep -q "open.*blocked=$T1"'

# ---- restart the dispatcher mid-run: reattach, 0 new placements (f)
before=$(hub "cat $ORCH_REGISTRY" | grep -c '"event": "\(woken\|dispatched\)"')
kill -- -"$DP"; DP=$(disp "$S/d2.log")
await "$S/d2.log" "hold	$T1"
ok "restart: 0 new placements" '[ "$(hub "cat $ORCH_REGISTRY" | grep -c "\"event\": \"\(woken\|dispatched\)\"")" = "$before" ]'

# ---- kill T1's claimant mid-task -> reopened (a joined session is never
# resumed: only spawned slots are), then a 2nd ctr worker reclaims it
kill_fake sw-ctr1-$N $C
fake sw-ctr2-$N $C ""
await "$S/d2.log" "final	$T1"
ok "T1 reclaimed on EXIT"   '[ "$(reg "$T1" reclaimed)" = 1 ] && [ "$(kind_re pass "$T1" "(m.get(\"why\") or \"\").startswith(\"reopen\")")" = 1 ]'
ok "T1 done by 2nd ctr"     'grep -q "final	$T1	done by=sw-ctr2-$N" "$S/d2.log"'

# ---- the wsl worker: T2 (now unblocked) and T3; T5 goes to a hitl fake
fake sw-wsl-$N $W ""
await "$S/d2.log" "final	$T2"
ok "T2 after T1 done"       'lines | python3 -c "import json,sys;L=[json.loads(l) for l in sys.stdin];d=[i for i,m in enumerate(L) if m[\"kind\"]==\"done\" and m.get(\"reply_to\")==\"$T1\"];a=[i for i,m in enumerate(L) if m[\"kind\"]==\"ack\" and m.get(\"reply_to\")==\"$T2\"];sys.exit(not(d and a and min(a)>d[0]))"'
await "$S/bridge.jsonl" "review $T3"
ok "T3 in review -> human"  'bin/room.sh -c $CH tasks | grep -q "^$T3	review"'
post ack "reviewed" --reply-to "$T3" >/dev/null
await "$S/d2.log" "final	$T3"
ok "T3 closed by human ack" 'grep -q "final	$T3	closed" "$S/d2.log"'

ROOM_FROM=sw-wsl-$N bin/room.sh -c "$CH" post leave "wsl fake down" >/dev/null
fake sw-hitl-$N $W hitl
T5=$(task "swarm T5: asks a human" --needs '{"tier":"wsl"}')
await "$S/sw-hitl-$N.out" "HOLD $T5"
await "$S/bridge.jsonl" "claimant sw-hitl-$N of $T5 waits on a human"
ok "T5 hitl -> human, not reclaimed" '[ "$(reg "$T5" reclaimed)" = 0 ] && bin/room.sh -c $CH tasks | grep -q "^$T5	claimed	.*by=sw-hitl-$N"'

# ---- whole-run checks
for t in $T1 $T2 $T3 $T5; do
    ok "claimed once per holder $t" '[ "$(lines | python3 -c "import json,sys,collections;c=collections.Counter(); st=None
for l in sys.stdin:
    m=json.loads(l)
    if m[\"kind\"]==\"ack\" and m.get(\"reply_to\")==\"$t\" and m[\"from\"].startswith(\"sw-\"): c[m[\"from\"]]+=1
print(max(c.values()))")" = 1 ]'
done
ok "0 spawned slots (cap never reached)" '[ "$(hub "cat $ORCH_REGISTRY" | grep -c "\"event\": \"dispatched\"")" = 0 ]'
ok "bridge = only review/hitl/to=human" 'python3 -c "import json,sys;L=[json.loads(l) for l in open(\"$S/bridge.jsonl\")];sys.exit(not L or any(m[\"kind\"] not in (\"review\",\"hitl\") and m.get(\"to\")!=\"human\" for m in L))"'
git fetch -q origin 2>/dev/null
ok "done shas on origin/master" 'for r in $(lines | python3 -c "import json,sys;[print(m[\"ref\"]) for l in sys.stdin if (m:=json.loads(l))[\"kind\"]==\"done\"]"); do git merge-base --is-ancestor "$r" origin/master || exit 1; done'
ok "no sleep/timeout in new code" '! grep -nE "\bsleep\b|timeout" bin/room-dispatch.py "$0" | grep -v "No sleep/timeout\|grep -nE"'
ok "no ERROR in dispatcher" '! grep -h ERROR "$S"/d*.log'

kcount() { lines | python3 -c "import json,sys;print(sum(1 for l in sys.stdin if (m:=json.loads(l))['kind']=='$1' and m['box']=='$2'))"; }
echo "--- verdict per box (R-FLEET)"
for h in $W $C; do
    printf "%s\tacks=%s\tdone=%s\n" "$h" \
        "$(kcount ack "${h%c}")" "$(kcount done "${h%c}")"
done
echo "--- d1"; cat "$S/d1.log"; echo "--- d2"; cat "$S/d2.log"
[ "$fails" = 0 ] && echo "ALL PASS" || { echo "FAILED $fails"; exit 1; }
