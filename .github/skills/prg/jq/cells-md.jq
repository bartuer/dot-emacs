# cells-md.jq -- render ANY bin2md-shaped cell stream as a markdown table.
#
# Input (slurped): [ {k:"cell", r, c, v, a?, f?, t?, src?}, ... ]
# Output: markdown text, one line per table row.
#
# This is a VIEW, never a second artifact.  It derives entirely from the
# stream `run` already emits, so the sheet and the prose cannot disagree.
# It therefore takes the stream as given: it does NOT re-read a sidecar,
# re-join, or re-derive a header.  Anything it cannot show (a formula's live
# -ness, the source address) is LOST IN THE RENDER ONLY -- the stream still
# carries it.  See the {r,c,v} red control in plan item 3.1.
#
# Row 1 is the header, because `run` emits it as ordinary cells (there is no
# separate header channel).  A stream whose lowest r is not 1 is rendered as
# data with a synthetic positional header, rather than silently promoting an
# arbitrary data row to a header -- inventing a header is the exact failure
# the schema lens spends Phase 1 avoiding.
#
# --arg formulas mark|text    how to render a cell that carries .f
#     mark (default) -- render the source wrapped in backticks: `=SUM(B7:B11)`.
#                       The reader can SEE it is an uncomputed formula and not
#                       mistake it for a total.
#     text           -- the bare source, `=SUM(B7:B11)`, for diffing against
#                       another renderer or feeding a machine.
#
# There is deliberately NO mode that prints a computed number.  MEASURED
# (item 3.3): every one of the 3133 formula-bearing xlsx files in
# crossapp-cases-1224 carries <calcPr fullCalcOnLoad="1"/> and stores its
# formula cells as <f>SUM(B7:B11)</f><v></v> -- an EMPTY cached value.  The
# numbers are not in the files, so bin2md is not withholding them and no
# parser change can surface them.  Evaluating instead is a separate, opted-out
# decision (plan 3.3 option B); a wrong total that LOOKS right is worse than a
# formula the reader can see.

def esc:
  # A literal '|' would split a cell into two columns and shift every column
  # after it: a silent, plausible-looking corruption.  Newlines do the same to
  # rows.  Both are escaped, never dropped.
  tostring
  | gsub("\\\\"; "\\\\")
  | gsub("\\|"; "\\|")
  | gsub("\r?\n"; "<br>");

def cell_text($mode):
  if .v == null then ""
  # Gate on `.f`, NOT on a leading "=" in .v: a genuine TEXT cell can start
  # with "=" (a note like "=see tab 2"), and marking that as a formula would
  # be a lie in the other direction.  `.f` is the parser's own statement.
  elif (.f != null) and $mode == "mark" then "`" + (.v | esc) + "`"
  else (.v | esc)
  end;

  ( $ARGS.named.formulas // "mark" ) as $FMODE
| ( if ($FMODE | IN("mark", "text")) then . else
      ("cells-md: --formulas must be mark|text (got \"\($FMODE)\"); "
       + "there is no value mode -- xlsx stores no cached result, see 3.3")
      | error
    end )

| map(select(.k == "cell"))
| if length == 0 then "" else

  ( map(.r) | min ) as $minr
| ( map(.c) | max ) as $maxc

  # Group by row ONCE, then index each row by column, so a missing cell is an
  # empty string rather than a shifted column.  A sparse stream is normal:
  # `run` emits nothing for a column a node does not have.
| ( group_by(.r) | map({ r: .[0].r,
                         cells: (map({key: (.c|tostring), value: .}) | from_entries) }) )
  as $rows

| ( [ range(1; $maxc + 1) ] ) as $cols

| ( if $minr == 1
    then ( $rows[0].cells as $h
           | [ $cols[] | ($h[(.|tostring)] // {}) | cell_text($FMODE) ] )
    else ( [ $cols[] | "c" + (.|tostring) ] )
    end ) as $hdr

| ( if $minr == 1 then $rows[1:] else $rows end ) as $body

| ( [ "| " + ($hdr | join(" | ")) + " |",
      "| " + ([ $cols[] | "---" ] | join(" | ")) + " |" ]
    + [ $body[]
        | .cells as $rc
        | "| " + ([ $cols[] | ($rc[(.|tostring)] // {}) | cell_text($FMODE) ]
                  | join(" | ")) + " |" ]
  ) | join("\n")

  end
