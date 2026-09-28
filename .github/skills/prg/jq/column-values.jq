# column-values.jq -- the VALUE DOMAIN of each column, keyed to its header.
#
# Feeds jq/join-candidates.jq.  One object per (file, sheet, column):
#   {file, sheet, col, hdr, n, vals:[...]}
#
# Only sheets whose schema is axis:"row" have columns in this sense; KEY-VALUE
# FORMS (axis:"col") are skipped, because their "columns" are a label list and
# a value list, not a domain that can be join-tested.
#
# ROWS BELOW THE HEADER ONLY.  Cells at or above hdr_row are title banners and
# the header itself; including them injects the header STRING into the value
# domain, which then "matches" the other table's header and manufactures a
# join that does not exist.
#
# USAGE (jq -s, one file at a time -- shard by FILE)
#   jq -s -c -f jq/column-values.jq --arg file F --argjson schema '<schemas>'

  ($ARGS.named.file // "")                        as $FILE
| ($ARGS.named.maxvals // "5000" | tonumber)      as $MAXVALS
| ($ARGS.named.schema | fromjson)                 as $SCHEMA

| def norm_blank: (.v != null)
    and ((.v | tostring | gsub("^\\s+|\\s+$"; "")) != "");

  # header row per sheet, and the header label per (sheet,col)
  ( $SCHEMA | map(select(.axis == "row")) )       as $rowsheets
| ( $rowsheets | map({key: (.sheet // ""), value: .hdr_row}) | from_entries ) as $HDRROW
| ( $rowsheets
    | map( (.sheet // "") as $s | (.hdr // [])
         | map({key: ($s + "\u0000" + (.c | tostring)), value: .v}) )
    | add // [] | from_entries )                  as $HDRLBL

| map(select(.r != null and .c != null))
| map(select(norm_blank))
| map(select( ($HDRROW[(.s // "")] != null) and (.r > $HDRROW[(.s // "")]) ))
| ( if length == 0 then empty else . end )

| group_by([(.s // ""), .c])
| map(
    ( .[0].s // "" )                              as $sheet
  | ( .[0].c )                                    as $col
  | ( [ .[] | .v | tostring ] )                   as $allv
  | ( $allv | unique )                            as $vals
  | { file: $FILE,
      sheet: $sheet,
      col: $col,
      hdr: ( $HDRLBL[($sheet + "\u0000" + ($col | tostring))] // ("c" + ($col | tostring)) ),
      n: ($vals | length),
      # n_all is the POPULATED cell count, n the DISTINCT count.  n/n_all is
      # uniqueness, which is what makes a column a KEY -- the `pk` edge rule
      # needs it.  Without n_all a column that repeats every value looks
      # identical to one that never does.
      n_all: ($allv | length),
      vals: ($vals[0:$MAXVALS]) }
  )
| .[]
