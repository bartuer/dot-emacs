#!/usr/bin/env bash
# prg-silo.sh — query a WORKBOOK the way prg-corpus queries a document corpus.
#
# The fifth prg SOURCE, beside repo / log / trace / corpus.  Its corpus is a
# single .xlsx (or a list of them), read through `silo`, never through Excel:
#
#   cells   silo --dump-json      {s,r,c,a,t,v,f?}   one row per CELL
#   meta    silo --dump-meta-json {k,s,...}          sheets, tables, charts, af
#
# WHY THIS EXISTS AND PLAIN `silo | jq` DOES NOT DO IT
# silo answers at the CELL level; a question is almost always asked at the
# ROW or the RECTANGLE level.  Two gaps have to be closed every single time:
#   1. a row has no container in the stream  -> jq/select.jq rebuilds it
#   2. a sheet has no stated extent          -> `where` reads the DECLARED one
# Both are already solved and BOTH ARE EASY TO GET WRONG BY HAND (see the
# --pipe ban below, and the meta/cell mixing rule).  This wraps them; it does
# not reimplement them.
#
# DECLARED, NEVER INFERRED.  `where` reports only rectangles the AUTHOR
# declared (a Ctrl+T ListObject, or the sheet autoFilter): silo tags those
# sig=boundary conf=2.  It does NOT guess a table from data shape.  A sheet
# with no declaration yields NOTHING here, and that is the honest answer --
# ~74% of a real corpus is in that state, which is what makes an inferring
# detector a separate, benched piece of work rather than a one-liner.
#
# !! `rows` IS NOT DECOMPOSABLE -- never run it under `parallel --pipe`.  A
# row's cells are adjacent in the stream, so a block boundary can CUT A ROW
# IN HALF; both halves then fail the WHERE and vanish SILENTLY, leaving a
# plausible smaller count.  Shard by FILE -- rows never span workbooks.
#
# Subverbs:
#   sheets  FILE                  -> {sheet, idx, frozen_rows?, frozen_cols?}
#   where   FILE                  -> {sheet, kind, ref, conf}  DECLARED rects
#   rows    FILE [lens args]      -> {r, a?, row:{<header>: value}}  (select.jq)
#   cells   FILE [jqfilter]       -> raw cell stream, optionally filtered
#   meta    FILE [jqfilter]       -> raw meta stream, optionally filtered
#
# Exit: 0 ok · 2 bad args/deps · 4 file absent · 5 silo could not read it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="$HERE/jq"
SILO="${PRG_SILO:-silo}"

# the index-first resolver, factored out (plan 256 G10.2) so prg-case.sh gets
# the SAME staleness rule instead of a second copy that can drift.
# shellcheck source=prg-source.sh
. "$HERE/prg-source.sh"

usage() {
  # --help is JSON so a model needs no second document, and so a caller can
  # branch on it.  The tool's own contract is machine-readable or it is not
  # a contract.  (The prose header above is for humans reading the source.)
  #
  # silo's own help is an OPTIONAL enrichment, not a dependency: piping
  # `$SILO --help` straight into jq made --help emit NOTHING when silo was
  # missing, so the tool failed its own :test_tool: (`--help | jq -e .`)
  # on exactly the machine where a caller most needs to read it.  Resolve
  # it to `null` instead and keep our half of the contract printable.
  local sh s
  sh="$("$SILO" --help 2>/dev/null || true)"
  if printf '%s' "$sh" | jq -e . >/dev/null 2>&1; then s="$sh"; else s=null; fi
  jq -n --arg silo "$SILO" --argjson s "$s" '{
    name: "prg-silo.sh",
    desc: "query a workbook: rows, declared rectangles, cells, meta. NO LLM.",
    usage: "prg-silo.sh SUB FILE [args]",
    subverbs: {
      sheets: "{sheet,idx,frozen_rows?,frozen_cols?} one row per sheet",
      where:  "{sheet,kind,ref,conf} DECLARED rectangles only (sig=boundary)",
      rows:   "{r,a?,row:{<header>:value}} via jq/select.jq (a = A1 address, absent for address-less formats); takes its --arg knobs",
      cells:  "raw silo --dump-json cells, optional jq filter as $2",
      meta:   "raw silo --dump-meta-json rows, optional jq filter as $2"
    },
    declared_only: ("where reports ONLY author-declared rectangles (conf 2). "
      + "It does not infer a table from data shape; a sheet with no "
      + "declaration yields nothing, which is the honest answer."),
    not_decomposable: ("rows must NOT run under parallel --pipe: a block "
      + "boundary can cut a row in half and both halves fail the WHERE "
      + "silently. Shard by FILE."),
    exit: {"0":"ok","2":"bad args/deps","4":"file absent","5":"silo cannot read it"},
    silo: ({bin: $silo, available: ($s != null)}
      + (if $s == null then {}
         else {boundary: $s.boundary, table: $s.table, af: $s.af, modes: $s.modes}
         end))
  }'
}

case "${1:-}" in
  ""|-h|--help) usage; [ -z "${1:-}" ] && exit 2 || exit 0;;
esac

command -v jq >/dev/null || { echo "prg-silo: jq required" >&2; exit 2; }
command -v "$SILO" >/dev/null || { echo "prg-silo: '$SILO' not on PATH (set PRG_SILO)" >&2; exit 2; }

SUB="$1"; shift
# Validate the SUBVERB before the FILE.  Found by negative control: with the
# checks the other way round, `prg-silo.sh bogus f.xlsx` reported exit 4
# ("file absent") for a mistyped subverb -- pointing the caller at the one
# argument that was fine.  Diagnose the error the caller actually made.
case "$SUB" in
  sheets|where|rows|cells|meta) ;;
  *) echo "prg-silo: unknown subverb '$SUB'" >&2; usage >&2; exit 2;;
esac
FILE="${1:-}"; shift || true
[ -n "$FILE" ] || { echo "prg-silo: $SUB needs a FILE" >&2; exit 2; }
[ -f "$FILE" ] || { echo "prg-silo: '$FILE' absent" >&2; exit 4; }

# silo exits 0 with a `degraded`/`err` row for a file it cannot parse, so a
# bare exit check is NOT enough -- an unreadable workbook would look like an
# empty sheet.  Materialize once, then refuse explicitly.
# ---- prg index first, binary only as fallback -------------------------
# A `<FILE>.prg.jsonl` sidecar holds the SAME {s,r,c,a,t,v} cell rows and the
# same meta rows silo would emit, so re-parsing the binary is wasted work --
# and on a 42k-row workbook it is 37MB of it.  VERIFIED equal: 4 workbooks,
# 15/15 rects identical (sheet/ref/rung/hdr_row) sidecar vs binary.
# STALENESS IS THE WHOLE RISK: a sidecar older than its binary describes a
# workbook that no longer exists, and it fails SILENTLY -- plausible rows,
# wrong answer.  Compare mtimes and re-parse when the binary is newer.
# `-nt` is false when either file is missing, which is the safe direction.
# The rule itself lives in prg-source.sh -- ONE definition, two callers.
prg_resolve "$FILE"
SIDECAR="$PRG_SIDECAR"
# a workbook resolves to index or binary; `text` is not reachable for .xlsx,
# but guard anyway so an odd extension cannot silently take the index path.
[ "$PRG_SRC" = index ] && [ -n "$SIDECAR" ] || PRG_SRC=binary

META="$(mktemp)"; trap 'rm -f "$META" "${CELLS:-}"' EXIT
if [ "$PRG_SRC" = index ]; then
  # meta rows are the ones carrying .k; cell rows have no .k.
  jq -c 'select(has("k"))' "$SIDECAR" > "$META" 2>/dev/null
  [ -s "$META" ] || { echo "prg-silo: sidecar '$SIDECAR' has no meta rows" >&2; exit 5; }
else
  "$SILO" --dump-meta-json "$FILE" > "$META" 2>/dev/null || { echo "prg-silo: silo failed on '$FILE'" >&2; exit 5; }
fi
if jq -e 'select(.degraded or .err)' "$META" >/dev/null 2>&1; then
  echo "prg-silo: silo could not parse '$FILE' (degraded)" >&2; exit 5
fi

# cell rows: from the index when fresh, else from the binary.  Cell rows are
# exactly the rows WITHOUT .k -- the sidecar interleaves both streams.
prg_cells() {
  if [ "$PRG_SRC" = index ]; then
    jq -c 'select(has("k")|not)' "$SIDECAR" 2>/dev/null
  else
    "$SILO" --dump-json "$FILE" 2>/dev/null \
      || { echo "prg-silo: silo --dump-json failed" >&2; return 5; }
  fi
}

case "$SUB" in
  sheets)
    jq -c 'select(.k=="sheet") | {sheet:.s, idx:.i}
           + (if .fr then {frozen_rows:.fr} else {} end)
           + (if .fc then {frozen_cols:.fc} else {} end)' "$META"
    ;;
  where)
    # sig=boundary is silo's own contract for "this row names a rectangle and
    # therefore HAS both .s and .ref" -- keying off it (rather than listing
    # k=table,k=af) means a future declared kind is picked up for free.
    jq -c 'select(.sig=="boundary") | {sheet:.s, kind:.k, ref:.ref, conf:.conf}' "$META"
    ;;
  meta)
    if [ $# -gt 0 ] && [ -n "${1:-}" ]; then jq -c "$1" "$META"; else jq -c . "$META"; fi
    ;;
  cells)
    CELLS="$(mktemp)"
    prg_cells > "$CELLS" || exit 5
    if [ $# -gt 0 ] && [ -n "${1:-}" ]; then jq -c "$1" "$CELLS"; else jq -c . "$CELLS"; fi
    ;;
  rows)
    # jq -s: grouping needs the whole sheet (see § in SKILL.md).  Remaining
    # args pass THROUGH to select.jq, so every knob it documents works here
    # unchanged -- no second argument vocabulary to learn or keep in sync.
    CELLS="$(mktemp)"
    prg_cells > "$CELLS" || exit 5
    jq -s -c -f "$JQ/select.jq" "$@" "$CELLS"
    ;;
esac
