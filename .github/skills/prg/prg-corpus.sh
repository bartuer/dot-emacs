#!/usr/bin/env bash
# prg-corpus.sh — search a BINARY-PARSED document corpus.  NO LLM.
#
# The fourth prg SOURCE, beside repo / log / trace.  Its corpus is the output
# of src/collect/index_folder.sh (plan 256), not a source tree:
#
#   <corpus>/…     extracted markdown as SIDECARS beside each source file,
#                  report.docx -> report.docx.md, minified bin2md provenance
#                  JSON on line 1, text from line 2 (no .md.meta.json)
#   index.jsonl    one row per document  {path, kind, ok, chars, out}
#   sheets.jsonl   one row per workbook  {path, cells, formulas, charts, ok}
#   summary.json   rolled-up counts + timings
#
# Set via --corpus or PRG_DOC_CORPUS; no default, so an unset corpus exits 4
# rather than silently searching a wrong path.
#
# WHY THIS EXISTS AND PLAIN `rg md/` DOES NOT DO IT
# The corpus is organized so files inside ONE CASE FOLDER are semantically
# related — the case, not the file, is the unit of meaning, and plain rg
# answers at the FILE level.  Every subverb here rolls up to the case.  The
# jsonl lenses derive it via jq/corpus-case.jq; `search` reads it
# straight off the hit path, since sidecars live inside the case folder.
#
# Subverbs:
#   search <regex> [-- rg args]  -> {case, path, line, content}  (md sidecars)
#   case <case-id>               -> every indexed artifact in one case folder
#   stat [--by kind|case]        -> rolled-up counts from index+sheets
#   sheets <jqfilter>            -> jq -c over sheets.jsonl, case-tagged
#   docs <jqfilter>              -> jq -c over index.jsonl, case-tagged
#   failed                       -> every ok:false / degraded row (both files)
#
# CAVEAT carried from plan 256 G2.3: sheets.jsonl `cells` is a BOUNDING-
# RECTANGLE metric (silo >= openpyxl in 20/20 sampled workbooks), NOT a
# populated-cell count.  `formulas` corroborated 20/20 EXACTLY.  Rank on
# formulas; do not read `cells` as "amount of data".
#
# Exit: 0 ok · 2 bad args/deps · 4 corpus absent · 5 corpus incomplete.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="$HERE/jq"
CORPUS="${PRG_DOC_CORPUS:-}"
PRETTY=0
BY=kind

command -v jq >/dev/null || { echo "prg-corpus: jq required" >&2; exit 2; }
command -v rg >/dev/null || { echo "prg-corpus: ripgrep required" >&2; exit 2; }

args=(); while [ $# -gt 0 ]; do case "$1" in
  --pretty) PRETTY=1; shift;;
  --corpus) CORPUS="${2:?--corpus needs a path}"; shift 2;;
  --by)     BY="${2:?--by needs kind|case}"; shift 2;;
  --)       shift; break;;
  *) args+=("$1"); shift;;
esac; done
RG_EXTRA=("$@")
set -- "${args[@]:-}"
SUB="${1:-}"; shift || true

usage() {
  sed -n '2,32p' "$HERE/prg-corpus.sh" | sed 's/^# \{0,1\}//'
  echo
  echo "schema: search -> {case,path,src,line,content} · stat -> {key,n,...}"
  echo "        case <id> -> {case,kind,path,...} · failed -> {case,path,why}"
}

case "$SUB" in ""|-h|--help) usage; [ -z "$SUB" ] && exit 2 || exit 0;; esac

[ -d "$CORPUS" ] || { echo "prg-corpus: corpus '$CORPUS' absent (set PRG_DOC_CORPUS or --corpus)" >&2; exit 4; }
IDX="$CORPUS/index.jsonl"; SHT="$CORPUS/sheets.jsonl"; SUM="$CORPUS/summary.json"
# `search` needs a TREE; the jsonl lenses need MANIFESTS.  Default the tree
# to $CORPUS so you can point straight at a document folder and search it
# with no index at all; if $CORPUS is an index dir, take the root the
# indexer recorded rather than adding a second flag that could disagree.
DOCROOT="$CORPUS"
[ ! -f "$SUM" ] || DOCROOT="$(jq -r --arg d "$CORPUS" '.corpus // $d' "$SUM" 2>/dev/null || echo "$CORPUS")"
# An index dir missing its manifests is NOT an empty result — it is a broken
# corpus, and the two must not look alike to a caller.  Exit 5, distinctly.
# Checked PER SUBVERB, not at startup: `search` reads the tree, so requiring
# a manifest for it would refuse the plain "search this folder" case.
need_idx() { [ -f "$IDX" ] || { echo "prg-corpus: '$CORPUS' has no index.jsonl — not an indexed corpus" >&2; exit 5; }; }

NP="$(nproc 2>/dev/null || echo 4)"

# Manifest validation gate.  Found by negative control: a single corrupt JSON
# row makes jq abort mid-stream, and every subverb downstream then reports the
# rows it managed to read AS IF THEY WERE THE WHOLE CORPUS — 20 of 50 rows,
# no warning, exit 0.  That is the plan-256 G2b.1 defect (summary.json cannot
# establish completeness) reappearing one layer up, so it gets refused here
# rather than re-discovered by a caller who trusts the number.
# jq -e over the whole file is O(size) but ~50ms on a 1.1MB manifest: cheap
# next to being confidently wrong.
validate_manifest() {
  local f="$1" n
  n=$(jq -c . "$f" 2>/dev/null | wc -l) || true
  local raw; raw=$(grep -c '' "$f" 2>/dev/null || echo 0)
  if [ "$n" -ne "$raw" ]; then
    echo "prg-corpus: '$f' is CORRUPT — $n of $raw rows parse as JSON." >&2
    echo "prg-corpus: refusing to report partial counts as complete." >&2
    exit 5
  fi
}
validate_manifest "$IDX"
[ -f "$SHT" ] && validate_manifest "$SHT"

# out-path -> "case<TAB>original-path".  Built once per invocation; the join
# is what keeps a flat-md hit answerable at case level.
join_tbl() {
  jq -r -f "$JQ/corpus-case.jq" "$IDX" \
    | jq -r 'select(.out != null) | [.out, .case, .path] | @tsv'
}

case "$SUB" in
  search)
    pat="${1:?usage: prg-corpus.sh search <regex> [-- rg args]}"
    [ -d "$DOCROOT" ] || { echo "prg-corpus: search root '$DOCROOT' absent" >&2; exit 5; }
    # SIDECAR LAYOUT KILLED THE JOIN.  This used to rg a FLAT md/ dir, where
    # a hit read "Q3 deck DRAFT.pptx.703b0cd9.md" and the case was gone, so
    # every hit had to be rejoined to index.jsonl .out through a jq table.
    # Artifacts now sit BESIDE their source, i.e. INSIDE the case folder, so
    # the hit path already carries the case id.  The join is not optimised
    # here, it is DELETED: it existed only to undo a flattening we no longer
    # do.  Bonus, search no longer needs index.jsonl at all -- it reads the
    # corpus, so it cannot go stale against it.
    rg --json -g '*.md' "${RG_EXTRA[@]}" -- "$pat" "$DOCROOT" 2>/dev/null \
      | jq -n -c -f "$JQ/search-hit.jq" \
      | jq -c '
          # Line 1 of an artifact is bin2md provenance, and it RESTATES the
          # source path -- so a match there is a duplicate of the real hit,
          # the same false positive the old .md.meta.json sidecars caused
          # (measured attribution 0.991 instead of 1.000).  Same defect, new
          # shape: drop it by WITNESS, never by line number alone, or a
          # corpus-own .md that genuinely matches on line 1 is lost.
          select((.line == 1 and (.content | startswith("{\"source\":"))
                                and (.content | contains("\"bin2md\""))) | not)
          | .path as $p
          | {case: (if ($p | test("/cases/"))
                    then ($p | split("/cases/")[1] | split("/")[0])
                    else "«nocase»" end),
             path: $p, line, content}'
    ;;

  case)
    need_idx
    cid="${1:?usage: prg-corpus.sh case <case-id>}"
    { jq -c -f "$JQ/corpus-case.jq" "$IDX" \
        | jq -c --arg c "$cid" 'select(.case == $c) | {case, kind, ok, chars, path, out}'
      [ ! -f "$SHT" ] || jq -c -f "$JQ/corpus-case.jq" "$SHT" \
        | jq -c --arg c "$cid" 'select(.case == $c) | {case, kind:"xlsx", ok, cells, formulas, charts, path}'
    } || true
    ;;

  stat)
    need_idx
    case "$BY" in
      kind)
        { jq -c -f "$JQ/corpus-case.jq" "$IDX" \
            | jq -c '{k: (.kind // "«unknown»"), ok: (.ok == true), chars: (.chars // 0)}'
        } | jq -s -c 'group_by(.k) | map({key: .[0].k, n: length,
                        ok: (map(select(.ok)) | length),
                        chars: (map(.chars) | add)}) | sort_by(-.n)[]'
        [ ! -f "$SHT" ] || jq -c -f "$JQ/corpus-case.jq" "$SHT" \
          | jq -s -c '{key: "xlsx(sheets)", n: length,
                       ok: (map(select(.ok == true)) | length),
                       cells: (map(.cells // 0) | add),
                       formulas: (map(.formulas // 0) | add),
                       charts: (map(.charts // 0) | add)}'
        ;;
      case)
        # per-case rollup across BOTH manifests — the unit of meaning.
        { jq -c -f "$JQ/corpus-case.jq" "$IDX" | jq -c '{case, docs: 1, formulas: 0}'
          [ ! -f "$SHT" ] || jq -c -f "$JQ/corpus-case.jq" "$SHT" \
            | jq -c '{case, docs: 0, formulas: (.formulas // 0)}'
        } | jq -s -c 'group_by(.case) | map({key: .[0].case, n: length,
                        docs: (map(.docs) | add),
                        formulas: (map(.formulas) | add)}) | sort_by(-.formulas)[]'
        ;;
      *) echo "prg-corpus: --by must be kind|case" >&2; exit 2;;
    esac
    ;;

  sheets)
    need_idx
    [ -f "$SHT" ] || { echo "prg-corpus: no sheets.jsonl in '$CORPUS'" >&2; exit 5; }
    filt="${1:?usage: prg-corpus.sh sheets '<jq filter>'}"
    tmpf="$(mktemp /tmp/prg-corpus-f.XXXXXX.jq)"; trap 'rm -f "$tmpf"' EXIT
    printf '%s\n' "$filt" > "$tmpf"
    jq -c -f "$JQ/corpus-case.jq" "$SHT" | jq -c -f "$tmpf"
    ;;

  docs)
    need_idx
    filt="${1:?usage: prg-corpus.sh docs '<jq filter>'}"
    tmpf="$(mktemp /tmp/prg-corpus-f.XXXXXX.jq)"; trap 'rm -f "$tmpf"' EXIT
    printf '%s\n' "$filt" > "$tmpf"
    jq -c -f "$JQ/corpus-case.jq" "$IDX" | jq -c -f "$tmpf"
    ;;

  failed)
    need_idx
    # A row the parser could not read is the most interesting row in the file
    # — this corpus plants .xls that actually hold HTML export tables.  Both
    # manifests, one stream, never dropped.
    { jq -c -f "$JQ/corpus-case.jq" "$IDX" \
        | jq -c 'select(.ok != true) | {case, path, kind, why: (.msg // .degraded // "unknown")}'
      [ ! -f "$SHT" ] || jq -c -f "$JQ/corpus-case.jq" "$SHT" \
        | jq -c 'select(.ok != true) | {case, path, kind: "xlsx", why: "silo-unreadable"}'
    } || true
    ;;

  *) echo "prg-corpus: unknown subverb '$SUB' (search|case|stat|sheets|docs|failed)" >&2; exit 2;;
esac
