#!/usr/bin/env bash
# prg-leg.sh — one graded LEG's session+traffic trace, as a glanceable list.
# NO LLM.  Pure jq + shell.  Opens the TWO correlated files for a single ssg
# leg and prints what the model DID (tool chain) and what it SAID (answer),
# so a debug read takes seconds instead of scrolling 70+ raw events.
#
# The two files, and how they join:
#   traffic  <run>/<TS>_<id>.response.json   (ssg_sim envelope)
#            .ssg_sim.childSessionId  -> JOIN KEY
#            .ssg_sim.leg, .success, .durationMs, .ssg_sim.digest.eventTypes
#   session  <run>/.copilot/session-state/<childSessionId>/events.jsonl
#            tool.execution_start/complete (the chain) + assistant.message
#            .data.content (the final answer).  reasoningOpaque is SEALED
#            (provider-encrypted) — this tool never touches it.
#
# Usage:
#   prg-leg.sh <run_dir> <leg_id>        # id = the 8-hex in the filenames
#   prg-leg.sh <path/to/*.response.json> # or point straight at the response
#
# Exit: 0 ok · 2 bad args/deps · 4 file absent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN="$HERE/jq/leg-chain.jq"

command -v jq >/dev/null || { echo "prg-leg: jq required" >&2; exit 2; }
[ -f "$CHAIN" ] || { echo "prg-leg: missing $CHAIN" >&2; exit 2; }

# ---- resolve the response.json + run dir from the two calling forms ----
RESP=""; RUN=""
case "${1:-}" in
  "") echo "usage: prg-leg.sh <run_dir> <leg_id> | <response.json>" >&2; exit 2;;
  *.response.json)
      RESP="$1"; RUN="$(cd "$(dirname "$RESP")" && pwd)";;
  *)
      RUN="${1%/}"; ID="${2:-}"
      [ -n "$ID" ] || { echo "prg-leg: need <leg_id> after <run_dir>" >&2; exit 2; }
      RESP="$(ls "$RUN"/*_"$ID".response.json 2>/dev/null | head -1 || true)"
      [ -n "$RESP" ] || { echo "prg-leg: no *_$ID.response.json under $RUN" >&2; exit 4; };;
esac
[ -f "$RESP" ] || { echo "prg-leg: response absent: $RESP" >&2; exit 4; }

# ---- W1: correlate -> child session events.jsonl ----
CHILD="$(jq -r '.ssg_sim.childSessionId // empty' "$RESP")"
[ -n "$CHILD" ] || { echo "prg-leg: no ssg_sim.childSessionId in $RESP" >&2; exit 4; }
EVENTS="$RUN/.copilot/session-state/$CHILD/events.jsonl"

# ---- W3: response summary line (traffic side) ----
# leg verdict + a compact "N tools, M msgs" fold of digest.eventTypes.
jq -r '
  .ssg_sim as $s
  | ($s.digest.eventTypes // {}) as $e
  | "leg=\($s.leg // "?")  ok=\(.success)  http=\(.httpStatus // "?")"
    + "  dur=\(.durationMs // $s.usage.sessionDurationMs // "?")ms"
    + "  tools=\($e["tool.execution_start"] // 0)"
    + "  msgs=\($e["assistant.message"] // 0)"
    + "  child=\($s.childSessionId[0:8])"
' "$RESP"

# ---- W2: the tool chain, rendered ----
if [ -f "$EVENTS" ]; then
  jq -s -f "$CHAIN" "$EVENTS" \
  | jq -r '"  \(.n). \(.tool)  \(if .ok==true then "OK" elif .ok==false then "ERR" else "?" end)  \(.digest)"'
else
  echo "  (session events absent: $EVENTS — jail/home reaped?)" >&2
fi

# ---- W3 cont: what it finally SAID (session side, else traffic .content) ----
SAID=""
if [ -f "$EVENTS" ]; then
  # the SUBSTANTIVE answer = the longest assistant.message content (a trailing
  # message may be just a ``` fence; the real answer/question is the longest).
  SAID="$(jq -rs '[ .[] | select(.type=="assistant.message") | .data.content // empty ]
                  | map(select(length>0)) | (max_by(length) // "")' "$EVENTS")"
fi
[ -n "$SAID" ] || SAID="$(jq -r '(.content // []) | map(.text? // empty) | join(" ")' "$RESP" 2>/dev/null)"
# first MEANINGFUL line (skip blank + lone ``` fence), trimmed to one glance
SAID="$(printf '%s\n' "$SAID" | grep -vE '^[[:space:]]*(```[a-z]*)?[[:space:]]*$' | head -1 | cut -c1-160)"
[ -n "$SAID" ] && echo "said: $SAID"
