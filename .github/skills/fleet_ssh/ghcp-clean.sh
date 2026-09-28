#!/usr/bin/env bash
# ghcp-clean.sh -- per-box GHCP session reaper.  Rides to the box on stdin
# (`bash -s`), which is how every probe in this skill travels: the remote
# shell sees the text verbatim, so no layer reinterprets the quoting.
#
# THIS IS THE SECOND RECIPE THAT WRITES, and the first that DESTROYS.
# `broadcast` copies; this one deletes directories and signals processes.
# So it is a SCRIPT fanned out (R-REPEATABLE), never a probe string built
# at the call site -- and it defaults to `report`, never `apply`.
#
# Env: MODE=report|apply  IDLE_AGE=<s>  KILL_IDLE=0|1  PROTECT="<id id>"
#      MIN_AGE=<s>        HOMEROOT/PROCFS/KILLCMD (fixture injection)
#
# ---------------------------------------------------------------------
# WHAT "NOT RUNNING" AND "IDLE" ACTUALLY MEAN
#
# `ghcp` renders four states (BUSY/WAIT/ERR/NOLOG) but those describe the
# LOG, not the process.  A reaper needs the process fact too, so this
# script classifies every session dir into five classes:
#
#   STALE  no live copilot holds it     -> the dir is garbage, remove it
#   IDLE   live, parked (WAIT|ERR) past IDLE_AGE  -> killable, if alone
#   LIVE   live and working, or parked but young -> keep
#   SELF   named in PROTECT                      -> keep, always
#   YOUNG  lockless but newer than MIN_AGE       -> keep (startup race)
#
# MEASURED on the live fleet 2026-09-21 before any of this ran: 88 session
# dirs across 5 boxes, 11 live locks.  77 dirs -- 112M -- were STALE, and
# c03 alone carried 42 dirs for 3 live sessions.
#
# ---------------------------------------------------------------------
# THE THREE HAZARDS THAT SHAPE THIS SCRIPT.  Each was MEASURED on the
# live fleet, and each one makes the OBVIOUS implementation destructive.
#
# HAZARD 1 -- ONE PROCESS CAN HOLD SEVERAL SESSIONS.  MEASURED on c01:
# pid 34966 holds BOTH 7ba4caa0 (NOLOG) and 7d0cfcfa (WAIT/155846s).  The
# lock is per-SESSION but the kill is per-PROCESS, so "reap this idle
# session" reads as "kill 34966" and takes the other session with it.
# A pid is therefore killable only when EVERY dir it holds is idle; one
# LIVE dir VETOES the pid.  Without the veto the fixture kills 2 pids
# where 1 was due -- mutation-tested, see bench/clean-bench.sh.
#
# HAZARD 2 -- THERE IS A SECOND REGISTRY.  ~/.copilot/
# open-sessions-state.json keys the same uuids independently of the
# directories.  Removing dirs alone leaves entries that outlive their
# directory forever -- MEASURED on c01, d92d5830 sits there
# `"working": true` with no dir lock at all.  So the json is pruned of
# exactly the keys whose dir is now GONE, which keeps it from ever
# disagreeing with the filesystem.  (Pruning by any other rule would be
# a second source of truth; this one is derived from the first.)
#
# HAZARD 3 -- THE DRIVER IS ONE OF THE BOXES.  This cluster is driven
# from a container on c01, so an unguarded fleet sweep deletes the state
# of the session RUNNING it.  PROTECT carries the caller's own session id
# and the recipe fills it from $COPILOT_AGENT_SESSION_ID automatically.
# It is belt-and-braces rather than sufficient on its own: that session is
# also BUSY (it is executing this), so the LIVE rule already spares it --
# but only while it is mid-turn, and a reap scheduled between turns would
# find it WAIT.
#
# :trap: NOLOG IS NOT IDLE.  A session dir exists before its events.jsonl
# does, so a starting agent and a logless corpse look identical in the
# log.  The difference is the LOCK, which is why NOLOG-with-a-live-pid is
# classed LIVE and never reaped on log evidence alone.
#
# :trap: GRADE ON THE RE-READ, NOT ON `kill`\'s rc.  `kill` returns 0 for
# "signal delivered", which is not "process gone".  After TERM this waits
# and re-checks /proc/<pid>/cmdline, escalating to KILL only if the pid is
# still there -- the same "ask the peer afterwards" rule `broadcast` uses.
set -u
MODE=${MODE:-report}
# TESTABILITY: the two roots this script reads are injectable so the same
# code can be graded against a FIXTURE.  Defaults are the real ones, so a
# live run is unaffected; bench/clean-bench.sh sets them to a temp tree.
# Without this the reaping logic could only ever be tested on a real box --
# i.e. tested by running the destructive thing.
HOMEROOT=${HOMEROOT:-}
PROCFS=${PROCFS:-/proc}
KILLCMD=${KILLCMD:-kill}
IDLE_AGE=${IDLE_AGE:-86400}
# A FLOOR UNDER EVERY DELETION, INDEPENDENT OF CLASS.  A session dir is
# created BEFORE its inuse lock is written, so for a short window a STARTING
# agent looks exactly like an abandoned one: dir present, no lock.  This is
# the same race SKILL.md names for NOLOG ("a session dir exists before its
# log does"), and here it is not merely a misreading -- it is a DELETION of
# a live agent's state in its first seconds.  Nothing younger than this is
# ever touched, whatever else says it is stale.  MEASURED on the fixture:
# without the floor a 10s-old lockless dir was reaped.
MIN_AGE=${MIN_AGE:-3600}
KILL_IDLE=${KILL_IDLE:-0}
PROTECT=" ${PROTECT:-} "

now=$(date +%s)

# ---- PASS 1: build the pid -> (busy?) map BEFORE classifying any dir.
# HAZARD 1: one copilot process can hold SEVERAL session dirs.  Killing it
# for one idle session also kills every other session it holds.  So a pid is
# killable only if EVERY dir it holds is idle; one BUSY dir vetoes the pid.
declare -A PID_HAS_BUSY PID_DIRS PID_ALIVE
dirs=()
for d in "$HOMEROOT"/root/.copilot/session-state/*/ "$HOMEROOT"/home/*/.copilot/session-state/*/; do
  [ -d "$d" ] || continue
  dirs+=("${d%/}")
done

livepid_of() {   # $1=dir -> echoes pid if a LIVE copilot holds it, else nothing
  local d=$1 l q
  for l in "$d"/inuse.*.lock; do
    [ -e "$l" ] || continue
    q=${l##*/inuse.}; q=${q%.lock}
    case "$q" in (*[!0-9]*|"") continue;; esac
    if [ -n "${PID_ALIVE[$q]+x}" ]; then
      [ "${PID_ALIVE[$q]}" = 1 ] && { printf '%s' "$q"; return 0; }
      continue
    fi
    if grep -aqs copilot "$PROCFS/$q/cmdline"; then
      PID_ALIVE[$q]=1; printf '%s' "$q"; return 0
    else
      PID_ALIVE[$q]=0
    fi
  done
  return 1
}

state_of() {     # $1=dir -> "STATE AGE"
  local d=$1 e a
  if [ -r "$d/events.jsonl" ]; then
    e=$(tail -1 "$d/events.jsonl" 2>/dev/null | jq -r .type 2>/dev/null)
    a=$(( now - $(stat -c %Y "$d/events.jsonl" 2>/dev/null || echo "$now") ))
  else
    e=""; a=$(( now - $(stat -c %Y "$d" 2>/dev/null || echo "$now") ))
  fi
  case "$e" in
    assistant.turn_end) printf 'WAIT %s' "$a";;
    session.error)      printf 'ERR %s'  "$a";;
    "")                 printf 'NOLOG %s' "$a";;
    *)                  printf 'BUSY %s' "$a";;
  esac
}

# classify once, cache
declare -A D_PID D_STATE D_AGE D_CLASS
for d in "${dirs[@]}"; do
  id=${d##*/}
  p=$(livepid_of "$d") || p=""
  read -r st ag <<<"$(state_of "$d")"
  D_PID[$d]=$p; D_STATE[$d]=$st; D_AGE[$d]=$ag
  if [ -z "$p" ]; then
    # dir age, not log age -- a lockless dir may have no log at all
    da=$(( now - $(stat -c %Y "$d" 2>/dev/null || echo "$now") ))
    if [ "$da" -lt "$MIN_AGE" ]; then D_CLASS[$d]=YOUNG; else D_CLASS[$d]=STALE; fi
  else
    PID_DIRS[$p]="${PID_DIRS[$p]:-} $d"
    # A live session is IDLE only if parked (WAIT/ERR) past the threshold.
    # NOLOG is NOT idle: a session dir exists before its log does, so a
    # fresh session is indistinguishable from a logless one -- and it is
    # LIVE, which is the fact that matters.  Treating it as idle would
    # reap agents in their first seconds.
    if { [ "$st" = WAIT ] || [ "$st" = ERR ]; } && [ "$ag" -ge "$IDLE_AGE" ]; then
      D_CLASS[$d]=IDLE
    else
      D_CLASS[$d]=LIVE
      PID_HAS_BUSY[$p]=1
    fi
  fi
done

# PROTECT: never touch a named session (the driver's own), and never treat
# its pid as killable.
for d in "${dirs[@]}"; do
  id=${d##*/}
  case "$PROTECT" in *" $id "*)
      D_CLASS[$d]=SELF
      p=${D_PID[$d]}; [ -n "$p" ] && PID_HAS_BUSY[$p]=1
  ;; esac
done

# ---- report / act
removed=0; killed=0; kept=0; vetoed=0
out=""
for d in "${dirs[@]}"; do
  id=${d##*/}; c=${D_CLASS[$d]}; p=${D_PID[$d]}
  case "$c" in
    SELF|LIVE|YOUNG) kept=$((kept+1)); continue;;
    IDLE)
      if [ "$KILL_IDLE" != 1 ]; then kept=$((kept+1)); continue; fi
      if [ -n "${PID_HAS_BUSY[$p]:-}" ]; then
        # HAZARD 1 in action: this pid also drives a live session.
        vetoed=$((vetoed+1))
        out="$out
VETO $id pid=$p (pid also holds a live session)"
        continue
      fi
      ;;
  esac
  # STALE, or IDLE cleared for reaping
  if [ "$c" = IDLE ]; then
    if [ "$MODE" = apply ]; then
      "$KILLCMD" -TERM "$p" 2>/dev/null
      # give it a moment, then verify -- grade on the re-read, not on rc
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        grep -aqs copilot "$PROCFS/$p/cmdline" || break
        sleep 1
      done
      grep -aqs copilot "$PROCFS/$p/cmdline" && "$KILLCMD" -KILL "$p" 2>/dev/null
      sleep 1
    fi
    killed=$((killed+1))
    out="$out
KILL $id pid=$p ${D_STATE[$d]}/${D_AGE[$d]}s"
  fi
  sz=$(du -sk "$d" 2>/dev/null | cut -f1); sz=${sz:-0}
  if [ "$MODE" = apply ]; then
    rm -rf -- "$d" || continue
  fi
  removed=$((removed+1))
  out="$out
RM $id ${D_STATE[$d]}/${D_AGE[$d]}s ${sz}k"
done

# ---- HAZARD 2: prune the parallel registry.
# open-sessions-state.json is a SECOND record of sessions, keyed by the same
# uuid.  Removing dirs without pruning it leaves entries that outlive their
# directory forever (MEASURED on c01: d92d5830 sits there `working:true`
# with no dir lock at all).  Prune only keys whose dir is now GONE, so the
# json can never disagree with the filesystem.
pruned=0
for j in "$HOMEROOT"/root/.copilot/open-sessions-state.json "$HOMEROOT"/home/*/.copilot/open-sessions-state.json; do
  [ -f "$j" ] || continue
  base=${j%/open-sessions-state.json}/session-state
  keys=$(jq -r 'keys[]' "$j" 2>/dev/null) || continue
  gone=""
  for k in $keys; do [ -d "$base/$k" ] || gone="$gone $k"; done
  [ -n "$gone" ] || continue
  n=$(printf '%s\n' $gone | wc -l)
  if [ "$MODE" = apply ]; then
    f=$(printf '%s\n' $gone | jq -R . | jq -s .)
    tmp=$(mktemp)
    if jq --argjson g "$f" 'delpaths([$g[]|[.]])' "$j" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      cat "$tmp" > "$j"
    fi
    rm -f "$tmp"
  fi
  pruned=$((pruned+n))
done

printf 'RM=%s KILL=%s VETO=%s KEPT=%s PRUNED=%s MODE=%s\n' \
  "$removed" "$killed" "$vetoed" "$kept" "$pruned" "$MODE"
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
