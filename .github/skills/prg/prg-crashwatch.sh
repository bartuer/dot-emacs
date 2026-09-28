#!/usr/bin/env bash
# prg-crashwatch.sh — api-server crash-class watcher over officeagent.log.  NO LLM.
#
# Why: an uncaughtException thrown out of a ws 'close' handler kills the
# api-server MID-EVAL.  The MCP/relay side often still returns a plausible
# answer, so a run can look GREEN while the server died underneath it.  This
# watcher makes that failure mode visible instead of silent.
#
# Corpus (--log or PRG_CRASH_LOG; default /agent/logs/officeagent.log).
#
# Agent-first: default output is stable JSONL to stdout; --pretty renders a
# count table.  Anchored patterns only (corpus-anchor rule: a fuzzy token
# inflates a log statistic).
#
# Subverbs:
#   scan            -> {ts, klass, message, n} one row per crash occurrence
#   count           -> {klass, n} aggregated
#   watch [SECS]    -> poll every SECS (default 10), emit new rows as they land
#   gate            -> exit 1 if ANY crash present (CI / eval preflight+postflight)
#
# Exit: 0 ok (or gate-clean) - 1 gate found crashes - 2 bad args/deps - 4 log absent.
set -euo pipefail

LOG="${PRG_CRASH_LOG:-/agent/logs/officeagent.log}"
PRETTY=0
SINCE="${PRG_CRASH_SINCE:-}"
args=(); while [ $# -gt 0 ]; do case "$1" in
  --pretty) PRETTY=1; shift;;
  --log) LOG="$2"; shift 2;;
  # --since ISO_TS: only count crashes STRICTLY AFTER this stamp. A log is
  # append-only across a fix, so historical crashes would otherwise pin the
  # gate RED forever. Pass the deploy/restart time to gate a post-fix run.
  --since) SINCE="$2"; shift 2;;
  *) args+=("$1"); shift;;
esac; done
set -- "${args[@]:-}"
SUB="${1:-scan}"; shift || true

command -v rg >/dev/null || { echo "prg-crashwatch: ripgrep required" >&2; exit 2; }
[ -f "$LOG" ] || { echo "prg-crashwatch: log '$LOG' absent" >&2; exit 4; }

# Anchored crash signatures. Keep this list SHORT and evidence-driven: every
# entry must have been observed in a real corpus (see fix.archive/apiserver-crash-watch.md).
PAT='Uncaught Exception|unhandledRejection|is not a function|Cannot read propert'

# Emit {ts, klass, message} JSONL — ONE row per crash EVENT, not per matching
# line. A node crash spans many lines (the stack), so a naive line-grep
# triple-counts it (observed 42 rows for 14 real crashes). We therefore anchor
# on the crash-START line (which carries the [ISO ts]) and then look ahead a
# bounded window for the `message:` line that names the defect.
emit() {
  awk '
    # crash start: a timestamped line announcing the failure.
    /Uncaught Exception|unhandledRejection/ {
      if (pending) flush();
      ts=""; if (match($0, /^\[[^]]*\]/)) ts=substr($0, RSTART+1, RLENGTH-2);
      klass = /unhandledRejection/ ? "unhandledRejection" : "uncaughtException";
      msg=""; pending=1; look=0; next;
    }
    # bounded look-ahead for the defect text.
    pending && look<6 {
      look++;
      if (msg=="" && match($0, /message: /)) {
        m=substr($0, RSTART+RLENGTH);
        gsub(/^[\x27"]|[\x27",]+$/,"",m);
        msg=m;
        if (msg ~ /is not a function/) klass="notAFunction";
        else if (msg ~ /Cannot read propert/) klass="nullDeref";
      }
      if (look>=6) flush();
      next;
    }
    function flush() {
      gsub(/\\/,"\\\\",msg); gsub(/"/,"\\\"",msg);
      printf "{\"ts\":\"%s\",\"klass\":\"%s\",\"message\":\"%s\"}\n", ts, klass, msg;
      pending=0; msg="";
    }
    END { if (pending) flush(); }
  ' "$LOG" 2>/dev/null \
  | { [ -n "$SINCE" ] && jq -c --arg s "$SINCE" 'select(.ts > $s)' || cat; }
}

case "$SUB" in
  scan) emit ;;
  count)
    if [ "$PRETTY" -eq 1 ]; then
      emit | jq -r .klass | sort | uniq -c | sort -rn | awk 'BEGIN{printf "%6s  %s\n","N","KLASS"} {printf "%6s  %s\n",$1,$2}'
    else
      emit | jq -r .klass | sort | uniq -c | sort -rn | awk '{printf "{\"klass\":\"%s\",\"n\":%s}\n",$2,$1}'
    fi ;;
  gate)
    n="$(emit | wc -l)"
    if [ "$n" -gt 0 ]; then
      echo "CRASH_GATE=RED n=$n log=$LOG" >&2
      emit | tail -3 >&2
      exit 1
    fi
    echo "CRASH_GATE=GREEN n=0 log=$LOG" ;;
  watch)
    SECS="${1:-10}"
    echo "prg-crashwatch: watching $LOG every ${SECS}s (ctrl-c to stop)" >&2
    last="$(emit | wc -l)"
    echo "prg-crashwatch: baseline=$last existing crash rows" >&2
    while sleep "$SECS"; do
      cur="$(emit | wc -l)"
      if [ "$cur" -gt "$last" ]; then
        echo "🔴 $((cur-last)) NEW crash row(s):" >&2
        emit | tail -n "$((cur-last))"
        last="$cur"
      fi
    done ;;
  *) echo "prg-crashwatch: unknown subverb '$SUB' (scan|count|watch|gate)" >&2; exit 2 ;;
esac
