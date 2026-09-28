#!/usr/bin/env bash
# prg-log.sh — L-server LLM request/response log miner.  NO LLM.
#
# Corpus (set via --corpus or PRG_LOG_CORPUS; no default): paired capture files
#   <TS>_<id>.json           request  {max_tokens, messages, system, tools}
#   <TS>_<id>.response.json  response {model, requestId, promptFile,
#                                      durationMs, httpStatus, success, ts, output}
# `id` = 8-hex requestId, embedded in the filename AND in .requestId.
#
# Agent-first: default output is stable JSONL to stdout; `--pretty` renders
# count tables column-aligned.  Uses the versioned jq filters in jq/.
#
# Subverbs:
#   count-by-model            -> {model, n}  aggregated across responses
#   pair <id>                 -> request object, then response object (2 lines)
#   tool-calls                -> {tool_name, n} across request .tools
#   grep <jqfilter>           -> run an arbitrary jq -c filter over responses
#   latest [N]                -> newest N *.response.json paths by NAME (the
#                                filename's leading ISO ts is a time sort; no
#                                stat).  Feed into pair/grep for recent calls.
#
# Exit: 0 ok · 2 bad args/deps · 4 corpus absent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="$HERE/jq"
# Log corpus: set via --corpus or PRG_LOG_CORPUS; no hardcoded default, so an
# unset corpus degrades to the documented "absent" exit (4), never a wrong path.
CORPUS="${PRG_LOG_CORPUS:-}"
PRETTY=0

command -v jq >/dev/null       || { echo "prg-log: jq required" >&2; exit 2; }
command -v parallel >/dev/null || { echo "prg-log: GNU parallel required" >&2; exit 2; }

# pull --pretty / --corpus out of the arg list, keep the rest positional.
args=(); while [ $# -gt 0 ]; do case "$1" in
  --pretty) PRETTY=1; shift;;
  --corpus) CORPUS="$2"; shift 2;;
  *) args+=("$1"); shift;;
esac; done
set -- "${args[@]:-}"
SUB="${1:-}"; shift || true

[ -d "$CORPUS" ] || { echo "prg-log: corpus '$CORPUS' absent" >&2; exit 4; }

# NPROC for parallel fan-out.
NP="$(nproc 2>/dev/null || echo 4)"

# list files (NUL-safe) of a given suffix.
list_resp() { find "$CORPUS" -maxdepth 1 -name '*.response.json' -print0; }
list_req()  { find "$CORPUS" -maxdepth 1 -name '*.json' ! -name '*.response.json' -print0; }

case "$SUB" in
  count-by-model)
    # parallel jq over response shards -> {model}; aggregate to {model,n}.
    # -N200: hand each jq fork ~200 files (jq loops its file args natively), so
    # 2.7k files = ~14 forks not 2.7k.  Per-file fan-out spends ~10s in
    # fork/exec for ~0.1s of real jq work (measured 112x); batching restores it.
    list_resp | parallel -0 -j "$NP" -N200 --no-notice \
        jq -c -f "$JQ/count-by-model.jq" {} 2>/dev/null \
      | jq -s -c 'group_by(.model)|map({model:.[0].model, n:length})|sort_by(-.n)[]' \
      > /tmp/prg-log.$$ || true
    if [ "$PRETTY" -eq 1 ]; then
      { printf 'MODEL\tN\n'; jq -r '[.model,(.n|tostring)]|@tsv' /tmp/prg-log.$$; } \
        | column -t -s $'\t'
    else
      cat /tmp/prg-log.$$
    fi
    rm -f /tmp/prg-log.$$
    ;;

  pair)
    id="${1:?usage: prg-log.sh pair <id>}"
    req=$(find "$CORPUS" -maxdepth 1 -name "*_${id}.json" ! -name '*.response.json' | head -1)
    resp=$(find "$CORPUS" -maxdepth 1 -name "*_${id}.response.json" | head -1)
    [ -z "$req" ] && [ -z "$resp" ] && { echo "prg-log: no files for id '$id'" >&2; exit 4; }
    if [ "$PRETTY" -eq 1 ]; then
      [ -n "$req" ]  && { echo "== request $id =="; jq '{max_tokens, model, system:(.system|type), n_messages:(.messages|length), tools:((.tools//[])|map(.function.name))}' "$req"; }
      [ -n "$resp" ] && { echo "== response $id =="; jq '{model, httpStatus, success, durationMs, ts}' "$resp"; }
    else
      [ -n "$req" ]  && jq -c '{id:"'"$id"'", kind:"request",  model, n_messages:(.messages|length), n_tool_calls:((.tools//[])|length)}' "$req"
      [ -n "$resp" ] && jq -c '{id:"'"$id"'", kind:"response", model, httpStatus, success, durationMs, ts}' "$resp"
    fi
    ;;

  tool-calls)
    list_req | parallel -0 -j "$NP" -N200 --no-notice \
        jq -c -f "$JQ/tool-calls.jq" {} 2>/dev/null \
      | jq -s -c 'group_by(.tool_name)|map({tool_name:.[0].tool_name, n:length})|sort_by(-.n)[]' \
      > /tmp/prg-log.$$ || true
    if [ "$PRETTY" -eq 1 ]; then
      { printf 'TOOL\tN\n'; jq -r '[.tool_name,(.n|tostring)]|@tsv' /tmp/prg-log.$$; } \
        | column -t -s $'\t'
    else
      cat /tmp/prg-log.$$
    fi
    rm -f /tmp/prg-log.$$
    ;;

  latest)
    # TAIL-FIRST at the filesystem level: L-server names are
    # <ISO-with-dashes>Z_<8hex>.response.json, so the leading token is a
    # lex-sortable timestamp -> a NAME sort is a time sort.  Return the newest
    # N response paths with ZERO stat() (kiss: the name already carries the
    # time; do NOT `find -printf '%T@'|sort` over thousands of files).
    N="${1:-20}"
    case "$N" in (*[!0-9]*) echo "prg-log: latest N must be an integer" >&2; exit 2;; esac
    # `head` closes the pipe early, so `ls|sort` get SIGPIPE (141); with
    # pipefail that would fail the script.  Sort into an array first, then
    # slice — no early-closed pipe, deterministic exit 0.
    mapfile -t _all < <(ls -1 "$CORPUS"/*.response.json 2>/dev/null | sort -r)
    printf '%s\n' "${_all[@]:0:$N}"
    ;;

  grep)
    filt="${1:?usage: prg-log.sh grep '<jq filter>'}"
    # parallel re-parses its command through a shell, which strips the quotes
    # around $filt and breaks on jq syntax like `(`.  Write the filter to a
    # temp .jq and use `jq -f` so no shell re-quoting can corrupt it.
    tmpf="$(mktemp /tmp/prg-log-grep.XXXXXX.jq)"
    printf '%s\n' "$filt" > "$tmpf"
    trap 'rm -f "$tmpf"' EXIT
    list_resp | parallel -0 -j "$NP" -N200 --no-notice jq -c -f "$tmpf" {} 2>/dev/null
    ;;

  ""|-h|--help)
    sed -n '2,20p' "$HERE/prg-log.sh" | sed 's/^# \{0,1\}//'
    echo
    echo "schema: count-by-model -> {model,n} · tool-calls -> {tool_name,n}"
    echo "        pair <id>       -> {id,kind,model,...}  (request then response)"
    [ -z "$SUB" ] && exit 2 || exit 0
    ;;

  *) echo "prg-log: unknown subverb '$SUB' (count-by-model|pair|tool-calls|grep|latest)" >&2; exit 2;;
esac
