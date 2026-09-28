#!/usr/bin/env bash
# prg-trace.sh — two-round trajectory deep-research over the telemetry corpus.
# NO LLM.  The model only sits at the loop head (CKP-5b) choosing the span and
# keywords; every discovery here is tool-only (jq + rg + parallel + git).
#
# Corpus (set via --corpus or PRG_TRACE_CORPUS; default /agent/logs), a dir of
# JSONL lenses with ISO-8601 Z timestamps so span filtering is a lexicographic
# string compare (no date parsing):
#   trace.otel.jsonl        {timestamp, type, trace:{traceId,name,...}}
#   agent.log.jsonl         {timestamp, component, event, file?}
#   agent_lifecycle.jsonl   {ts, eventType, fromState, toState, convId, ...}
# Plus (optional, when reachable): git log in --repo, session-state checkpoints.
#
# Verbs:
#   harvest --span FROM..TO [--repo DIR] [--pretty]
#       Round 1: walk every lens within [FROM,TO], emit a flat keyword
#       collection with provenance.  Stable JSONL rows:
#         {keyword, kind(symbol|path|span|event|tool|commit), source, ts, ref}
#       --pretty ranks by cross-lens frequency and groups by kind.
#   connect --span FROM..TO [--repo DIR]
#       Round 2: stitch the harvest into ONE object validated against
#       bench/trajectory.schema.json; deterministic edges only (shared
#       traceId / shared file / shared keyword / adjacent ts).  Prints the
#       object iff it validates, else exits 5 with a stderr note.
#
# Exit: 0 ok · 2 bad args/deps · 4 corpus absent · 5 schema validation failed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="$HERE/jq"
SCHEMA="$HERE/bench/trajectory.schema.json"
CORPUS="${PRG_TRACE_CORPUS:-/agent/logs}"
PRETTY=0
REPO=""
SPAN=""
STRATEGY="auto"   # auto|tail|forward — how to scan large JSONL lenses
TAIL_WIN_MB="${PRG_TRACE_TAIL_WIN_MB:-2}"   # initial byte-window (MiB) for tail-first
TAIL_WIN_MAX_MB="${PRG_TRACE_TAIL_WIN_MAX_MB:-32}"  # widen up to this, else fall back

command -v jq >/dev/null       || { echo "prg-trace: jq required" >&2; exit 2; }
command -v parallel >/dev/null || { echo "prg-trace: GNU parallel required" >&2; exit 2; }

# shared time normalizer: --span sides may be human/relative ("1 hour ago",
# "noon", "HEAD~2", ISO).  Sourcing gives prg_when / prg_span.
# shellcheck source=prg-when.sh
. "$HERE/prg-when.sh"

args=(); while [ $# -gt 0 ]; do case "$1" in
  --pretty) PRETTY=1; shift;;
  --corpus) CORPUS="$2"; shift 2;;
  --repo)   REPO="$2";   shift 2;;
  --span)   SPAN="$2";   shift 2;;
  --strategy) STRATEGY="$2"; shift 2;;
  *) args+=("$1"); shift;;
esac; done
set -- "${args[@]:-}"
SUB="${1:-}"; shift || true

[ -d "$CORPUS" ] || { echo "prg-trace: corpus '$CORPUS' absent" >&2; exit 4; }

# split FROM..TO and NORMALIZE each side through the shared time helper, so a
# span may be human/relative ("1 hour ago..now", "this morning..noon",
# "HEAD~2..HEAD") not just raw ISO.  git-relative sides resolve against --repo.
parse_span() {
  [ -n "$SPAN" ] || { echo "prg-trace: --span FROM..TO required" >&2; exit 2; }
  case "$SPAN" in *..*) : ;; *)
    echo "prg-trace: bad --span '$SPAN' (want FROM..TO)" >&2; exit 2 ;; esac
  WHEN_REPO="$REPO"           # let prg_when resolve git refs against --repo
  local sp
  sp="$(prg_span "$SPAN")" || { echo "prg-trace: bad --span '$SPAN'" >&2; exit 2; }
  FROM="${sp%%$'\t'*}"; TO="${sp##*$'\t'}"
  [ -n "$FROM" ] && [ -n "$TO" ] && [ "$FROM" != "$TO" ] || \
    { echo "prg-trace: --span resolves to an empty/zero range ('$FROM'..'$TO')" >&2; exit 2; }
}

NP="$(nproc 2>/dev/null || echo 4)"
TSKEY_lifecycle=".ts"   # lifecycle uses .ts; the rest use .timestamp
NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

# decide_strategy: pick tail-first vs parallel forward for THIS span.
# tail-first wins when the span reaches to "now-ish" (recent / open-ended
# dive) — telemetry is append-only so the hits are near the file end.  A span
# that ends well before now needs the exhaustive forward scan.  --strategy
# tail|forward forces the choice; auto (default) compares TO against now.
decide_strategy() {
  [ "$STRATEGY" = "tail" ] && { echo tail; return; }
  [ "$STRATEGY" = "forward" ] && { echo forward; return; }
  # auto: TO within ~1 day of now (lexicographic date-prefix compare) -> tail.
  local to_day="${TO:0:10}" now_day; now_day="$(date -u -d 'yesterday' +%Y-%m-%d 2>/dev/null || echo 0000-00-00)"
  if [ "$to_day" \> "$now_day" ] || [ "$to_day" = "$now_day" ]; then echo tail; else echo forward; fi
}

# scan_lens <file> <lensfile> <tskey>
#   Runs the lens over records in [FROM,TO], honoring BOTH wisdoms:
#   - TAIL-FIRST (byte-window, frontier-decided): `tail -c <bytes>` seeks from
#     EOF so it is O(window), never O(file).  `tac` reverses the window; the
#     lens' first expr drops anything outside the span.  If the OLDEST line the
#     window yields is still newer than FROM the window undershot -> WIDEN
#     (double MiB) up to TAIL_WIN_MAX_MB, then fall back to the forward scan.
#     (`tac|head -n K` is rejected: `tac` reads the whole file -> O(file).)
#   - PARALLEL FORWARD: `parallel --pipepart --block 8M` shards ONE big file
#     across nproc for exhaustive/historical spans.  O(file)/ncores.
# Either way the span-compare is the FIRST jq expr in the lens (cheapest reject).
scan_lens() {
  local f="$1" lens="$2" tskey="${3:-.timestamp}"
  [ -f "$f" ] || return 0
  local strat; strat="$(decide_strategy)"
  if [ "$strat" = "forward" ]; then
    # --pipepart -a <file> record-aligns ONE big file into per-core chunks.
    parallel -j "$NP" --pipepart -a "$f" --block 8M --no-notice \
      jq -c --arg FROM "$FROM" --arg TO "$TO" -f "$lens" 2>/dev/null || true
    return 0
  fi
  # tail-first byte-window with auto-widen.  A file smaller than the window is
  # read whole (tail -c just returns it), which is fine — small files are cheap.
  local fsize win reached=0
  fsize="$(wc -c <"$f" 2>/dev/null || echo 0)"
  win=$(( TAIL_WIN_MB * 1024 * 1024 ))
  while :; do
    # oldest line in this window (first line AFTER a partial-record boundary).
    # tail -c may split the first record; `tail -n +2` drops that fragment so
    # jq never sees a half line.  Empty window guard: if the file is tiny we
    # keep the whole thing.
    local oldest
    if [ "$win" -ge "$fsize" ]; then
      oldest="$(head -n1 "$f" 2>/dev/null | jq -r "${tskey} // empty" 2>/dev/null || true)"
      reached=1
    else
      oldest="$(tail -c "$win" "$f" 2>/dev/null | tail -n +2 | head -n1 \
                 | jq -r "${tskey} // empty" 2>/dev/null || true)"
    fi
    # window reaches FROM iff its oldest line is <= FROM (monotone ts), or we
    # already grabbed the whole file, or we hit the max window.
    if [ "$reached" -eq 1 ] || [ -z "$oldest" ] || [ ! "$oldest" \> "$FROM" ] \
       || [ "$win" -ge $(( TAIL_WIN_MAX_MB * 1024 * 1024 )) ]; then
      break
    fi
    win=$(( win * 2 ))
  done
  if [ "$win" -ge "$fsize" ]; then
    tail -n +1 "$f" 2>/dev/null | tac \
      | jq -c --arg FROM "$FROM" --arg TO "$TO" -f "$lens" 2>/dev/null || true
  elif [ -n "$oldest" ] && [ "$oldest" \> "$FROM" ] \
       && [ "$win" -ge $(( TAIL_WIN_MAX_MB * 1024 * 1024 )) ]; then
    # window maxed out but still didn't reach FROM -> exhaustive forward scan.
    parallel -j "$NP" --pipepart -a "$f" --block 8M --no-notice \
      jq -c --arg FROM "$FROM" --arg TO "$TO" -f "$lens" 2>/dev/null || true
  else
    tail -c "$win" "$f" 2>/dev/null | tail -n +2 | tac \
      | jq -c --arg FROM "$FROM" --arg TO "$TO" -f "$lens" 2>/dev/null || true
  fi
}

# ---- Round 1 lenses: each emits {keyword,kind,source,ts,ref} JSONL -----------
h_otel()      { scan_lens "$CORPUS/trace.otel.jsonl"      "$JQ/trace-otel.jq"; }
h_agentlog()  { scan_lens "$CORPUS/agent.log.jsonl"       "$JQ/trace-agentlog.jq"; }
h_lifecycle() { scan_lens "$CORPUS/agent_lifecycle.jsonl" "$JQ/trace-lifecycle.jq" ".ts"; }
h_git() {
  [ -n "$REPO" ] && [ -d "$REPO/.git" ] || return 0
  # commits in span -> {keyword:subject, kind:commit, source:git, ts, ref:sha}
  git -C "$REPO" log --since="$FROM" --until="$TO" \
      --date=format-local:'%Y-%m-%dT%H:%M:%S.000Z' \
      --pretty=format:'%H%x09%cd%x09%s' 2>/dev/null \
    | jq -R -c 'split("\t") | select(length==3)
        | {keyword:.[2], kind:"commit", source:"git", ts:.[1], ref:.[0]}' \
    2>/dev/null || true
}

harvest_raw() {   # concatenated JSONL from every reachable lens
  h_otel; h_agentlog; h_lifecycle; h_git
}

do_harvest() {
  parse_span
  if [ "$PRETTY" -eq 1 ]; then
    # rank by cross-lens frequency: a keyword seen in >1 distinct source
    # outranks a one-off; group by kind for the human view.  De-noise the
    # same way prg-seed does: down-weight node_modules/.d.ts paths.
    harvest_raw | jq -s -c '
      map(. + {w: (if (.ref|tostring|test("node_modules|\\.d\\.ts")) then 0.2 else 1 end)})
      | group_by(.keyword)
      | map({keyword: .[0].keyword, kind: .[0].kind,
             sources: (map(.source)|unique),
             lenses: (map(.source)|unique|length),
             count: length,
             score: ((map(.w)|add) * (map(.source)|unique|length))})
      | sort_by(-.score, -.count)[]' \
    | jq -r '[.keyword,.kind,(.lenses|tostring),(.count|tostring),(.sources|join(","))]|@tsv' \
    | { printf 'KEYWORD\tKIND\tLENSES\tCOUNT\tSOURCES\n'; cat; } \
    | column -t -s $'\t'
  else
    harvest_raw
  fi
}

# ---- Round 2: connect harvest into one schema-validated object ---------------
do_connect() {
  parse_span
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  harvest_raw > "$tmp"

  # Build the connected object deterministically from the harvested rows.
  # turns      = one per distinct (ts,source) ordered by ts (adjacency edge)
  # keywords   = ranked distinct keywords with refs
  # edges      = shared-ref (traceId/file) links between turns + adjacency
  local obj
  obj="$(jq -s -c --arg FROM "$FROM" --arg TO "$TO" '
    . as $rows
    | ($rows | sort_by(.ts)) as $sorted
    | ([ $sorted[] | {ts, role:.source, keyword, ref, kind} ]) as $ev
    | # turns: collapse events sharing the same ts+source into one turn.
      # Each turn also carries `slots` — the SAME SOURCE/TERM/TASK
      # decomposition the parse recipe applies to one utterance, here
      # derived DETERMINISTICALLY (no model) by partitioning each turn
      # from its own {keyword,kind} events: SOURCE=the lens/role, TERM=seeds
      # (kind symbol|path|span|commit), TASK=the operation (kind
      # event|tool|model).  See SKILL.md "## Trajectory = the workflow spine".
      ([ $ev | group_by(.ts + "|" + .role)[]
         | {turn: 0, ts: .[0].ts, role: .[0].role,
            keywords: (map(.keyword)|unique),
            refs: (map(.ref)|unique),
            slots: {
              source: .[0].role,
              term:   (map(select(.kind=="symbol" or .kind=="path"
                                   or .kind=="span" or .kind=="commit")
                          | .keyword) | unique),
              task:   (map(select(.kind=="event" or .kind=="tool"
                                   or .kind=="model")
                          | .keyword) | unique)
            }} ]
       | to_entries | map(.value + {turn: .key})) as $turns
    | # keyword table with cross-lens count
      ([ $rows | group_by(.keyword)[]
         | {keyword: .[0].keyword, kind: .[0].kind,
            count: length, refs: (map(.ref)|unique)} ]
       | sort_by(-.count)) as $kw
    | # edges: adjacency (turn N -> N+1) + shared-ref links
      ( [ range(0; ($turns|length)-1) as $i
          | {from_turn: $i, to_turn: ($i+1), via: "ts"} ] ) as $adj
    | ( [ $turns[] as $a | $turns[] as $b
          | select($a.turn < $b.turn)
          | ($a.refs - ($a.refs - $b.refs)) as $shared
          | select(($shared|length) > 0)
          | {from_turn: $a.turn, to_turn: $b.turn, via: $shared[0]} ] ) as $reflinks
    | {session: "harvest", span: {from: $FROM, to: $TO},
       turns: $turns, edges: ($adj + $reflinks), keywords: $kw}
  ' "$tmp")"

  # Validate: prefer python jsonschema if present, else a jq required-field
  # check.  A malformed object is NEVER emitted to the consumer.
  if command -v python3 >/dev/null && python3 -c 'import jsonschema' 2>/dev/null; then
    if printf '%s' "$obj" | python3 -c '
import sys, json, jsonschema
obj = json.load(sys.stdin)
schema = json.load(open("'"$SCHEMA"'"))
jsonschema.validate(obj, schema)
' 2>/tmp/prg-trace.verr; then
      printf '%s\n' "$obj"
    else
      echo "prg-trace: connect object failed schema validation:" >&2
      cat /tmp/prg-trace.verr >&2
      exit 5
    fi
  else
    # jq fallback: assert required top-level keys + turns/edges/keywords arrays.
    if printf '%s' "$obj" | jq -e '
        (.session|type=="string") and (.span.from|type=="string")
        and (.span.to|type=="string") and (.turns|type=="array")
        and (.edges|type=="array") and (.keywords|type=="array")
        and (all(.turns[]; (.turn|type=="number") and (.ts|type=="string")))
        and (all(.edges[]; (.from_turn|type=="number") and (.to_turn|type=="number")))
      ' >/dev/null 2>&1; then
      printf '%s\n' "$obj"
    else
      echo "prg-trace: connect object failed jq required-field check" >&2
      exit 5
    fi
  fi
}

case "$SUB" in
  harvest) do_harvest;;
  connect) do_connect;;
  ""|-h|--help)
    sed -n '2,33p' "$0"; exit 0;;
  *) echo "prg-trace: unknown verb '$SUB' (harvest|connect)" >&2; exit 2;;
esac
