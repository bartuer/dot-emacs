# select.jq -- SQL SELECT over silo's cell stream.  The "row" recipe.
#
# WHY THIS EXISTS.  `--dump-json` emits CELLS, not ROWS: one object per cell,
# in sheet/row/column order, with NO row container anywhere in the stream.  A
# WHERE clause spanning two columns ("orderDate in range AND freight in range")
# cannot be written as a filter over single records -- the two predicates live
# in two DIFFERENT records that share only `.r`.  The row is implicit; this
# lens makes it explicit.
#
# THE SHAPE, in three moves:
#   1. GROUP   cells by row          -- reconstruct the row   (FROM)
#   2. WHERE   predicates over it    -- all columns in ONE place
#   3. PROJECT the wanted columns    -- SELECT
# That ORDER is the recipe.  Filtering cells BEFORE grouping is the tempting
# one-liner and it is WRONG: it throws away the cells the other predicate needs
# and the projected column too.  Filter ROWS, not cells.
#
# HEADER-DRIVEN.  Column letters are a layout accident; header text is the
# schema.  The header row is read into a column->name map, so predicates are
# written against `orderDate`, not `C` -- insert a column and the query still
# works.  This is why a spreadsheet is queryable at all: row 1 IS the schema.
#
# DATE COMPARISON IS LEXICAL, and that is SOUND, not a shortcut: silo renders
# every date as ISO-8601 ("2013-07-04T00:00:00", tag "d"), and ISO-8601 is
# built so lexical order == chronological order.  We compare the DATE PREFIX
# (first 10 chars) so both bounds are INCLUSIVE and a time-of-day component
# cannot silently drop an end-date row.
#
# !! NOT DECOMPOSABLE -- do NOT run under `parallel --pipe`.  A row's cells are
# adjacent in the stream, so a block boundary can CUT A ROW IN HALF, yielding
# two partial rows that each fail the WHERE and vanish -- silently, with a
# plausible smaller count.  This lens has NO merge partner, which per merge.jq
# forbids --pipe.  Shard by FILE instead: rows never span workbooks.
# See :map-reduce-recipe: / :correctness-contract: in .github/REPL/253.*.org.txt
#
# USAGE  (jq -s, because grouping needs the whole sheet in hand)
#   jq -s -f select.jq \
#      --arg  sheet Sheet1 --argjson hdr 1 \
#      --arg  d_col orderDate --arg d_from 2014-01-01 --arg d_to 2014-03-31 \
#      --arg  n_col freight   --argjson n_min 100 --argjson n_max 500 \
#      --arg  select 'orderID,customerName' \
#      cells.jsonl
# Every predicate is OPTIONAL: omit d_col to drop the date clause, omit
# select to get the whole row.  No knob set == SELECT * (the row dump).
#
# Optionality is spelled `$ARGS.named.x // default`, NOT `$x // default`:
# a bare `$x` for an unpassed --arg is a jq COMPILE error, not a null, so
# `$x // ""` does not make an argument optional.  $ARGS.named is the only
# accessor that actually degrades.
#
# COST (measured, not estimated -- see the bench block in 253.*.org.txt):
#   13,275-cell sheet : 0.14 s query;  0.15 s END-TO-END from .xlsx via silo.
#   1.77 M cells / 313 MB : 23 s, PEAK RSS ~1,978 MB  (~6.3x the input).
# `jq -s` slurps the whole sheet, so MEMORY is the binding constraint, not
# time.  Past ~1 M cells prefer sharding BY FILE across cores; a single
# multi-GB sheet is where this lens stops and SQLite starts.

  ($ARGS.named.sheet  // "") as $SH
| ($ARGS.named.hdr    //  1) as $HDR
# CELL-FIDELITY MODE (--argjson cells 1).  Default 0 keeps the pinned
# {r,a,row} shape byte-for-byte for every existing caller.
#
# WHY A MODE AND NOT A SECOND LENS.  `row` is {name: value}: it keeps ONE
# scalar per column, so the per-cell `.a` and `.f` are gone by the time
# PROJECT runs.  That is right for a human reading a row and WRONG for a
# join that must write back to the sheet -- the address is the write target
# and `.f` is the live formula.  Losing them is invisible in the rendered
# markdown, which is exactly why it needs a switch rather than vigilance.
#
# THIS BRANCH WAS DROPPED ONCE AND THE LOSS WAS SILENT.  The sync in 4dd9f28
# landed a copy without it; jq IGNORES an unknown --argjson, so `prg-join.sh
# run` kept passing `--argjson cells 1`, kept getting the {r,a,row} shape,
# and died downstream in join-run.jq with "Cannot iterate over null" at
# `.cells[]` -- a message that points at the CONSUMER, not at the arg that
# never took effect.  bench/assert-join-run.sh now pins the contract.
| (($ARGS.named.cells // 0) == 1) as $CELLS
| ($ARGS.named.select // "") as $SEL
| ($ARGS.named.d_col  // "") as $DC
| ($ARGS.named.n_col  // "") as $NC
| ($ARGS.named.d_from // "") as $DF
| ($ARGS.named.d_to   // "") as $DT
| ($ARGS.named.n_min  // null) as $NLO
| ($ARGS.named.n_max  // null) as $NHI

# 0. scope to one sheet -- a workbook may hold several unrelated tables.
#    The cell selector is STRUCTURAL (`has .r and .c`), not tag-based, because
#    the two parsers tag rows with OPPOSITE polarity and prg must read both:
#      silo   -- meta rows carry `.k`, cell rows carry NO `.k`   -> cells are k==null
#      bin2md -- cell rows carry `k:"cell"`, and the rows with NO `.k` are the
#                MARKDOWN blocks (t:"r"/"h", already-rendered `| a | b |` lines)
#    So `select(.k == null)` is right for silo and CATASTROPHIC for bin2md:
#    MEASURED on one workbook it selects 42,464 markdown rows instead of the
#    551,402 cells.  Those rows have no `.r`/`.c`, so step 2 collapses them into
#    a PHANTOM `r:null` bucket -- the same failure this comment has always
#    warned about, with the polarity flipped.  (Before this fix, that bucket
#    reached `from_entries` as a null key and raised
#    "Cannot use null (null) as object key", rc=5.)
#    `.r != null and .c != null` is exact on BOTH: 551402 == 551402 on the same
#    workbook, admitting only k=="cell" from bin2md and excluding all 7 of
#    silo's meta rows from its mixed --dump-meta-json + --dump-json stream.
#    Keep it structural -- a tag test would have to change again for the next
#    parser, and silo stays the differential oracle for the bin2md migration.
| [ .[] | select(.r != null and .c != null) | select($SH == "" or .s == $SH) ] as $cells

# 1. header row -> {"<col number>": "<name>"}.  Schema, read from the data.
| ( [ $cells[]
      | select(.r == $HDR and .v != null)
      | {key: (.c|tostring), value: (.v|tostring)} ] | from_entries )  as $name

# 2. GROUP into rows.  group_by keeps .r ascending, so output is in
#    spreadsheet order with no second sort.
| [ $cells[] | select(.r != $HDR) ]
| group_by(.r)
| map(
    { r: .[0].r,
      # A1 ADDRESS, carried when the parser supplies one.  An earlier version of
      # this comment claimed "bin2md drops `.a` BY DESIGN"; that is FALSIFIED --
      # MEASURED 35,287 of 35,287 xlsx cells carry `.a` under bin2md.  It is
      # emitted per-FORMAT, not dropped: xlsx cells have it, and the formats with
      # no such address (pdf 0/78, pptx 0/274) correctly omit it, so `has("a")`
      # is a real test rather than a parser test.  Carrying it is not cosmetic:
      # under bin2md `.r` is the RENDERED position and `.a` is the sheet's REAL
      # address, and they DIVERGE (22 cells in one measured column) because
      # blank rows are not emitted.  `r` alone therefore cannot navigate you back
      # to the cell -- which is exactly what step 4 claims the address is for.
      # Additive: absent for the formats that have no address, so the pinned
      # {r,row} shape is unchanged for every existing caller.
      a: .[0].a,
      # the row as a NAMED object; an unnamed column falls back to a synthetic
      # "c<N>" label so nothing is silently lost.  This is the COLUMN key, and
      # `.a` is deliberately NOT reused for it: a missing key is not harmless
      # here -- a null key raises "Cannot use null as object key", and reusing a
      # bare `.c` integer would collide with a header literally named "3", merging
      # two columns inside from_entries and losing data with no error.
      # With a correct numeric --argjson hdr this fallback never fires (every
      # column resolves through $name); it is the safety net for the headerless
      # tables that are exactly bin2md's reason to exist.
      row: ( [ .[] | {key: ($name[(.c|tostring)] // ("c" + (.c|tostring))), value: .v} ] | from_entries )
    }
    # The UNCOLLAPSED cells, keyed by the same column name `row` uses, so
    # PROJECT can select against either view.  Carried ONLY in cell mode:
    # an unconditional key would change the pinned shape for every caller.
    + ( if $CELLS
        then { cells: [ .[]
                 | { col: ($name[(.c|tostring)] // ("c" + (.c|tostring))),
                     c: .c, a: .a, v: .v, f: .f, t: .t, s: .s } ] }
        else {} end )
  )

# 3. WHERE -- every predicate reads the SAME reconstructed row.
| map(select(
      ( $DC == "" or
        ( (.row[$DC] // null) as $d
          | ($d != null)
            and ( ($DF == "") or (($d|tostring)[0:10] >= $DF) )
            and ( ($DT == "") or (($d|tostring)[0:10] <= $DT) ) ) )
  and ( $NC == "" or
        # COERCION IS THE FIX HERE, NOT A MITIGATION -- and it must STAY.
        # bin2md --cells emits every .v as a STRING even when the xlsx declared
        # it numeric (MEASURED 35,287/35,287 strings), so a bare
        # (type=="number") test matches NOTHING under that parser and the filter
        # silently returns 0 rows with rc=0.
        # The old note said to "revert to a declaration-respecting test once
        # bin2md tags declared types".  bin2md now DOES tag (7,628 `n` + 193
        # `date` over the same 40 sidecars) -- but reverting would be a BUG:
        # 2,562 xlsx cells whose value parses as a number carry NO `t` at all,
        # so gating on `t=="n"` would silently drop every one of them from a
        # numeric range filter.  `t` is a DECLARATION, never a completeness
        # guarantee, and bin2md's own schema says keys are ABSENT rather than
        # null when they do not apply.  Coercion covers declared and undeclared
        # numerics alike, and stays correct for silo's genuinely-numeric .v.
        # Coerce HERE ONLY: the predicate is the one place that needs a number.
        # Do NOT coerce in step 2 -- that would rewrite the PROJECTED values and
        # change what the user is shown.  `tonumber?` is the safe form: it
        # declines rather than raises on "2024-10" and other non-numeric text,
        # so those keep failing the filter as they should.
        # :trap: a bin2md FORMULA cell puts the formula TEXT in .v ("=K4*31.8",
        # with the body also in .f) where silo puts null.  `tonumber?` declines
        # on it, so such a cell fails a numeric predicate under BOTH parsers --
        # same verdict, different reason.  Do not "rescue" it by reading .f.
        ( (.row[$NC] // null) as $n
          | ($n | tonumber? // null) as $num
          | ($num != null)
            and ( ($NLO == null) or ($num >= $NLO) )
            and ( ($NHI == null) or ($num <= $NHI) ) ) )
  ))

# 4. PROJECT.  Keep the row ADDRESS: a result you cannot navigate back to in
#    the workbook is a dead end -- the address IS the join key.  Under bin2md
#    `.r` is the RENDERED row and `.a` the real one, so `a` is what actually
#    navigates; it rides along and is absent for address-less formats.
| map(
    .row as $R                       # bind FIRST: inside `reduce`, `.` is the
    | .cells as $C                   # ACCUMULATOR, so `.row` there reads the
    | ( if $SEL == "" then null      # empty seed and every value comes back
        else ($SEL | split(",") | map(sub("^ +";"") | sub(" +$";""))) end ) as $KEYS
    | { r: .r, a: .a,                # null -- a silent, plausible-looking
        row: ( if $KEYS == null then $R
               else reduce $KEYS[] as $k ({}; .[$k] = ($R[$k] // null))
               end )
      }
      # Cell mode projects the CELL LIST through the same key filter, so a
      # narrowed SELECT narrows both views identically and they cannot
      # disagree about what the row contains.
      + ( if $CELLS
          then { cells: ( if $KEYS == null then $C
                          else [ $C[] | select(.col as $c | $KEYS | index($c)) ]
                          end ) }
          else {} end )
  )
| .[]
