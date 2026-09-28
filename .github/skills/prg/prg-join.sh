#!/usr/bin/env bash
# prg-join.sh -- multi-table join pipeline over a folder of .prg.jsonl sidecars.
#
# WHY A DRIVER AT ALL.  Measured on this session's own events.jsonl for the
# reference QBR analysis: 1270.8s wall clock, of which TOOL EXECUTION WAS 17.0s
# -- 1.3%.  The cost is model round-trips (33 of them), not tool speed.  So the
# job of this script is NOT to run jq faster; it is to make ONE invocation
# return everything the model needs for the next decision.  A subcommand that
# needs a follow-up call to be useful has failed its purpose.
#
# SUBCOMMANDS
#   schema     <folder>   per-sheet schema catalog, real header row detected
#   candidates <folder>   join candidates ranked by MEASURED value overlap
#   shapes     <folder>   per-column VALUE SHAPE histogram (join pre-check)
#   dag        <folder>   verify a PROPOSED edge set + prove acyclicity
#
# Both walk every *.prg.jsonl in the folder.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQD="$HERE/jq"

die() { printf '%s\n' "$*" >&2; exit 2; }

usage() {
  cat <<'EOF'
usage: prg-join.sh <subcommand> [args]

  schema     <folder> [--maxhdr N] [--minw N]
      Emit one JSON object per (file, sheet):
        {file, sheet, hdr_row, hdr_a1row?, axis, cols, rows, cells, hdr[], conf}
      axis is "row" (header row found), "col" (KEY-VALUE FORM -- schema runs
      down column 1, so NO header row exists and none is invented), or "none".

  candidates <folder> [--min-overlap N] [--top N]
      Emit ranked join candidates with measured overlap. See jq/join-candidates.jq.

  shapes     <folder> [--sample N] [--top N] [--col REGEX]
      Per-column histogram of NORMALISED value shapes (digits -> 9,
      letters -> A).  Two join candidates whose dominant shapes differ
      CANNOT match, and that is decided from ~400 sampled cells instead
      of a full scan or a trial query.  Emits {file,sheet,col,hdr,sql,
      n,sampled,shapes[],top}; `sql` is the identifier the DDL actually
      carries (mangle() in src/emitsql.c), NOT the header.
      --col filters by header regex, e.g. --col '(?i)shipment'.
      MEASURED, freight corpus: cass SHIPMENT_REF is "9" x400 while MG
      "Shipment Nbr" is "A-9" x400 -- the join between them is
      syntactically perfect and returns ZERO ROWS.

  model      <folder> [--min-shared N] [--min-contain F] [--budget-tok N | --top-k N]
      Emit the folder's join model as self-describing JSONL, sized for a
      model context window:
        {k:schema} x1  the contract, incl. counts
        {k:node}       one per (file,sheet)
        {k:edge}       the top-k surviving joins, BEST FIRST
        {k:trunc}      ONLY when k < N -- so its absence means "complete"
        {k:warn}  x1   every header that agrees BY NAME with ZERO shared
                       values.  Rejects are NOT exported as rows: measured,
                       35 996 reject rows (9.5 MB) carry 20 distinct names
                       (222 B).  The rows die, the finding lives.
      --budget-tok N sizes k from a context budget at ~41 tok/edge
      (8k -> ~192 edges, 32k -> ~771, 128k -> ~3084); --top-k N overrides.
      This is what `wpx` reads as "the most important semantic schema",
      and it is the context a model needs to write correct SQL first try.

  dag        <folder> [--edges FILE|-] [--out DIR] [--rule name|value|pk] [--escalate]
      VERIFY a proposed edge set; never invents one.  Proposal is TSV on stdin
      or --edges FILE:  src<TAB>dst<TAB>lcol<TAB>rcol
      Nodes are "file::sheet" (a bare sheet or file name is accepted when it
      resolves uniquely); columns are header text, cN, or a column number.
      Writes edges.tsv, rejects.tsv, dag.mmd into --out; prints a JSON verdict.
      An edge with ZERO measured shared values is REJECTED, never retained.
      --escalate: on a cycle, retry under the next-stricter rule
      (name -> value -> pk) and re-run the SAME DFS, rather than reaching for a
      cycle algorithm.  The rules form a monotone ladder (each adds a
      conjunct), so edges can only be removed; the output is tagged with the
      rule the DAG was proved under.  A DAG whose rule is unstated is not
      citable.  Only a graph still cyclic under `pk` is genuinely cyclic.
      Exit 3 = graph is CYCLIC (a real outcome, branchable, not an error).

  run        <folder> --edges FILE [--maxrows N] [--md] [--formulas mark|text]
      EXECUTE a VERIFIED DAG (the edges.tsv written by `dag`) and emit the
      joined table as a bin2md-shaped cell stream: {k,r,c,v,a?,f?,t?,src}.
      Row 1 is the header, emitted as ordinary cells.  `r`/`c` are the RESULT
      position; `a` remains the SOURCE address and `f` the LIVE formula, so a
      consumer can write back.  Keys are matched on `tostring` (bin2md emits
      every .v as a string); a null key never joins.
      --md renders that SAME stream as markdown (jq/cells-md.jq) -- a VIEW,
      not a second artifact, so table and cells cannot disagree.
      Consumes the output of `dag`, never a raw proposal: an unverified edge
      is exactly the zero-overlap join this pipeline exists to reject, and
      running one produces a plausible EMPTY table.

Exit: 0 ok, 2 usage/error, 3 cyclic graph. Empty input folder is an ERROR,
not an empty success.
EOF
}

# List sidecars NUL-separated: filenames in this corpus contain spaces,
# parentheses and '#'.  Word-splitting $(find) mangles them silently.
list_sidecars() {
  # -xtype f, NOT -type f: the sidecar may be a SYMLINK to the real file.
  # Measured, not assumed -- ssg-sim's bench jail is built entirely from
  # per-file symlinks (`setup_run`: "ONE SYMLINK PER FILE inside REAL
  # directories"), so `-type f` matched ZERO of 6 sidecars there while
  # `-xtype f` matched all 6.  The failure was silent in the worst way: the
  # verbs exited 2 "no *.prg.jsonl found" on a directory visibly full of
  # them, which reads as a corpus problem rather than a predicate bug.
  # -xtype f still excludes directories AND dangling links (it stats the
  # TARGET), so the exclusion contract below is unchanged.
  #
  # The two ! -name exclusions stop the artifact being its own input (6.13):
  # `join.prg.jsonl` matches this very glob, so writing it to the folder root
  # drops it into the stream that feeds the NEXT run.  MEASURED in this fork
  # before the fix: planting a CELL-shaped join.prg.jsonl took `schema` from
  # 17 nodes to 18, the extra one literally named "join".  A MODEL-shaped
  # artifact is harmless here only by luck (table-schema.jq returns [] for
  # it), so testing with one is green theatre -- use the cell-shaped arm.
  find "$1" -maxdepth 1 -xtype f -name '*.prg.jsonl' \
       ! -name 'join.prg.jsonl' ! -name '*.out.prg.jsonl' -print0 | sort -z
}

cmd_schema() {
  local dir="" maxhdr=12 minw=2
  while [ $# -gt 0 ]; do
    case "$1" in
      --maxhdr) maxhdr="$2"; shift 2 ;;
      --minw)   minw="$2";   shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  [ -d "$dir" ] || die "not a directory: $dir"

  local n=0 f base
  while IFS= read -r -d '' f; do
    n=$((n+1))
    base="$(basename "$f")"; base="${base%.prg.jsonl}"
    # Per-file jq: a sheet split across files would yield a confidently WRONG
    # rectangle rather than a visible error.  Shard by FILE, always.
    jq -s -c -f "$JQD/table-schema.jq" \
       --arg file "$base" --arg maxhdr "$maxhdr" --arg minw "$minw" \
       < "$f" || die "jq failed on: $base"
  done < <(list_sidecars "$dir")

  [ "$n" -gt 0 ] || die "no *.prg.jsonl found in: $dir"
}

# Column value-domain index for the whole folder.  Emitted on stdout so the
# caller can inspect it; `candidates` consumes it directly.
cmd_colvals() {
  local dir="${1:-}"; shift || true
  [ -n "$dir" ] || { usage >&2; exit 2; }
  [ -d "$dir" ] || die "not a directory: $dir"
  local f base sch
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"; base="${base%.prg.jsonl}"
    # Per-file schema first: column-values needs hdr_row to skip banner rows.
    sch="$(jq -s -c -f "$JQD/table-schema.jq" --arg file "$base" < "$f" \
           | jq -s -c .)" || die "schema failed on: $base"
    [ "$sch" = "[]" ] && continue
    jq -s -c -f "$JQD/column-values.jq" \
       --arg file "$base" --arg schema "$sch" < "$f" \
       || die "column-values failed on: $base"
  done < <(list_sidecars "$dir")
}

# Verify a PROPOSED edge set.  Reads the proposal on stdin (or --edges FILE) as
# src<TAB>dst<TAB>lcol<TAB>rcol.  Emits edges.tsv / rejects.tsv / dag.mmd into
# --out DIR (default: cwd) plus a one-line JSON verdict on stdout.
cmd_dag() {
  local dir="" edges="-" out="." rule="value" minshared=1 escalate=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --edges)       edges="$2";     shift 2 ;;
      --out)         out="$2";       shift 2 ;;
      --rule)        rule="$2";      shift 2 ;;
      --escalate)    escalate=1;     shift ;;
      --min-overlap) minshared="$2"; shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  [ -d "$dir" ] || die "not a directory: $dir"

  # The proposal goes to jq via --rawfile, NOT --arg.  Measured: a 6110-edge
  # proposal (the full derived edge set for one case) blows ARG_MAX and jq dies
  # with "Argument list too long" -- a size limit is not an acceptable ceiling
  # on how big a graph this can verify.
  local etf; etf="$(mktemp)" || die "mktemp failed"
  if [ "$edges" = "-" ]; then cat > "$etf"
  else [ -f "$edges" ] || die "no such edge file: $edges"; cat "$edges" > "$etf"; fi
  [ -s "$etf" ] && grep -q '[^[:space:]]' "$etf" \
    || die "empty edge proposal: nothing to verify"

  mkdir -p "$out" || die "cannot create out dir: $out"

  # Compute the value domains ONCE.  Escalation re-verifies the same proposal
  # under a stricter rule; re-walking the sidecars per rung would triple the
  # only genuinely expensive step for no new information.
  local cv; cv="$(cmd_colvals "$dir")" || die "colvals failed"
  [ -n "$cv" ] || die "no column values extracted from: $dir"

  verify_at() {
    printf '%s\n' "$cv" | jq -s -c -f "$JQD/dag-verify.jq" \
      --rawfile edges "$etf" --arg rule "$1" --arg minshared "$minshared"
  }

  local res prev_edges=""
  if [ "$escalate" = "1" ]; then
    # ESCALATE THE EDGE RULE BEFORE ESCALATING THE ALGORITHM (item 2.3).
    # A cycle is first attacked with stricter EVIDENCE, not with a cycle
    # algorithm: measured corpus-wide, 55.4% of value-cyclic cases become
    # acyclic under `pk`.  Only what survives all three rungs is truly cyclic
    # and belongs to prg-cyclic.sh.
    local r
    for r in name value pk; do
      res="$(verify_at "$r")" || die "dag verification failed at rule=$r"
      [ -n "$res" ] || die "dag verification produced no output at rule=$r"
      local ne; ne="$(printf '%s' "$res" | jq -r '.n_edges')"
      # The ladder adds conjuncts, so edges can only ever be removed.  If this
      # ever trips, the implementation is wrong -- not the corpus.
      if [ -n "$prev_edges" ] && [ "$ne" -gt "$prev_edges" ]; then
        die "INVARIANT VIOLATED: rule=$r yielded $ne edges > $prev_edges from the looser rung"
      fi
      prev_edges="$ne"
      # Escalate on the UNDIRECTED cycle: a directed DAG that sits on an
      # undirected cycle is an artifact of the proposer's orientation, and
      # stopping there would report a DAG the data does not support.
      if printf '%s' "$res" | jq -e '.acyclic and (.undirected_cyclic | not)' >/dev/null; then
        rule="$r"; break
      fi
      printf 'cyclic under rule=%s (%s edges, undirected_cyclic=%s) -- escalating\n' \
        "$r" "$ne" "$(printf '%s' "$res" | jq -r '.undirected_cyclic')" >&2
      rule="$r"
    done
  else
    res="$(verify_at "$rule")" || die "dag verification failed"
    [ -n "$res" ] || die "dag verification produced no output"
  fi

  # edges.tsv -- the verified graph
  { printf 'src\tdst\tlhdr\trhdr\tn_l\tn_r\tn_shared\tcontain\trule\n'
    printf '%s' "$res" | jq -r '.edges[]
      | [.src_node,.dst_node,.lhdr,.rhdr,.n_l,.n_r,.n_shared,.contain,.tried]
      | @tsv'
  } > "$out/edges.tsv"

  # rejects.tsv -- FIRST-CLASS output (item 2.2), not an absence.  Carries the
  # measured counts and the loosest rule tried, so "cannot be joined" is citable.
  { printf 'src\tdst\tlcol\trcol\tn_l\tn_r\tn_shared\ttried\twhy\n'
    printf '%s' "$res" | jq -r '.rejects[]
      | [.src,.dst,.lcol,.rcol,.n_l,.n_r,.n_shared,.tried,.why] | @tsv'
  } > "$out/rejects.tsv"

  # dag.mmd -- mermaid, edge labels carry the MEASURED overlap
  { echo 'graph LR'
    printf '%s' "$res" | jq -r '
      def id: gsub("[^A-Za-z0-9]"; "_");
      .edges[]
      | "  \(.src_node|id)[\"\(.src_node)\"] -->|\(.lhdr)=\(.rhdr) n=\(.n_shared)| \(.dst_node|id)[\"\(.dst_node)\"]"'
    printf '%s' "$res" | jq -r 'if .cycle then "  %% DIRECTED CYCLE: " + (.cycle | join(" -> ")) else empty end,
      (if .vacuous_dag then "  %% VACUOUS: directed-acyclic only because of edge orientation; the UNDIRECTED join graph has a cycle" else empty end)'
  } > "$out/dag.mmd"

  # Full verdict (edges + rejects included) for programmatic consumers such as
  # prg-cyclic.sh, which needs the surviving edge list to pick the weakest one.
  printf '%s' "$res" > "$out/verdict.json"

  rm -f "$etf"
  printf '%s' "$res" | jq -c 'del(.edges, .rejects)'
  # A cycle is a real outcome, not a crash: exit 3 so a caller can branch on it
  # (item 2.3 escalates the rule; 2.4 hands off to prg-cyclic.sh).
  printf '%s' "$res" | jq -e '.acyclic and (.undirected_cyclic | not)' >/dev/null || return 3
  return 0
}

cmd_candidates() {
  local dir="" minshared=1 top=0 minvals=2 ratio=100 all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --min-overlap|--min-shared) minshared="$2"; shift 2 ;;
      --top)         top="$2";       shift 2 ;;
      --minvals)     minvals="$2";   shift 2 ;;
      --ratio)       ratio="$2";     shift 2 ;;
      --all)         all=1;          shift ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  # 06/4.3 BACK-PROPAGATION LEDGER.  Stage-2 (real SQL) findings live WITH
  # the corpus, so they are picked up by presence -- no flag to remember and
  # no way to run the corpus without the findings it has already earned.
  # Absent file => the argument is not passed at all => byte-identical output
  # (verified: 0 lines differ across 20,460 rows).
  local led="$dir/join-findings.jsonl"
  if [ -f "$led" ]; then
    cmd_colvals "$dir" \
      | jq -s -c -f "$JQD/join-candidates.jq" \
          --arg minshared "$minshared" --arg top "$top" \
          --arg minvals "$minvals" --arg ratio "$ratio" --arg all "$all" \
          --slurpfile ledger "$led"
  else
    cmd_colvals "$dir" \
      | jq -s -c -f "$JQD/join-candidates.jq" \
          --arg minshared "$minshared" --arg top "$top" \
          --arg minvals "$minvals" --arg ratio "$ratio" --arg all "$all"
  fi
}

# Value-SHAPE histogram per column.  Sits on colvals so the sidecars are
# walked ONCE; a shape probe that re-scanned would be slower than the trial
# query it exists to avoid.
cmd_shapes() {
  local dir="" sample=400 top=5 colre=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sample) sample="$2"; shift 2 ;;
      --top)    top="$2";    shift 2 ;;
      --col)    colre="$2";  shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  cmd_colvals "$dir" \
    | jq -s -c -f "$JQD/column-shapes.jq" \
        --arg sample "$sample" --arg top "$top" \
    | { if [ -n "$colre" ]; then
          jq -c --arg re "$colre" 'select(.hdr|test($re))'
        else cat; fi; }
}


# EMIT THE JOIN MODEL -- the context artifact (6.2, reshaped by 6.16).
#
# Wired as a subcommand now because 6.16 gave it a real caller-facing knob
# (--budget-tok): "run this jq by hand with two --slurpfiles" is not a thing a
# consumer can be asked to size against its own context window.  This also
# closes 6.2's :open: (never wired as `model)`).
#
# Note it feeds join-model.jq the `candidates --all` stream: the model does its
# OWN pruning (mincontain/minshared) and needs the rejects to build the warn
# row, so pre-filtering here would silently delete the warning.
cmd_model() {
  local dir="" minshared=20 mincontain=0.9 budgettok=0 topk=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --min-overlap|--min-shared) minshared="$2"; shift 2 ;;
      --min-contain) mincontain="$2"; shift 2 ;;
      --budget-tok)  budgettok="$2";  shift 2 ;;
      --top-k)       topk="$2";       shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  [ -d "$dir" ] || die "not a directory: $dir"

  local sch cand
  sch="$(mktemp)"; cand="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$sch' '$cand'" RETURN
  cmd_schema "$dir" > "$sch" || die "schema failed"
  cmd_candidates "$dir" --min-shared 1 --all > "$cand" || die "candidates failed"
  jq -s -c -f "$JQD/join-model.jq" --slurpfile schema "$sch" \
      --arg minshared "$minshared" --arg mincontain "$mincontain" \
      --arg budgettok "$budgettok" --arg topk "$topk" "$cand" \
    || die "join-model failed"
}

# EXECUTE a verified DAG: walk edges.tsv in order and emit the joined result as
# a bin2md-shaped cell stream.  Consumes the output of `dag`, never a raw
# proposal -- an unverified edge is exactly the zero-overlap join this pipeline
# exists to reject, and running one would produce a plausible empty table.
cmd_run() {
  local dir="" edges="" maxrows=100000 md=0 formulas="mark"
  while [ $# -gt 0 ]; do
    case "$1" in
      --edges)   edges="$2";   shift 2 ;;
      --maxrows) maxrows="$2"; shift 2 ;;
      --md)      md=1;         shift ;;
      --formulas) formulas="$2"; shift 2 ;;
      -*) die "unknown option: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || { usage >&2; exit 2; }
  [ -d "$dir" ] || die "not a directory: $dir"
  [ -n "$edges" ] || die "run requires --edges FILE (output of: dag --out DIR)"
  [ -f "$edges" ] || die "no such edge file: $edges"

  # The header row per (file,sheet) is a SCHEMA fact, so derive it from the
  # same detector `schema` uses rather than re-guessing here -- two header
  # oracles in one pipeline is how the empty-join bug above happened.
  local schema_f; schema_f="$(mktemp)" || die "mktemp failed"
  cmd_schema "$dir" > "$schema_f" || die "schema failed for: $dir"
  [ -s "$schema_f" ] || die "schema produced nothing for: $dir"

  # Resolve a "file::sheet" node to its sidecar and append it to the node list.
  # The sheet half stays separate: select.jq filters by sheet, so a file with
  # two sheets is two nodes over ONE sidecar.
  #
  # This deliberately does NOT pipe node_rows into jq.  On the left of a pipe
  # the function runs in a subshell, so `die` kills only that subshell and the
  # pipeline reports jq's status -- a missing sidecar then exits 0 with a
  # SHORT-BUT-PLAUSIBLE join, the same silent-partial failure the sharded
  # colvals had.  Staging through a temp file keeps every failure fatal.
  emit_node() {
    local node="$1"; shift
    local file="${node%%::*}" sheet="${node#*::}"
    local path="$dir/$file.prg.jsonl"
    [ -f "$path" ] || die "no sidecar for node: $node (looked for $path)"
    # The HEADER ROW MUST COME FROM `schema`, never from select.jq's default.
    # select.jq defaults --argjson hdr to 1; `schema` detects the real one and
    # it is usually NOT row 1 (fact 1 of the plan: FILTER-then-earliest).
    # Measured bug this fixes: sheet "5.20" has hdr_row=3 with key column
    # NAME, but running it at hdr 1 picked "WEEK 5/20 - MEMORIAL DAY WK" as
    # the header and demoted NAME to DATA -- 4 rows instead of 13, the join
    # key absent, and `run` emitted an EMPTY table at rc=0.  A silent empty
    # join is the exact failure this pipeline exists to prevent, so the
    # header row is looked up per node and a miss is FATAL, not defaulted.
    local hdr
    hdr="$(jq -s -r --arg f "$file" --arg s "$sheet" \
             'map(select(.file==$f and (.sheet//"")==$s)) | .[0].hdr_row // empty' \
             "$schema_f")"
    [ -n "$hdr" ] || die "no schema row for node: $node (run \`schema\` on $dir)"
    local rf; rf="$(mktemp)" || die "mktemp failed"
    jq -s -c -f "$JQD/select.jq" --argjson cells 1 --arg sheet "$sheet" \
       --argjson hdr "$hdr" "$path" > "$rf" \
      || { rm -f "$rf"; die "select failed for node: $node"; }
    [ -s "$rf" ] || { rm -f "$rf"; die "node has no rows: $node"; }
    jq -s -c --arg n "$node" "$@" "$rf" >> "$tmp" \
      || { rm -f "$rf"; die "node assembly failed: $node"; }
    rm -f "$rf"
  }

  # Build the node list in DAG-walk order: the first edge's src is the root,
  # then one entry per edge carrying the join columns.
  local tmp; tmp="$(mktemp)" || die "mktemp failed"
  # ONE trap for BOTH tempfiles: a second `trap ... RETURN` REPLACES the first
  # rather than adding to it, so registering them separately silently leaks
  # whichever was registered earlier.
  # shellcheck disable=SC2064
  trap "rm -f '$tmp' '$schema_f'" RETURN

  local src dst lhdr rhdr first=1 n=0
  while IFS=$'\t' read -r src dst lhdr rhdr _rest; do
    [ "$src" = "src" ] && continue          # header line
    [ -n "$src" ] || continue
    if [ "$first" = "1" ]; then
      emit_node "$src" '{node:$n, rows:.}'
      first=0
    fi
    emit_node "$dst" --arg l "$lhdr" --arg r "$rhdr" \
      '{node:$n, lcol:$l, rcol:$r, rows:.}'
    n=$(( n + 1 ))
  done < "$edges"

  [ "$n" -gt 0 ] || die "no edges in: $edges (a verified DAG with 0 edges has nothing to join)"

  # --md renders the SAME stream; it never takes a different path to the data,
  # so the table and the cells cannot disagree.
  if [ "$md" = "1" ]; then
    # BOTH stages must be checked.  $? alone is the RENDERER's status, so a
    # failed join renders an empty table and exits 0; PIPESTATUS[0] alone
    # misses a rejected --formulas, which is the LAST stage.  Capture the
    # whole array once -- it is clobbered by the next command, including by
    # the `[` test itself.
    local st
    jq -s -c -f "$JQD/join-run.jq" --arg maxrows "$maxrows" "$tmp" \
      | jq -s -r -f "$JQD/cells-md.jq" --arg formulas "$formulas"
    st="${PIPESTATUS[*]}"
    [ "${st%% *}" = "0" ] || die "join-run failed"
    [ "${st##* }" = "0" ] || die "markdown render failed"
  else
    jq -s -c -f "$JQD/join-run.jq" --arg maxrows "$maxrows" "$tmp" \
      || die "join-run failed"
  fi
}

main() {
  [ $# -ge 1 ] || { usage >&2; exit 2; }
  local sub="$1"; shift
  case "$sub" in
    schema)      cmd_schema "$@" ;;
    colvals)     cmd_colvals "$@" ;;
    candidates)  cmd_candidates "$@" ;;
    shapes)      cmd_shapes "$@" ;;
    model)       cmd_model "$@" ;;
    dag)         cmd_dag "$@" ;;
    run)         cmd_run "$@" ;;
    -h|--help)   usage ;;
    *)           die "unknown subcommand: $sub" ;;
  esac
}

main "$@"
