#!/usr/bin/env bash
# room-e2e-islands.sh -- plan 36 C.4 :test_tool:  one room across 3 islands.
#   1. one poster per island (cj06 main, c00 odsp, c16 sydney), 30 posts each:
#      90/90 ids on all three hubs; each reader's FIRST hub is its island's
#   2. partition: sydney's hub refuses appends (chattr +i on the scratch file)
#      and the sydney reader cannot reach it (ROOM_GATEWAYS alias with no
#      route).  10 posts from main + 10 from sydney land on the two live hubs;
#      the sydney reader fails over and sees each id once.  Lift it: the NEXT
#      full post runs heal by itself (C.3, no clock) -> same id set (md5) x3
#   3. a task posted from c16 is owned by the sydney dispatcher only
#      (room-dispatch.py dry-run as each island: 1 owner, 2 skip)
#   4. one verdict row per box (R-FLEET).  No sleep/timeout (R-AWAIT).
# Scratch hubs: main=cj06c odsp=c00c (containers), sydney=c16wsl -- c16 has no
# docker and c14c/c15c are unreachable (MEASURED 2026-09-26).  Nothing here
# kills sshd: the partition is a file flag + a dead alias, so the A.3 run-1
# accident (sshd killed on a live distro) cannot happen.
set -uo pipefail
cd "$(dirname "$0")/../../.."
MAIN=${ROOM_ISL_MAIN:-cj06c} ODSP=${ROOM_ISL_ODSP:-c00c} SYD=${ROOM_ISL_SYD:-c16wsl}
declare -A POSTER=([main]=cj06 [odsp]=c00 [sydney]=c16) HUBOF=([main]=$MAIN [odsp]=$ODSP [sydney]=$SYD)
unset ROOM_FILE ROOM_HUB ROOM_HUBS
export ROOM_GATEWAYS="main=$MAIN,odsp=$ODSP,sydney=$SYD" ROOM_DIR=/var/lib/agent-room/isl.$$ ROOM_CHANNELS=fleet
F=$ROOM_DIR/fleet.jsonl HUBS3="$MAIN $ODSP $SYD"
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "PASS $*"; }
x() { ssh -o BatchMode=yes "$@"; }
cleanup() { x "$SYD" "chattr -i $F 2>/dev/null"; for h in $HUBS3; do x "$h" "rm -rf $ROOM_DIR" 2>/dev/null; done
            for b in cj06 c00 c16; do x "${b}wsl" "rm -f ~/.copilot/room-heal.*isl.$$*" 2>/dev/null; done; }
trap cleanup EXIT
for b in "${POSTER[@]}"; do echo "$b"; done | parallel -j3 \
  "scp -q -o BatchMode=yes bin/room.py bin/fleet-ips.json {}wsl:/tmp/" || fail "scp"
for h in $HUBS3; do x "$h" "mkdir -p $ROOM_DIR && touch $F" || fail "mkdir $h"; done
R="ROOM_GATEWAYS=$ROOM_GATEWAYS ROOM_DIR=$ROOM_DIR python3 /tmp/room.py"
ids() { x "$1" "cat $F" | jq -R -r 'fromjson? | .id' | sort -u; }

# 1. 30 posts per island, in parallel; first hub per reader
for isl in main odsp sydney; do echo "$isl ${POSTER[$isl]}"; done | parallel --colsep ' ' -j3 \
  "ssh -o BatchMode=yes {2}wsl 'for i in \$(seq 1 30); do ROOM_FROM={1}-\$i $R post finding \"isl {1} \$i\" >/dev/null || echo BAD; done; echo {1} done'" \
  > /tmp/isl.$$.1
grep -q BAD /tmp/isl.$$.1 && fail "1 a post failed: $(cat /tmp/isl.$$.1)"
for isl in main odsp sydney; do
  h=${HUBOF[$isl]}; n=$(ids "$h" | wc -l)
  first=$(x "${POSTER[$isl]}wsl" "ROOM_GATEWAYS=$ROOM_GATEWAYS python3 -c 'import sys;sys.path.insert(0,\"/tmp\");import room;print(room.HUBS[0])'")
  printf '   %-7s poster=%-4s hub=%-7s ids=%s/90 reader_first_hub=%s\n' "$isl" "${POSTER[$isl]}" "$h" "$n" "$first"
  [ "$n" = 90 ] && [ "$first" = "$h" ] || fail "1 $isl ids=$n first=$first (want 90, $h)"
done
pass "1 90/90 ids on all three hubs; every reader's first hub is its own island's"

# 2. partition sydney
x "${POSTER[sydney]}wsl" "ROOM_FROM=rs $R read >/dev/null"                      # cursor at 90
x "$SYD" "chattr +i $F" || fail "2 chattr"
x "$SYD" "echo x >> $F" 2>/dev/null && fail "2 sydney hub still takes appends"
DEAD="main=$MAIN,odsp=$ODSP,sydney=${SYD%wsl}dead.invalid"   # sydney reader: its hub unreachable
for isl in main sydney; do echo "$isl ${POSTER[$isl]}"; done | parallel --colsep ' ' -j2 \
  "ssh -o BatchMode=yes {2}wsl 'for i in \$(seq 1 10); do ROOM_FROM=p-{1}-\$i $R post finding \"part {1} \$i\" 2>>/tmp/isl.$$.err >/dev/null || echo BAD; done; grep -c \"heal runs\" /tmp/isl.$$.err; rm -f /tmp/isl.$$.err'" \
  > /tmp/isl.$$.2
grep -q BAD /tmp/isl.$$.2 && fail "2 a post failed during the partition"
x "${POSTER[sydney]}wsl" "ROOM_GATEWAYS=$DEAD ROOM_FROM=rs ROOM_DIR=$ROOM_DIR python3 /tmp/room.py read 2>/dev/null" > /tmp/isl.$$.rs
got=$(jq -r .id /tmp/isl.$$.rs | wc -l); uq=$(jq -r .id /tmp/isl.$$.rs | sort -u | wc -l)
nm=$(ids "$MAIN" | wc -l); no=$(ids "$ODSP" | wc -l); ns=$(ids "$SYD" | wc -l)
echo "   partition: $MAIN=$nm $ODSP=$no $SYD=$ns ids; partial-post warnings main,sydney=$(tr '\n' ' ' </tmp/isl.$$.2)"
[ "$nm" = 110 ] && [ "$no" = 110 ] && [ "$ns" = 90 ] || fail "2a live hubs must hold 110, sydney 90"
[ "$got" = 20 ] && [ "$uq" = 20 ] || fail "2b sydney reader got=$got distinct=$uq of 20 (failover)"
pass "2a 20/20 partition posts landed on the two live hubs; sydney hub missed them"
pass "2b sydney reader failed over past its dead hub: 20 ids, each once"
x "$SYD" "chattr -i $F"
# C.3: the next post that lands on ALL hubs is the recovery event -> heal
x "${POSTER[sydney]}wsl" "ROOM_FROM=rec $R post finding recovered 2>&1 >/dev/null" | sed 's/^/   /'
im=$(ids "$MAIN" | md5sum); io=$(ids "$ODSP" | md5sum); is=$(ids "$SYD" | md5sum); ns=$(ids "$SYD" | wc -l)
[ "$im" = "$io" ] && [ "$io" = "$is" ] && [ "$ns" = 111 ] || fail "2c after recovery ids $ns md5 $im/$io/$is"
pass "2c the first full post after recovery healed: all three hubs hold the same 111 ids"

# 3. owner island
T=$(x "${POSTER[sydney]}wsl" "ROOM_FROM=poster-syd $R post task 'isl e2e task' --ref x@0 --repo cluster@master --needs '{\"tier\":\"wsl\"}' --done-when true") \
  || fail "3 task post"
for isl in main odsp sydney; do
  row=$(ORCH_SELF=${POSTER[$isl]} python3 bin/room-dispatch.py fleet 2>/dev/null | grep -P "\t$T\t")
  printf '   dispatcher@%-7s %s\n' "$isl" "$(echo "$row" | grep -oE 'owner=[a-z]+(\(skip\))?')"
  case $isl:$row in sydney:*owner=sydney*skip*|sydney:) fail "3 sydney does not own $T";;
                    sydney:*owner=sydney*) ;;
                    *:*owner=sydney\(skip\)*) ;;
                    *) fail "3 $isl row: $row";; esac
done
pass "3 task $T from c16: owned by the sydney dispatcher only (1 owner, 2 skip)"
rm -f /tmp/isl.$$.*
echo "ALL PASS"
