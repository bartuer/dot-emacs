#!/usr/bin/env bash
# prg-llm.sh — ONE fast completion via the LOCAL L-server proxy.  THE LOOP HEAD.
#
# This is the ONLY prg-* script that calls a model.  Every other prg-* tool is
# model-free by contract; this script is the loop ORCHESTRATOR's mouth — the
# model that picks keywords/spans (R1) and reads the trajectory to decide the
# next dives (R2).  It never boots an agent: it hits the OpenAI-compatible
# proxy at http://host.docker.internal:11434 which answers in ~1.5s with zero
# boot and zero credits, concurrency-safe (this is what makes fan-out possible;
# a full `copilot -p` boot is 34.7s / 22.4 credits and CANNOT be fanned out).
#
# Contract (so callers can depend on it):
#   - Probes /v1/models once.  If the proxy is UNREACHABLE, exit 3 — the caller
#     is expected to fall back to its --no-model tool-only path.  Exit 3 is the
#     documented "no model, degrade gracefully" signal across prg-*.
#   - On success prints ONLY the assistant message text to stdout (no JSON),
#     so it composes in a pipe / $() with no jq on the caller side.
#   - Default model = claude-sonnet-4-5 (measured ~1.5s, correct on seeds).
#
# Usage:
#   prg-llm.sh <prompt>            [--model M] [--system S] [--max-tokens N]
#   echo <prompt> | prg-llm.sh -   [--model M] ...          (prompt on stdin)
#   prg-llm.sh <prompt> --tool-schema FILE [--tool-name N]  # FORCE conforming
#       output: attach one tool whose input_schema IS FILE, force it via
#       tool_choice, and print the tool call's arguments JSON (the enforceable
#       schema path; response_format is NOT honored by this proxy — plan 43).
#   prg-llm.sh --probe                              # exit 0 reachable / 3 not
#
# Env:
#   PRG_LLM_URL    override base URL (default http://host.docker.internal:11434)
#   PRG_LLM_MODEL  override default model
#
# Exit codes: 0 ok · 2 usage/dep · 3 proxy unreachable (fall back --no-model)
set -euo pipefail

command -v curl >/dev/null || { echo "prg-llm: curl required" >&2; exit 2; }
command -v jq   >/dev/null || { echo "prg-llm: jq required"   >&2; exit 2; }

BASE="${PRG_LLM_URL:-http://host.docker.internal:11434}"
MODEL="${PRG_LLM_MODEL:-claude-sonnet-4-5}"
SYSTEM=""
MAXTOK=512
PROMPT=""
PROBE_ONLY=0
TOOL_SCHEMA=""          # --tool-schema FILE : force a tool whose input_schema IS this JSON Schema
TOOL_NAME="parse_utterance"

# ---- arg parse -------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --model)      MODEL="$2"; shift 2 ;;
    --system)     SYSTEM="$2"; shift 2 ;;
    --max-tokens) MAXTOK="$2"; shift 2 ;;
    --tool-schema) TOOL_SCHEMA="$2"; shift 2 ;;
    --tool-name)  TOOL_NAME="$2"; shift 2 ;;
    --probe)      PROBE_ONLY=1; shift ;;
    -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
    -)            PROMPT="$(cat)"; shift ;;
    --)           shift; PROMPT="${PROMPT:-$*}"; break ;;
    -*)           echo "prg-llm: unknown flag $1" >&2; exit 2 ;;
    *)            PROMPT="${PROMPT:+$PROMPT }$1"; shift ;;
  esac
done

# ---- probe the proxy ONCE (this is the exit-3 gate) ------------------------
probe() {
  local code
  code="$(timeout 6 curl -s -o /dev/null -w '%{http_code}' "$BASE/v1/models" 2>/dev/null || echo 000)"
  [ "$code" = "200" ]
}

if [ "$PROBE_ONLY" = 1 ]; then
  if probe; then echo "reachable $BASE"; exit 0
  else echo "prg-llm: proxy unreachable at $BASE" >&2; exit 3; fi
fi

[ -n "$PROMPT" ] || { echo "prg-llm: empty prompt (usage: prg-llm.sh <prompt>)" >&2; exit 2; }

if ! probe; then
  echo "prg-llm: proxy unreachable at $BASE — caller should fall back to --no-model" >&2
  exit 3
fi

# ---- build request + one completion ---------------------------------------
# Default path: {model, max_tokens, messages}.  Forced-tool-schema path
# (--tool-schema): ALSO attach a single tool whose input_schema IS the given
# JSON Schema and force it via tool_choice, so the model must emit conforming
# arguments.  This is the enforceable path the L-server corpus supports
# (tools/tool_choice present; response_format never is — see plan 43 CKP-6).
if [ -n "$TOOL_SCHEMA" ]; then
  [ -f "$TOOL_SCHEMA" ] || { echo "prg-llm: --tool-schema file not found: $TOOL_SCHEMA" >&2; exit 2; }
  jq -e . "$TOOL_SCHEMA" >/dev/null 2>&1 || { echo "prg-llm: --tool-schema not valid JSON: $TOOL_SCHEMA" >&2; exit 2; }
  # OpenAI /v1/chat/completions tools shape (this proxy is OpenAI-compat on
  # this endpoint — it rejects the Anthropic {type:"tool",name} tool_choice
  # with 400 and requires {type:"function",function:{name}}).
  REQ="$(jq -n --arg m "$MODEL" --arg p "$PROMPT" --arg s "$SYSTEM" \
             --argjson mt "$MAXTOK" --arg tn "$TOOL_NAME" \
             --slurpfile sc "$TOOL_SCHEMA" '
    ( (if ($s | length) > 0 then [{role:"system", content:$s}] else [] end)
      + [{role:"user", content:$p}] ) as $msgs
    | {model:$m, max_tokens:$mt, messages:$msgs,
       tools:[{type:"function",
               function:{name:$tn,
                         description:"Return the parsed structure for the utterance.",
                         parameters:$sc[0]}}],
       tool_choice:{type:"function", function:{name:$tn}}}')"
else
  REQ="$(jq -n --arg m "$MODEL" --arg p "$PROMPT" --arg s "$SYSTEM" --argjson mt "$MAXTOK" '
    ( (if ($s | length) > 0 then [{role:"system", content:$s}] else [] end)
      + [{role:"user", content:$p}] ) as $msgs
    | {model:$m, max_tokens:$mt, messages:$msgs}')"
fi

RESP="$(timeout 60 curl -s -H 'content-type: application/json' \
  -d "$REQ" "$BASE/v1/chat/completions" 2>/dev/null || echo '')"

[ -n "$RESP" ] || { echo "prg-llm: empty response from proxy" >&2; exit 3; }

# ---- extract the completion -----------------------------------------------
# In forced-tool mode prefer the TOOL CALL's arguments (constrained output),
# tolerating both response shapes the proxy may emit:
#   OpenAI:    .choices[0].message.tool_calls[0].function.arguments  (JSON string)
#   Anthropic: .content[] | select(.type=="tool_use") | .input       (JSON object)
# Fall back to plain message content only if NO tool call came back (reported
# on stderr so a format-miss can't masquerade as a slot miss).
if [ -n "$TOOL_SCHEMA" ]; then
  CONTENT="$(printf '%s' "$RESP" | jq -rc '
      ( .choices[0].message.tool_calls[0].function.arguments? )
      // ( [.content[]? | select(.type=="tool_use") | .input] | (.[0] // empty) )
      // empty' 2>/dev/null || true)"
  if [ -n "$CONTENT" ]; then printf '%s\n' "$CONTENT"; exit 0; fi
  echo "prg-llm: forced tool ($TOOL_NAME) returned NO tool call — falling back to message content" >&2
fi

CONTENT="$(printf '%s' "$RESP" | jq -r '.choices[0].message.content // (.content[]? | select(.type=="text") | .text) // empty' 2>/dev/null || true)"
if [ -z "$CONTENT" ]; then
  # surface the proxy error but still signal a model-unavailable outcome
  ERR="$(printf '%s' "$RESP" | jq -r '.error.message // .error // "(no content)"' 2>/dev/null || echo '(unparseable)')"
  echo "prg-llm: no completion content: $ERR" >&2
  exit 3
fi

printf '%s\n' "$CONTENT"
