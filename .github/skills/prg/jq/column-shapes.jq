# column-shapes.jq -- the VALUE SHAPE histogram of each column.
#
# Consumes jq/column-values.jq output (one {file,sheet,col,hdr,n,n_all,vals}
# object per column) and replaces the value domain with a histogram of
# NORMALISED shapes:  every run of digits -> "9", every run of letters -> "A".
#
# WHY.  Two columns whose dominant shapes differ CANNOT join, and that is
# decided from a few hundred sampled cells instead of a full scan or a trial
# query.  The motivating case on the freight corpus:
#     cass_paid_detail.SHIPMENT_REF   "4887"        -> 9
#     MG_shipment_extract.Shipment Nbr "SH-0004651" -> A-9
# A join across those is syntactically perfect, names two real columns, runs
# without error, and returns ZERO ROWS -- which is indistinguishable from "no
# matches exist", so a model has nothing to self-correct from.  The shape
# verdict is one line long and unambiguous, which is what makes it cheap
# enough to put in a prompt.
#
# THIS IS VALUE-LEVEL SCHEMA LINKING, the failure class that actually
# dominates: ~37-42% of text-to-SQL errors are schema linking, while
# un-executable SQL is <=3% (fix.archive/text2sql-methodology.md sections 3.2
# and 4).  A preflight that only proves SQL RUNS is aimed at the 3%.
#
# USAGE (jq -s, over the whole colvals stream)
#   prg-join.sh colvals DIR | jq -s -c -f jq/column-shapes.jq --arg sample 400
#
# OUTPUT, one object per column:
#   {file, sheet, col, hdr, sql, n, sampled,
#    shapes:[{s:"A-9", k:399, pct:100}, ...],   -- descending, capped
#    top:"A-9"}
#
# `sql` is the identifier the DDL will actually carry.  It is NOT the header
# and it is NOT a naive slug -- see sql_ident below.

  ($ARGS.named.sample // "400" | tonumber)  as $SAMPLE
| ($ARGS.named.top    // "5"   | tonumber)  as $TOP

# THE SQL IDENTIFIER IS NOT THE HEADER, AND NOT A NAIVE SLUG.
# This mirrors mangle() in src/emitsql.c EXACTLY.  The obvious recipe
#     (.name|ascii_downcase|gsub("[^a-z0-9]+";"_"))
# is WRONG on 19 of the 109 headers in the freight corpus (17%): it keeps
# leading/trailing underscores that mangle() strips, and it leaves a
# leading digit that mangle() prefixes with "_".
#     "Fuel %"        naive fuel_       real fuel
#     "$/CWT"         naive _cwt        real cwt
#     "2023 avg $/cwt" naive 2023_...   real _2023_avg_cwt
# Getting this wrong returns EMPTY rather than an error -- which reads as
# "no data" instead of "wrong key", the same failure mode as the zero-row
# join, one level up.  That is why it is duplicated here rather than
# approximated.
#
# NOT MODELLED: uniq()'s _2/_3 disambiguation, which cannot be computed from
# one column in isolation (it depends on the other columns of the same
# table).  A column whose `sql` collides with a sibling therefore carries the
# UNDISAMBIGUATED name here.  Callers that need the true post-uniq identifier
# must read it from insert.prg.sql.  See plan item 3.6.
| def sql_ident:
    ( ascii_downcase
    | gsub("[^a-z0-9]+"; "_")
    | sub("_+$"; "")
    | sub("^_+"; "") ) as $k
  | if   ($k | length) == 0      then "c"
    elif ($k | test("^[0-9]"))   then "_" + $k
    else $k end;

# digits -> 9, letters -> A.  Applied in that order so that a letter run
# introduced by the digit rule cannot be re-collapsed.
def shape_of:
    tostring
  | gsub("[0-9]+"; "9")
  | gsub("[A-Za-z]+"; "A");

  map(
    . as $c
  | ( $c.vals // [] )                       as $all
  # Sample from the DISTINCT values (column-values.jq already uniqued them).
  # Sampling distinct rather than raw is deliberate: a column that is 99% one
  # repeated value would otherwise report a single shape with 99% confidence
  # and hide the minority shape that actually breaks the join.
  | ( $all[0:$SAMPLE] )                     as $s
  | ( $s | map(shape_of) )                  as $shapes
  | ( $shapes | length )                    as $ns
  | { file:    $c.file,
      sheet:   $c.sheet,
      col:     $c.col,
      hdr:     $c.hdr,
      sql:     ($c.hdr | sql_ident),
      n:       $c.n,
      sampled: $ns,
      shapes:
        ( $shapes
        | group_by(.)
        | map({ s: .[0], k: length })
        | sort_by(-.k)
        | .[0:$TOP]
        | map(. + { pct: (if $ns == 0 then 0
                          else ((.k * 1000 / $ns) | round / 10) end) }) ),
      top: ( $shapes | group_by(.) | map({s: .[0], k: length})
           | sort_by(-.k) | (.[0].s // null) ) }
  )
| .[]
