#!/usr/bin/env bash
# prg-addr.sh -- map SQLite query results BACK to workbook cell addresses.
#
# WHY THIS EXISTS.  Every other tool in prg/ improves the READ path: find the
# tables, join them, write correct SQL.  None of them can APPLY an answer.
# Loading a corpus into SQLite deliberately drops provenance -- the DDL emits
# the sheet's own headers and `INSERT INTO t VALUES(...)`, so a result row
# knows its VALUES and has no idea which cell they came from.  This script
# puts the address back, so an OfficeJS (or any workbook) caller can write
# into the ORIGINATING cell.
#
# THE RULE: ORDINAL LOOKUP, NEVER ARITHMETIC.  See
# .github/REPL/fix.archive/cell-address-recovery.md for the
# measurement -- `hdr_row + rowid` is wrong on 20 of 24 sheets and wrong
# SILENTLY.  The Nth data row of a table is the Nth surviving cell row, and
# its `a` is read verbatim from the sidecar.
#
# SUBCOMMANDS
#   rows  <folder> --sheet S [--hdr N]        addressed rows, ord = rowid
#   cell  <folder> --sheet S --ord N --col C  ONE cell's address
#   check <folder> --sheet S --db F --table T verify ord->a against a real db
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQD="$HERE/jq"

die() { printf '%s\n' "$*" >&2; exit 2; }

usage() {
  cat <<'EOF'
usage: prg-addr.sh <subcommand> <folder> [options]

  rows <folder> --sheet SHEET [--file SUBSTR] [--hdr N] [--ord N]
      Emit one JSON object per DATA row of SHEET:
        {file, sheet, ord, r, cells:[{c,a,v}]}
      `ord` is 1-based and matches SQLite rowid for the table built from
      that sheet.  --ord N restricts output to a single row.
      --hdr N gives the header row in STREAM coordinates (default: auto via
      prg-join.sh schema).

  cell <folder> --sheet SHEET --ord N --col C
      Print the address of ONE cell as {file,sheet,ord,c,a,v}.
      C is a 1-based column number.  Exits 3 if that cell does not exist
      (an omitted cell is EMPTY in the sheet, not an error in the data --
      but it IS an error to pretend you know its address).

  check <folder> --sheet SHEET --db FILE --table T
      Verify the mapping against a real database: for each row of T,
      compare column 1 to the ordinally recovered cell's value.
      Prints ok/mismatch counts and exits 1 on ANY mismatch.

PERFORMANCE: every subcommand puts a literal `rg` prefilter in front of jq.
Measured 50x on this corpus (750 ms -> 15 ms) for identical output; jq
parsing every line is the cost, not the JSONL format.
EOF
  exit 2
}

[ $# -ge 1 ] || usage
SUB="$1"; shift || true
case "$SUB" in rows|cell|check) ;; -h|--help|help) usage ;; *) die "unknown subcommand: $SUB" ;; esac

[ $# -ge 1 ] || usage
DIR="$1"; shift || true
[ -d "$DIR" ] || die "not a directory: $DIR"

SHEET=""; HDR=""; ORD=""; COL=""; DB=""; TABLE=""; FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sheet) SHEET="${2:-}"; shift 2 ;;
    --file)  FILE="${2:-}";  shift 2 ;;
    --hdr)   HDR="${2:-}";   shift 2 ;;
    --ord)   ORD="${2:-}";   shift 2 ;;
    --col)   COL="${2:-}";   shift 2 ;;
    --db)    DB="${2:-}";    shift 2 ;;
    --table) TABLE="${2:-}"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done
[ -n "$SHEET" ] || die "--sheet is required"

# ---------------------------------------------------------------- file scope
# The addressing key is (FILE, SHEET, ORDINAL) -- never (SHEET, ORDINAL).
# Sheet names repeat across workbooks: in the reference corpus three separate
# scorecard files each carry a sheet called "Targets (from AOP)".  Globbing
# *.prg.jsonl concatenates them, so ordinal 1 becomes whichever file rg read
# first -- a silently wrong address, the exact failure class this script
# exists to prevent.  So: resolve the sheet to exactly ONE file, or refuse.
SRC=""
resolve_file() {
  [ -n "$SRC" ] && return 0
  local hits n
  hits=$(rg -l --fixed-strings "\"s\":\"$SHEET\"" "$DIR"/*.prg.jsonl 2>/dev/null || true)
  [ -n "$hits" ] || die "no file in $DIR contains sheet: $SHEET"
  if [ -n "$FILE" ]; then
    SRC=$(printf '%s\n' "$hits" | rg --fixed-strings "$FILE" | head -1)
    [ -n "$SRC" ] || die "sheet '$SHEET' not found in any file matching: $FILE"
    return 0
  fi
  n=$(printf '%s\n' "$hits" | wc -l)
  if [ "$n" -gt 1 ]; then
    printf 'ambiguous: sheet "%s" exists in %s files:\n' "$SHEET" "$n" >&2
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    die "disambiguate with --file <substring>"
  fi
  SRC="$hits"
}

# The literal rg match is what makes this fast.  It is a SUBSTRING match on
# the raw line, so it needs no JSON parse; jq then sees ~1% of the stream.
prefilter() {
  resolve_file
  rg -N --fixed-strings "\"s\":\"$SHEET\"" "$SRC" 2>/dev/null
}

# Resolve the header row.  hdr_row is in STREAM coordinates (an index into the
# cell stream), NOT the A1 row -- those differ on any sheet with blank rows,
# which is the whole reason this script exists.
#
# It must be resolved per (FILE, SHEET), not per SHEET.  The same sheet name in
# a different workbook routinely has a DIFFERENT header row -- measured in the
# reference corpus: "Sheet1" is hdr_row=4 in the Freight Cost Recon workbook
# but hdr_row=5 in a scorecard, and "score calc" is hdr_row=1 in one file and
# absent (null) in two others.  Taking `head -1` of a sheet-only match silently
# adopts a foreign workbook's header and shifts every ordinal by one row.
resolve_hdr() {
  [ -n "$HDR" ] && { printf '%s' "$HDR"; return; }
  resolve_file
  local base h
  base=$(basename "$SRC" .prg.jsonl)
  h=$("$HERE/prg-join.sh" schema "$DIR" 2>/dev/null \
      | jq -r --arg s "$SHEET" --arg f "$base" \
          'select(.sheet==$s and (.file//"")==$f) | .hdr_row' 2>/dev/null \
      | head -1)
  [ -n "$h" ] && [ "$h" != "null" ] || h=0
  printf '%s' "$h"
}

# Group the flat (r,c) cell stream into rows and number them 1..N.  The ordinal
# -- not the row index, not the A1 row -- is what matches SQLite rowid.
group_rows() {
  jq -s --arg sheet "$SHEET" '
    group_by(.r)
    | to_entries
    | map({ sheet: $sheet,
            ord:   (.key + 1),
            r:     .value[0].r,
            cells: (.value | map({c, a, v}) | sort_by(.c)) })
    | .[]'
}

addressed_rows() {
  local hdr; hdr=$(resolve_hdr)
  prefilter \
    | jq -c --arg sheet "$SHEET" --argjson hdr "${hdr:-0}" \
        'select(.k=="cell" and .s==$sheet and .r > $hdr)
         | {r, c, a: (.a // null), v: (.v // null)}' \
    | group_rows
}

case "$SUB" in
  rows)
    if [ -n "$ORD" ]; then
      addressed_rows | jq -c --argjson o "$ORD" 'select(.ord == $o)'
    else
      addressed_rows | jq -c .
    fi
    ;;

  cell)
    [ -n "$ORD" ] || die '--ord is required for cell'
    [ -n "$COL" ] || die '--col is required for cell'
    out=$(addressed_rows \
      | jq -c --argjson o "$ORD" --argjson c "$COL" '
          select(.ord == $o)
          | .cells[] | select(.c == $c) as $x
          | {sheet: "", ord: $o, c: $c, a: $x.a, v: $x.v}' 2>/dev/null \
      | head -1)
    # Re-emit with the sheet filled in; keeping the jq above simple is
    # deliberate -- this path is the one a write-back caller hits per click.
    if [ -z "$out" ]; then
      printf 'no such cell: sheet=%s ord=%s col=%s\n' "$SHEET" "$ORD" "$COL" >&2
      exit 3
    fi
    printf '%s\n' "$out" | jq -c --arg s "$SHEET" '.sheet = $s'
    ;;

  check)
    [ -n "$DB" ]    || die '--db is required for check'
    [ -n "$TABLE" ] || die '--table is required for check'
    SQLITE="${SQLITE:-sqlite3}"
    command -v "$SQLITE" >/dev/null 2>&1 || SQLITE=/app/officepy/bin/sqlite3
    [ -x "$SQLITE" ] || command -v "$SQLITE" >/dev/null 2>&1 \
      || die "no sqlite3 available (set SQLITE=)"

    tmpa=$(mktemp); tmpb=$(mktemp)
    trap 'rm -f "$tmpa" "$tmpb" "$tmpb.rows"' EXIT

    # Recovered FIRST-COLUMN value per ordinal, from the sidecar.
    #
    # "First column" is the sheet's lowest populated c, NOT c==1.  Sheets that
    # start at column B are common (a title block or a spacer column occupies
    # A), e.g. [Freight Cost Recon / Sheet1] begins at c=2.  Hardcoding c==1
    # yields an empty string for every row there, which compares unequal to
    # every db value and reports a false MISMATCH on a table that is fine.
    addressed_rows > "$tmpb.rows"
    firstc=$(jq -s '[.[].cells[].c] | min // 1' < "$tmpb.rows")
    jq -r --argjson fc "$firstc" \
      '[(.ord|tostring), ((.cells[] | select(.c==$fc) | .v) // "")] | @tsv' \
      < "$tmpb.rows" > "$tmpa"
    # Actual column-1 value per rowid, from the db.
    "$SQLITE" "$DB" ".mode tabs" "select rowid, * from \"$TABLE\"" 2>/dev/null \
      | awk -F'\t' '{print $1"\t"$2}' > "$tmpb"

    ok=0; bad=0
    while IFS=$'\t' read -r ord val; do
      dbv=$(awk -F'\t' -v k="$ord" '$1==k{print $2; exit}' "$tmpb")
      [ -n "$dbv" ] || continue
      if [ "$dbv" = "$val" ]; then ok=$((ok+1)); else
        bad=$((bad+1))
        printf 'MISMATCH ord=%s sidecar=[%s] db=[%s]\n' "$ord" "$val" "$dbv" >&2
      fi
    done < "$tmpa"
    printf '{"sheet":"%s","table":"%s","ok":%d,"mismatch":%d}\n' \
      "$SHEET" "$TABLE" "$ok" "$bad"
    [ "$bad" -eq 0 ] || exit 1
    ;;
esac
