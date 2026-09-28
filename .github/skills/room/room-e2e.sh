#!/usr/bin/env bash
# room-e2e.sh -- plan 36 item 2.3 :test_tool:.  Asserts, per step, that:
#   1. session A on box $A posts `hitl` and BLOCKS in `room.sh wait`
#   2. session B on box $B posts a `finding`
#   3. the human (this shell) answers A's hitl with an `ack --reply-to`
#   4. A's wait returns THAT answer, and A's `read` then contains B's finding
#   5. a burst (default 10 boxes x 10 concurrent = 100, 60 KB each) lands 100/100,
#      0 corrupt lines
# v2 (plan 36 A.3), channels + two hubs:
#   6. two channels stay isolated (each its own <chan>.jsonl on the hub)
#   7. a DM (--to NAME) is seen by NAME only
#   8. sshd on the PRIMARY hub is killed mid-burst: 100/100 posts land, a
#      reader that reads before, during and after gets every id exactly once,
#      `heal` makes both hubs hold the same id set; one row per box (R-FLEET)
# No sleep, no timeout: every step awaits a real event (R-AWAIT) -- the kill
# fires when `tail -F` on the primary has seen $KILL_AT lines.  Runs against a
# scratch channel dir on both hubs so the real room is untouched.
# The PRIMARY is a scratch hub whose sshd this test kills and restarts:
# default cj06c, the officeagent-dev container on cj06 (MEASURED 2026-09-26:
# no other session on it; reachable from all 10 burst boxes).  Killing sshd
# kills every ssh session INTO that container -- do not point it at a hub
# anyone else uses.  `systemctl stop ssh` would NOT do: KillMode=process
# leaves the live sessions (and every room mux) running.
# Usage: room-e2e.sh [A_BOX] [B_BOX]      (defaults cj06 cj07)
#   env: ROOM_E2E_PRIMARY=cj06c  ROOM_E2E_SECONDARY=cj00wsl  ROOM_E2E_CTR=officeagent-dev
set -uo pipefail
cd "$(dirname "$0")/../../.."
A=${1:-cj06} B=${2:-cj07}
BURST=${ROOM_BURST_BOXES:-"cj06 cj07 cj01 cj11 cj00 cj08 helix c10 c16 c00"}
P=${ROOM_E2E_PRIMARY:-cj06c} S=${ROOM_E2E_SECONDARY:-cj00wsl} CTR=${ROOM_E2E_CTR:-officeagent-dev}
KILL_AT=${ROOM_E2E_KILL_AT:-30}
unset ROOM_FILE ROOM_HUB
export ROOM_HUBS=$P,$S ROOM_DIR=/var/lib/agent-room/e2e.$$ ROOM_CHANNELS=fleet
F=$ROOM_DIR/fleet.jsonl
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "PASS $*"; }
ctr() { printf '%s\n' "$1" | ssh -o BatchMode=yes "${P%c}wsl" docker exec -i "$CTR" sh; }  # script on stdin: no quoting layer
cleanup() { ctr 'pgrep -x sshd >/dev/null || /usr/sbin/sshd'
            for h in $P $S; do ssh -o BatchMode=yes "$h" "rm -rf $ROOM_DIR" 2>/dev/null; done; }
trap cleanup EXIT
case $P in *c) ;; *) fail "primary $P is not a container alias: this test kills its sshd";; esac

# ship the tool (the boxes may be on an older checkout)
for b in $A $B $BURST; do echo "$b"; done | sort -u | parallel -j16 \
  "scp -q -o BatchMode=yes bin/room.py {}wsl:/tmp/room.py" || fail "scp room.py"
R="ROOM_HUBS=$ROOM_HUBS ROOM_DIR=$ROOM_DIR python3 /tmp/room.py"

# 1. A posts hitl, prints its id, then blocks on wait, then reads.
exec 3< <(ssh -o BatchMode=yes "${A}wsl" "export ROOM_FROM=A-$A;
  id=\$($R post hitl 'e2e: proceed with step X?' --plan 36 --wi 2.3) || exit 1
  echo \$id; $R wait \$id; echo ---READ---; $R read")
read -r ID <&3 || fail "A did not post"
[ -n "$ID" ] && pass "1 A@$A posted hitl id=$ID and is waiting"

# 2. B posts a finding
ssh -o BatchMode=yes "${B}wsl" "ROOM_FROM=B-$B $R post finding 'e2e: fact-from-B'" >/dev/null \
  || fail "B post"
pass "2 B@$B posted finding"

# 3. human answers
ROOM_FROM=human python3 bin/room.py post ack "e2e: yes, proceed" --reply-to "$ID" >/dev/null \
  || fail "human post"
pass "3 human answered re=$ID"

# 4. A unblocks with the answer, and its read sees B's finding
OUT=$(cat <&3); exec 3<&-
first=$(printf '%s\n' "$OUT" | head -1)
printf '%s' "$first" | jq -e --arg id "$ID" '.reply_to==$id and .from=="human" and .body=="e2e: yes, proceed"' >/dev/null \
  || fail "4 A's wait returned: $first"
pass "4a A's wait returned the human's answer"
printf '%s\n' "$OUT" | sed '1,/---READ---/d' | jq -e 'select(.from=="B-'"$B"'" and .kind=="finding")' >/dev/null \
  || fail "4b A's read lacks B's finding: $OUT"
pass "4b A's read consumed B's finding"

# 5. burst
for h in $P $S; do ssh -o BatchMode=yes "$h" "rm -f $F"; done
printf '%s\n' $BURST | parallel --tag -j10 "ssh -o BatchMode=yes {}wsl '
  for i in \$(seq 1 10); do
    (ROOM_FROM={}-\$i $R post finding \"burst \$(head -c 60000 /dev/zero | tr \"\\0\" x)\" >/dev/null; echo rc=\$?) &
  done | sort | uniq -c | tr \"\n\" \" \"; wait'"
ROOM_FROM=grader python3 bin/room.py read --all --peek > /tmp/e2e.$$.out
n=$(jq -r .from /tmp/e2e.$$.out | sort -u | wc -l)
rm -f /tmp/e2e.$$.out
want=$(( $(printf '%s\n' $BURST | wc -l) * 10 ))
for h in $P $S; do
  lines=$(ssh -o BatchMode=yes "$h" "wc -l < $F")
  [ "$n" = "$want" ] && [ "$lines" = "$want" ] || fail "5 burst on $h distinct=$n lines=$lines of $want"
  pass "5 burst $h: $n/$want distinct, $lines lines, 0 corrupt"
done

# 6. channels isolated
X=$(ROOM_FROM=c6 python3 bin/room.py -c e2ea post finding "only-in-a") || fail "6 post a"
Y=$(ROOM_FROM=c6 python3 bin/room.py -c e2eb post finding "only-in-b") || fail "6 post b"
ra=$(ROOM_FROM=r6 python3 bin/room.py -c e2ea read | jq -r .id | tr '\n' ' ')
rb=$(ROOM_FROM=r6 python3 bin/room.py read -c e2eb | jq -r .id | tr '\n' ' ')
onhub=$(ssh -o BatchMode=yes "$P" "grep -c only-in- $ROOM_DIR/e2ea.jsonl $ROOM_DIR/e2eb.jsonl" | tr '\n' ' ')
[ "$ra" = "$X " ] && [ "$rb" = "$Y " ] || fail "6 a-read='$ra' (want $X) b-read='$rb' (want $Y)"
[ "$onhub" = "$ROOM_DIR/e2ea.jsonl:1 $ROOM_DIR/e2eb.jsonl:1 " ] || fail "6 files: $onhub"
pass "6 channels isolated: e2ea sees only $X, e2eb only $Y; one line per <chan>.jsonl"

# 7. DM seen only by its recipient
D=$(ROOM_FROM=c7 python3 bin/room.py -c e2ea post finding "dm-for-bob" --to bob) || fail "7 post"
bob=$(ROOM_FROM=bob python3 bin/room.py -c e2ea read | jq -r 'select(.body=="dm-for-bob")|.id')
eve=$(ROOM_FROM=eve python3 bin/room.py -c e2ea read | jq -r 'select(.body=="dm-for-bob")|.id')
[ "$bob" = "$D" ] && [ -z "$eve" ] || fail "7 bob='$bob' (want $D) eve='$eve' (want none)"
pass "7 DM $D reached bob, not eve"

# 8. kill the primary hub's sshd mid-burst
for h in $P $S; do ssh -o BatchMode=yes "$h" "rm -f $F; touch $F"; done
ROOM_FROM=r8 python3 bin/room.py read >/dev/null                  # cursor at the start
ROOM_FROM=r8 python3 bin/room.py read > /tmp/e2e.$$.r8             # (empty) before
printf '%s\n' $BURST | parallel --tag -j10 "ssh -o BatchMode=yes {}wsl '
  for i in \$(seq 1 10); do
    (ROOM_FROM={}-\$i $R post finding \"kill \$(head -c 6000 /dev/zero | tr \"\\0\" y)\" >/dev/null 2>&1; echo rc=\$?) &
  done | sort | uniq -c | tr \"\n\" \" \"; wait'" > /tmp/e2e.$$.burst &
BP=$!
# the trigger is an event: the KILL_AT-th line appearing on the primary
ssh -o BatchMode=yes "$P" "tail -n +1 -F $F" | awk -v k="$KILL_AT" 'NR>=k{exit}'
ctr 'pkill -x sshd; pkill -f sshd-session; true'
ctr 'pgrep -f "^sshd" >/dev/null' && fail "8 sshd on $P survived the kill"
echo "   killed sshd on $P after $KILL_AT lines (pgrep: none left)"
ROOM_FROM=r8 python3 bin/room.py read >> /tmp/e2e.$$.r8 2>/dev/null  # during: $P down
wait $BP
sed 's/^/   /' /tmp/e2e.$$.burst
ROOM_FROM=r8 python3 bin/room.py read >> /tmp/e2e.$$.r8 2>/dev/null  # after, $P still down
ctr 'mkdir -p /run/sshd; /usr/sbin/sshd'
pass "8a sshd on $P restarted"
python3 bin/room.py heal | sed 's/^/   /'
ROOM_FROM=r8 python3 bin/room.py read >> /tmp/e2e.$$.r8            # $P back, healed
got=$(jq -r .id /tmp/e2e.$$.r8 | wc -l); uniq=$(jq -r .id /tmp/e2e.$$.r8 | sort -u | wc -l)
bad=0
for b in $BURST; do   # R-FLEET: one row per box
  ok=$(grep -oE "(^| )$b"$'\t'" +10 rc=0" /tmp/e2e.$$.burst | wc -l)   # --tag rows share one line
  seen=$(jq -r .from /tmp/e2e.$$.r8 | grep -c "^$b-")
  printf '   %-6s posts_rc0=%s  reader_saw=%s/10\n' "$b" "$([ "$ok" = 1 ] && echo 10 || echo NO)" "$seen"
  [ "$ok" = 1 ] && [ "$seen" = 10 ] || bad=1
done
[ "$bad" = 0 ] || fail "8b a box lost posts or the reader missed some"
[ "$got" = "$want" ] && [ "$uniq" = "$want" ] || fail "8c reader got=$got distinct=$uniq of $want"
pass "8b $want/$want posts landed (rc=0 on every box) with $P killed mid-burst"
pass "8c reader saw each of $want ids exactly once (before/during/after/healed)"
ids() { ssh -o BatchMode=yes "$1" "cat $F" | jq -R -r 'fromjson? | .id' | sort -u; }
ip=$(ids "$P" | md5sum); is=$(ids "$S" | md5sum); np=$(ids "$P" | wc -l)
[ "$ip" = "$is" ] && [ "$np" = "$want" ] || fail "8d after heal $P ids=$np md5 $ip vs $S $is"
pass "8d after heal $P and $S hold the same $np ids"
rm -f /tmp/e2e.$$.r8 /tmp/e2e.$$.burst
echo "ALL PASS"
