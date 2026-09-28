# join-run.jq -- walk a VERIFIED DAG and emit ONE bin2md-shaped cell stream.
#
# INPUT (slurped): one object per node, in topological order:
#   {node, lcol, rcol, rows: [ <select.jq --argjson cells 1 output> ]}
# The FIRST node is the root and carries no lcol/rcol; each later node joins
# its `rcol` against the accumulated row's `lcol`.
#
# WHY THE OUTPUT IS A CELL STREAM AND NOT A TABLE OBJECT.  (frontier A, item
# 3.1.)  A cell stream is what bin2md already emits, so everything downstream
# -- select.jq, cells-md.jq, OfficeJS Range.values -- consumes the join result
# with NO adapter and no second code path.  A {columns, rows} table would need
# a converter at every one of those boundaries, and each converter is a place
# for the sheet and the prose to disagree.
#
# WHAT IS CARRIED, AND WHY IT IS NOT COSMETIC (item 3.1 :trap:)
#   a  the SOURCE A1 address -- the write-back target.  `r`/`c` below are the
#      RESULT position, which navigates you nowhere in the original workbook.
#      Dropping `a` yields a result you cannot act on, and the markdown looks
#      exactly the same, so nothing catches it.
#   f  the live formula body.  Under bin2md `.v` of a formula cell is the
#      formula TEXT and there is no cached value anywhere (measured: 0 formula
#      cells carry a computed .v).  `f` is therefore the ONLY thing that can
#      reconstitute a live cell via Range.formulas; lose it and the cell
#      becomes an inert string that reads as correct.
#   src  file::sheet of origin -- with N tables joined, `a` alone is ambiguous
#      ("B4" in WHICH workbook?), so the address is only actionable in pairs.
#
# JOIN SEMANTICS: INNER, on stringified values.  Inner because a LEFT join
# would emit rows with null columns from the right table, and a null in a
# rendered markdown cell is indistinguishable from a genuinely blank cell --
# the reader cannot tell "no match" from "empty".  Membership is tested on
# `tostring` because the two parsers disagree about numeric typing (bin2md
# emits every .v as a string; see the COERCION note in select.jq), so a
# type-sensitive == silently matches nothing.

  ( $ARGS.named.maxrows // 100000 | tonumber? // 100000 ) as $MAXROWS

# Accumulate: fold each node's rows into the running result.
# A "wide row" is [cell, ...]; cells keep their own provenance, so a join
# never has to re-derive where a value came from.
| ( .[0] ) as $root
| ( .[1:] ) as $rest
| [ $root.rows[] | [ .cells[] | . + {src: $root.node} ] ] as $seed

| reduce $rest[] as $n
    ( $seed;
      . as $acc
      # Index the right table by its join column ONCE.  A nested scan is
      # O(L*R) and this is the only step that grows with the corpus.
      | ( reduce $n.rows[] as $r
            ({}; ( [ $r.cells[] | select(.col == $n.rcol) | .v ] | first ) as $k
               | if $k == null then .
                 else .[$k|tostring] += [ [ $r.cells[] | . + {src: $n.node} ] ]
                 end ) ) as $idx
      | [ $acc[]
          | . as $lrow
          | ( [ $lrow[] | select(.col == $n.lcol) | .v ] | first ) as $lk
          | if $lk == null then empty
            else ( $idx[$lk|tostring] // [] )[] as $rrow
                 | $lrow + $rrow
            end ]
    )

# TRUNCATION MUST BE SIGNALLED, NOT SILENT.  `.[0:$MAXROWS]` alone drops rows
# with rc=0 and nothing on stderr, so a capped result is indistinguishable
# from a complete one.  MEASURED: an ACCEPTED edge (Pallets<->Pallets, 17
# shared keys, contain=1) truly yields 379,592 rows; `run` emitted exactly
# 100001 and said nothing, losing 74% of the answer while every visible
# signal stayed green.  An analyst summing that column gets a confidently
# wrong total, which is worse than an error.  `stderr` passes its input
# through, so `| empty` after it keeps the warning OFF stdout -- the cell
# stream must stay machine-readable.
| ( . as $all
    | if ($all | length) > $MAXROWS
      then ( ( "join-run: TRUNCATED to \($MAXROWS) of \($all|length) joined rows"
               + " -- raise --maxrows or narrow the edge; this result is PARTIAL" )
             | stderr | empty ), $all
      else $all end )

| .[0:$MAXROWS] as $rows

# Column order is first-seen across the joined rows: it follows the DAG walk,
# so the leftmost columns are the root table's.  Deterministic without a sort.
# NOT `unique` -- that sorts, which would reorder columns by name and lose the
# DAG walk order; the reduce below preserves first-seen.
#   Carries {seen, order}: `seen` is an OBJECT used as a set, so membership is
#   a hash lookup rather than a linear scan of `order` (there is no index/2 in
#   jq, and re-scanning the list would be quadratic in column count).
| ( reduce $rows[][] as $c
      ({seen: {}, order: []};
       ($c.src + "\u0000" + $c.col) as $k
       | if .seen[$k] then . else .seen[$k] = true | .order += [$k] end)
    | .order ) as $cols
| ( $cols | to_entries | map({key: .value, value: (.key + 1)}) | from_entries ) as $colno

# The two emit blocks below are ONE comma-expression, parenthesised.  After a
# `... as $x |` binding jq expects a single expression, so a bare top-level
# `,` here is a syntax error.
| (
# 1. HEADER ROW.  Emitted as ordinary cells so the stream needs no separate
#    header channel -- consumers already know row 1 is the header (hdr=1).
  ( $cols | to_entries[]
    | { k: "cell", r: 1, c: (.key + 1),
        v: (.value | split("\u0000") | .[1]),
        src: (.value | split("\u0000") | .[0]) } )

# 2. DATA ROWS.  `r` is the RESULT position; `a` stays the SOURCE address.
, ( $rows | to_entries[]

    | (.key + 2) as $rn
    | .value[]
    | ($colno[.src + "\u0000" + .col]) as $cn
    | if $cn == null then empty
      else { k: "cell", r: $rn, c: $cn, v: .v }
           + (if .a  != null then {a:  .a}  else {} end)
           + (if .f  != null then {f:  .f}  else {} end)
           + (if .t  != null then {t:  .t}  else {} end)
           + {src: .src}
      end )
  )
