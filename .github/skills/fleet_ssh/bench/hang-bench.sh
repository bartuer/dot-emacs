#!/usr/bin/env bash
# hang-bench.sh -- A LOST HOST MUST NOT COST YOU THE SESSION.
#
# WHY THIS EXISTS: a hung box is not a slow table, it is a DEAD SESSION.
# A foreground tool call that blocks past ~120s makes the CLI emit
# `tool.execution_partial_result`, the session host has a fixed 120s budget
# to ack it, a host pinned by that same call misses the budget, and the
# session dies with "session host did not acknowledge ... within 120s" --
# unrecoverable, because resuming replays the same stall.  357 such
# failures in one evening (REPL/fix.archive/survive_lost_host.md).  So the
# sweep MUST self-terminate, and that property needs a test that can run
# anywhere -- not a story about the fleet.
#
# :*** THE FIXTURE IS THE WHOLE POINT: A BOX THAT ANSWERS, THEN STOPS. ***
# A DARK box (no SYN/ACK) is the EASY case -- `ConnectTimeout` already
# covers it, and a fixture built from an unroutable ip PASSES WITHOUT
# TESTING ANYTHING: it returns `(unreachable)` in ~1s whether or not the
# cap exists.  The failure that killed the sessions is the box that
# COMPLETES THE TCP HANDSHAKE AND THE SSH BANNER AND THEN GOES SILENT, so
# that is what `silent_server` fakes -- it sends one banner line and then
# holds the fd open forever, never sending KEXINIT.  `ssh` waits for it
# forever, which is exactly the point.
#
# Arms:
#   1 CONTROL    ConnectTimeout alone vs the silent server -- MUST NOT bound
#   2 CAP        the wrapper against the same server        -- MUST bound
#   3 HEALTHY    a real sshd -- the cap must cost a live sweep NOTHING
#   4 MIXED      live + hung together -- good rows MUST survive the hung one
#   5 CUT        a probe killed mid-flight MUST NOT render as a healthy row
#   6 RC         a timed-out box MUST NOT chain a failure up to the caller
#
# Usage:  bench/hang-bench.sh
# Exit:   0 all arms pass · 1 any arm failed
set -uo pipefail

W="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fleet-ssh.sh"
TMP=$(mktemp -d); pass=0; fail=0
# Kill the fixtures on EVERY exit path.  A bench that leaks a listener
# makes the NEXT run bind-fail and look like a code regression.
cleanup() {
    [ -f "$TMP/silent.pid" ] && kill "$(cat "$TMP/silent.pid")" 2>/dev/null
    [ -f "$TMP/run/sshd.pid" ] && kill "$(cat "$TMP/run/sshd.pid")" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

ck() { # name expected actual
    if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok   %s\n' "$1"
    else fail=$((fail+1)); printf 'FAIL %s\n       want: %s\n       got:  %s\n' "$1" "$2" "$3"; fi
}
# Elapsed whole seconds of a command, so a bound can be asserted as a NUMBER.
elapsed() { local s=$SECONDS; "$@" >/dev/null 2>&1; echo $(( SECONDS - s )); }

# Pick free ports rather than hardcoding: a hardcoded port collides with a
# real service (2222 is the CONTAINER port on this fleet) and the bench
# then measures something else entirely.
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }
HUNG=$(free_port); LIVE=$(free_port)

# --- fixture 1: the SILENT server (banner, then nothing, forever) --------
cat > "$TMP/silent.py" <<'PY'
import socket, sys, threading, time
port = int(sys.argv[1])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(64)
held = []                      # keep every fd OPEN: established, but mute
def serve():
    while True:
        c, _ = s.accept()
        try: c.sendall(b"SSH-2.0-OpenSSH_9.6\r\n")   # complete the banner...
        except Exception: pass
        held.append(c)                               # ...then go silent
threading.Thread(target=serve, daemon=True).start()
time.sleep(100000)
PY
python3 "$TMP/silent.py" "$HUNG" & echo $! > "$TMP/silent.pid"

# --- fixture 2: a REAL sshd, so "healthy" is measured, not assumed ------
have_sshd=0
if command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; then
    SSHD=$(command -v sshd || echo /usr/sbin/sshd)
    ssh-keygen -q -t ed25519 -f "$TMP/hostkey" -N '' 2>/dev/null
    ssh-keygen -q -t ed25519 -f "$TMP/id_t"    -N '' 2>/dev/null
    cp "$TMP/id_t.pub" "$TMP/authk"; chmod 600 "$TMP/authk" "$TMP/hostkey"
    mkdir -p "$TMP/run"
    cat > "$TMP/sshd.conf" <<C
Port $LIVE
ListenAddress 127.0.0.1
HostKey $TMP/hostkey
PidFile $TMP/run/sshd.pid
AuthorizedKeysFile $TMP/authk
UsePAM no
PermitRootLogin yes
PasswordAuthentication no
StrictModes no
C
    "$SSHD" -f "$TMP/sshd.conf" -E "$TMP/sshd.log" 2>/dev/null && have_sshd=1
fi

cat > "$TMP/config" <<C
Host c90wsl c91wsl
    HostName 127.0.0.1
    Port $LIVE
    User root
    IdentityFile $TMP/id_t
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
Host c99wsl
    HostName 127.0.0.1
    Port $HUNG
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
C
export FLEET_SSH_CONFIG="$TMP/config"
sleep 1

echo "== 0. STAGE 0 -- is the fixture actually being DIALLED? =="
# :*** WITHOUT THIS ARM THE WHOLE BENCH CAN PASS WITHOUT TESTING ANYTHING. ***
# MEASURED 2026-09-23 against the pre-fix wrapper: `FLEET_SSH_CONFIG` was
# honoured by box discovery and the ctr tier but NEVER passed to the
# distro-tier `ssh`, so the sweep fell back to ~/.ssh/config, `c99wsl`
# resolved to nothing, and the hung-box arm returned `(unreachable)` in
# 0s -- which scores as "the cap worked".  A bounded-time assertion
# cannot tell "the cap fired" from "we never dialled".  So prove the
# config reaches ssh FIRST: a LIVE box must answer through it.  If this
# arm fails, every timing number below is meaningless.
if [ "$have_sshd" = 1 ]; then
    ck "FLEET_SSH_CONFIG reaches the distro-tier ssh (live box answers)" "yes" \
       "$("$W" -b c90 hn='hostname' 2>/dev/null | tail -1 | grep -q '(unreachable)' && echo "no -- config ignored, timings below are meaningless" || echo yes)"
else
    echo "     SKIP -- no sshd available to prove the dial"
fi

echo
echo "== 1. CONTROL -- ConnectTimeout is NOT a hang guard =="
# The arm that justifies the whole fix.  If `ssh` returns here on its own,
# the fixture is not reproducing a post-banner stall and NOTHING below is
# meaningful -- so this is asserted, not assumed.  `timeout 20` is the
# TEST's cap: rc=124 means ssh never returned, which is the bug.
t=$SECONDS
timeout 20 ssh -F "$TMP/config" -o BatchMode=yes -o ConnectTimeout=5 c99wsl true >/dev/null 2>&1
rc=$?; el=$(( SECONDS - t ))
ck "ConnectTimeout=5 does NOT bound a post-banner stall (killed by test cap at 20s)" \
   "124" "$rc"
printf '     unbounded arm ran %ss with ConnectTimeout=5\n' "$el"

echo
echo "== 2. CAP -- the wrapper bounds the same box =="
el=$(elapsed env FLEET_SSH_CMD_TIMEOUT=8 "$W" -b c99 hn='hostname')
# BOUNDED BELOW AS WELL AS ABOVE.  An instant return does NOT prove the
# cap fired -- it is the signature of never having dialled at all (see
# arm 0).  A real post-banner stall must consume the cap, so require the
# sweep to have ACTUALLY WAITED for it: 8s cap => at least ~5s.
ck "cap=8 terminates the sweep (<=14s)" "yes" "$([ "$el" -le 14 ] && echo yes || echo "no:${el}s")"
ck "...and it WAITED for the cap (>=5s, so it truly dialled the stall)" "yes" \
   "$([ "$el" -ge 5 ] && echo yes || echo "no:${el}s -- returned instantly, fixture not dialled")"
printf '     bounded arm ran %ss\n' "$el"
out=$(FLEET_SSH_CMD_TIMEOUT=8 "$W" -b c99 hn='hostname' 2>/dev/null | tail -1)
ck "a capped box renders (unreachable)" "yes" \
   "$(echo "$out" | grep -q '(unreachable)' && echo yes || echo "no:[$out]")"

if [ "$have_sshd" = 1 ]; then
echo
echo "== 3. HEALTHY -- the cap must cost a live sweep NOTHING =="
el=$(elapsed "$W" -b c90,c91 hn='hostname' k='echo ok')
ck "live 2-box sweep stays fast (<=10s)" "yes" "$([ "$el" -le 10 ] && echo yes || echo "no:${el}s")"
rows=$("$W" -b c90,c91 hn='hostname' k='echo ok' 2>/dev/null | tail -n +2 | grep -c 'ok')
ck "both live boxes answered" "2" "$rows"

echo
echo "== 4. MIXED -- one hung box must not poison the good rows =="
# THE REGRESSION THAT MATTERS.  Before the cap, one wedged box held the
# `parallel` slot and the sweep never returned -- taking the session with
# it.  The good rows must still be there, and the hung one must degrade.
mix=$(FLEET_SSH_CMD_TIMEOUT=8 "$W" -b c90,c91,c99 hn='hostname' k='echo ok' 2>/dev/null)
ck "live rows survive alongside a hung box" "2" "$(echo "$mix" | grep -c 'ok')"
ck "the hung box alone is (unreachable)"     "1" "$(echo "$mix" | grep -c '(unreachable)')"

echo
echo "== 5. CUT -- a truncated probe must NOT look healthy =="
# :*** THE CAP ITSELF CAN PRODUCE A CONFIDENT WRONG TABLE. ***  Fields are
# emitted one line at a time, so a box killed MID-PROBE has already sent
# the early columns and simply stops.  MEASURED 2026-09-23, 3x25s fields
# vs a 60s cap:  `c90  A  B     ` -- A and B real, C blank.  Blank is the
# cell an HONEST empty answer produces (`-`), so a truncated sweep was
# indistinguishable from a complete one.  The remote now prints a
# `__done__` marker as its last act; columns after the cut say `(cut)`.
cut=$(FLEET_SSH_CMD_TIMEOUT=6 "$W" -b c90 a='echo A' b='sleep 30; echo B' 2>/dev/null | tail -1)
ck "columns cut by the cap are NAMED, not blank" "yes" \
   "$(echo "$cut" | grep -q '(cut)' && echo yes || echo "no:[$cut]")"
ck "columns that DID answer are kept" "yes" \
   "$(echo "$cut" | grep -q 'A' && echo yes || echo "no:[$cut]")"
# `-` (answered, no output) and `(cut)` (never ran) are OPPOSITE facts.
hon=$("$W" -b c90 a='echo A' b='true' 2>/dev/null | tail -1)
ck "an honest empty answer is still '-', not '(cut)'" "yes" \
   "$(echo "$hon" | grep -q -- '-' && ! echo "$hon" | grep -q '(cut)' && echo yes || echo "no:[$hon]")"
# The marker is transport, not data: it must never become a column.
ck "the __done__ marker never renders as a column" "yes" \
   "$("$W" -b c90 a='echo A' 2>/dev/null | grep -qi '__done__' && echo "no" || echo yes)"
fi

echo
echo "== 6. RC -- a lost host must not chain a failure up =="
# The trap that turns one dead box into a dead PIPELINE.  Recipes run
# under `set -u` and many callers test rc; a capped box is a DEGRADED
# CELL, not an error, and must exit 0 or every sweep containing one
# broken box fails its caller too.
FLEET_SSH_CMD_TIMEOUT=5 "$W" -b c99 hn='hostname' >/dev/null 2>&1
ck "table mode exits 0 despite a timed-out box" "0" "$?"
FLEET_SSH_CMD_TIMEOUT=5 "$W" -R -b c99 hn='hostname' >/dev/null 2>&1
ck "raw mode exits 0 despite a timed-out box" "0" "$?"

echo
printf '%s/%s hang checks pass\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
