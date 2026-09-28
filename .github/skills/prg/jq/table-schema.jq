# table-schema.jq -- PER-SHEET SCHEMA with REAL header-row detection.
#
# WHAT IT EMITS, one object per (file, sheet):
#   {file, sheet, hdr_row, axis, cols, rows, cells, hdr:[{c,a?,v}], conf}
#
# WHY THIS EXISTS.  The single most expensive wrong assumption when querying a
# folder of spreadsheets is "the header is row 1".  Measured on the 88 schemas
# of the QBR corpus: r1=22, r2=27, r3=31, r4=3, r5=4, r6=1 -- only 25% are on
# row 1.  Reading r1 as the header on the other 75% does not fail loudly; it
# silently names every column after a title banner or a blank spacer, and every
# join built on those names is then wrong in a way no error message reveals.
#
# DETECTION (Context fact 1).  Among rows <= $maxhdr, the row with the most
# TEXT cells wins; ties go to the LOWEST row, because a title banner sits above
# the header and a data row sits below it, so the lowest of an equal-scoring
# set is the earliest plausible header.  A candidate must have >= $minw
# populated cells: a lone title cell in A1 outscores nothing and must not win.
#
# AXIS.  A schema is not always a row.  ~21% of the wider microcosmo corpus is
# KEY-VALUE FORMS whose schema runs DOWN COLUMN 1, and for those "which row is
# the header" has no true answer -- any row we return is a fabrication.  We do
# NOT re-implement silo-schema.jq's C-axis here; we DETECT the case and report
# axis:"col" with hdr_row:null, so a caller can route those sheets to the
# column ladder instead of quietly joining on invented column names.
#   :honesty: axis:"col" is a REFUSAL to guess, not a column schema.
#
# HDR_ROW VS HDR_A1ROW -- two different numbers, both true, never interchange.
# .r is the RENDERED row (position in the markdown table); .a is the REAL A1
# address.  They diverge whenever the sheet has blank rows, because blank rows
# are not emitted.  Measured on this corpus: 6350 of 7456 xlsx cells -- 85.2% --
# have .r != the row in .a.  So a header reported ONLY as hdr_row sends a human
# (or an OfficeJS write-back) to the wrong row on the large majority of cells.
#   hdr_row   -> index into THIS stream; use it to filter cells.
#   hdr_a1row -> the row a user sees in Excel; use it to cite or write back.
# hdr_a1row is ABSENT for non-xlsx, which have no A1 at all, so `has` is a
# real test rather than a guess.
#
# TYPE HANDLING.  .t is a DECLARATION, never a completeness guarantee.  bin2md
# leaves text untagged and tags numerics "n"/"date"; silo spells strings "s".
# So has("t") tests declaredness and the untagged case must be INFERRED from
# the value's shape -- which is why is_text works on both parsers unchanged.
#   :trap: `tonumber?` emits EMPTY, not null, on non-numeric input.  Without
#   the `// null` the whole cell vanishes from the count instead of being
#   counted as text, and every header score silently drops toward zero.
#
# USAGE -- jq -s is REQUIRED (the ladder needs the whole sheet in hand):
#   jq -s -c -f jq/table-schema.jq --arg file "$F" < "$F"
#   :trap: without -s you get "Cannot index string with ...".

# ---- helpers ----------------------------------------------------------------

# TEXT test, parser-agnostic.  See TYPE HANDLING above.
def is_text:
  if has("t") then (.t == "s")
  else ((.v | tostring | tonumber? // null) == null) end;

# A cell counts only if it carries a non-blank payload.  Empty cells are
# omitted by bin2md rather than sent as "", but csv/pdf can still yield
# whitespace-only values, and those are padding, not schema.
def populated:
  (.v != null) and ((.v | tostring | gsub("^\\s+|\\s+$"; "")) != "");

  ($ARGS.named.file    // "")   as $FILE
| ($ARGS.named.maxhdr  // "12" | tonumber) as $MAXHDR
| ($ARGS.named.minw    // "2"  | tonumber) as $MINW

# Step 0 -- the STRUCTURAL cell selector.  Works on bin2md and silo alike:
# bin2md cells carry k:"cell" while silo's carry no .k at all, so testing .k
# picks one parser and drops the other.  (r,c) is exact on both.
| map(select(.r != null and .c != null))
| map(select(populated))
| ( if length == 0 then empty else . end )

# 06/5.9: GROUP BY (sheet, tbl), MIRRORING catalog.c's T-H.10 loop.
#
# 07/T-H.5 made `tbl` table-grained and T-H.10 taught catalog.c to walk
# (sheet,tbl) runs, so the C path publishes a sheet's SECOND region.  This
# lens still grouped by sheet alone, so it published only the first -- two
# schema implementations disagreeing, which is the drift 3.6 removed for
# SQL identifiers by moving the derivation into one place.
# MEASURED on soc-11-1011.00_task-8825_v2, sheet 'Aurora' (tbl 8 and 9 in
# ONE file), read from join.prg.jsonl:
#     C path   Aurora hdr_row=3 rows=29  AND  Aurora rows=32
#     jq lens  Aurora hdr_row=3 rows=29       (the second was ABSENT)
#
# THE FIRST REGION KEEPS WHOLE-SHEET EXTENT, and copying that rule is the
# whole reason this is not a one-line group_by change.  catalog.c:506-527
# records why: hand the first region only its own run and its `rows` stops
# counting everything below the split -- "FAIL row count is 11, want 19 --
# ROWS WERE DROPPED", 1,271 tables changed, and the first T-H.10 attempt
# was REVERTED for exactly that.  A silently short table answers every
# query without erroring.  So the GROUP narrows (which is what makes the
# second region reachable) while the first region's ANALYSIS still spans
# the sheet.  Later regions analyse their own run -- the new information.
#
# `.tbl // 0` IS LOAD-BEARING: this lens reads bin2md AND silo streams, and
# silo cells carry no tbl.  The default collapses a tbl-less stream to one
# bucket per sheet, i.e. exactly the old behaviour, so silo is unchanged by
# construction rather than by luck.
| ( group_by(.s // "") | map({ sheet: (.[0].s // ""), maxr: ([ .[].r ] | max) })
    | INDEX(.sheet) )                             as $SHEETMAX
| group_by([(.s // ""), (.tbl // 0)])
| ( . as $runs
    | [ range(0; $runs | length) as $i
        | $runs[$i] as $g
        | ($g[0].s // "") as $sh
        | { g: $g,
            first: ($i == 0 or (($runs[$i-1][0].s // "") != $sh)) } ] )
| map(
    . as $run
  | $run.g                                        as $sc
  | ($sc[0].s // "")                              as $sheet
  | ( if $run.first then ($SHEETMAX[$sheet].maxr) else ([ $sc[].r ] | max) end )
                                                  as $maxr
  | ([ $sc[].c ] | max)                           as $maxc
  | ($sc | length)                                as $ncells

  # ---- candidate header rows, scored by TEXT count -------------------------
  | [ $sc
      | group_by(.r)[]
      | select(.[0].r <= $MAXHDR)
      | { r:  .[0].r,
          n:  length,
          ts: ( map(select(is_text)) | length ) } ]                as $cand
  | ( $cand | map(select(.n >= $MINW and .ts >= $MINW)) )           as $ok0

  # ---- LABEL-LIKENESS: text count ALONE is not enough -----------------------
  # On schedule sheets every data row is text too (names, "6:00-2:30", notes),
  # so a data row can out-score the header on raw text count.  Measured on
  # `SCHED_2025-06-09_v2_JM / WK 6-9`: the real header r2 scores 9 text cells
  # and the DATA row r6 scores 10, purely because it has one more populated
  # cell -- and r6 ("Luis O.") won, naming the table's columns after a person.
  #
  # A header's distinguishing property is not that it is text; it is that its
  # cells are LABELS: distinct from each other, and NOT repeated by the rows
  # below (a header says "DEPT" once; a data column says "WHSE" many times).
  # We score each candidate by how many of its values never reappear lower in
  # the sheet, which is the same type-transition evidence silo-schema.jq's R3
  # rung uses, expressed as a value test rather than a type test.
  # NB: candidate rows are used AS-IS ($ok0) -- there is deliberately no
  # per-candidate "label-likeness" enrichment here.  An earlier version
  # computed `uniq` (distinct values in the row) and `fresh` (labels that do
  # not recur below the row) for every candidate.  Both were DEAD: the header
  # is chosen by the categorical `.ts == .n` filter below, and the comment
  # there records that ranking by `fresh` was measured and REJECTED (it picked
  # a summary row).  Neither field was read by the ranking, by the emitted
  # rows, or by any caller.  Computing `fresh` re-scanned the whole sheet once
  # per candidate row (up to $MAXHDR times) -- accidentally quadratic in cell
  # count for a value nobody consumed.  Measured on the FY24 sidecar: removing
  # it took table-schema from 96,387 ms to 13,355 ms (7.2x) with byte-identical
  # output across all 12 files of the case folder.  Do not reintroduce a
  # per-candidate scan without a consumer AND a mutation test that kills it.
  | $ok0                                                             as $ok

  # ---- KEY-VALUE FORM detection -------------------------------------------
  # A form is NARROW and TALL with a text-dominated first column: the schema
  # runs down c1.  Requiring maxc <= 3 keeps this from stealing real tables,
  # which are wider than they are label-ish.
  | ( [ $sc[] | select(.c == 1) ] )                                as $c1
  | ( if ($c1 | length) == 0 then 0
      else (([ $c1[] | select(is_text) ] | length) / ($c1 | length))
      end )                                                        as $c1_text
  | ( ($maxc <= 3) and ($maxr >= 4) and ($c1_text >= 0.8)
      and (($ok | length) == 0
           or (($ok | map(.ts) | max) < 3)) )                       as $is_form

  # ---- CHOOSING THE HEADER -------------------------------------------------
  # Ranking by magnitude does not generalise.  Two measured counter-examples:
  #   * ranking by text count picked a DATA row ("Luis O.") that happened to
  #     have one more populated cell than the header;
  #   * ranking by fresh-label count picked a summary row ("SHORT | OK | -2")
  #     because nothing recurs beneath it.
  # The property that held on BOTH sheets is categorical rather than scalar:
  # a header is ENTIRELY labels and spans the table's full width, whereas data
  # rows either mix in numerics or are narrower.  That is a FILTER, not a
  # score -- on `Outbound/Sheet1` exactly one row qualifies, while on
  # `SCHED/WK 6-9` eight do.  Among qualifying rows the header is the FIRST,
  # because data follows its header.  We therefore filter, then take the
  # earliest, and only fall back to scoring when nothing is fully label-like.
  | ( $ok | map(select(.ts == .n and .n >= ($maxc * 0.8))) )        as $full
  | ( if ($full | length) > 0 then ($full | sort_by(.r) | .[0])
      elif ($ok | length) == 0 then null
      else ($ok | sort_by(-.ts, .r) | .[0]) end )                   as $best

  | if $is_form then
      # REFUSE to name a header row.  See AXIS above.
      { file: $FILE, sheet: $sheet, hdr_row: null, axis: "col",
        cols: $maxc, rows: $maxr, cells: $ncells, hdr: [], conf: 1 }
    elif $best == null then
      { file: $FILE, sheet: $sheet, hdr_row: null, axis: "none",
        cols: $maxc, rows: $maxr, cells: $ncells, hdr: [], conf: 0 }
    else
      ( [ $sc[] | select(.r == $best.r) ] | sort_by(.c) )            as $hrow
      # REAL sheet row, from .a -- see HDR_ROW VS HDR_A1ROW above.
    | ( [ $hrow[] | .a // empty
        | capture("(?<n>[0-9]+)$") | .n | tonumber ] | first )       as $a1row
    | { file: $FILE,
        sheet: $sheet,
        hdr_row: $best.r,
        hdr_a1row: $a1row,
        axis: "row",
        cols: ($hrow | length),
        # DATA rows only -- the header itself is not data, and a caller that
        # reports "N rows" meaning N-1 records overstates every total.
        rows: ($maxr - $best.r),
        cells: $ncells,
        hdr: [ $hrow[] | { c, a, v: (.v | tostring) } | with_entries(select(.value != null)) ],
        conf: 1 }
    end
  )
| .[]
