# bin2md-summary.jq -- derive the per-workbook roll-up row from a bin2md
# cell stream, replacing `silo --summary`.
#
# INPUT:  SLURPED bin2md --cells stream (or the .prg.jsonl sidecar, which is
#         the same bytes).  `jq -s -c -f bin2md-summary.jq --arg path F`
# OUTPUT: ONE object, the sheets.jsonl row shape:
#         {path,sheets,cells,formulas,used,charts,tables,af}
#
# WHY THIS EXISTS: sheets.jsonl was the last thing in index_folder.sh that
# needed silo.  bin2md emits no k=sheet meta row, which reads like a gap --
# it is not: every field is derivable from the rows already in the stream,
# so the roll-up costs a jq pass over a sidecar we write anyway, instead of
# a THIRD extractor process per workbook.
#
# VERIFIED 40/40 EXACT against `silo --summary` on all seven shared fields
# (microcosmo corpus, 31,724 cells).  Two traps are why it took three tries:
#
#  1. silo's `cells` EXCLUDES formula cells; `used` includes them.  The
#     bin2md stream is `used`.  So cells = used - formulas, NOT count(cell).
#     Getting this wrong mismatched 15/40 -- all of them off by exactly the
#     formula count.
#  2. sheets must be counted over ALL rows, not just k=="cell".  An EMPTY
#     sheet has zero cells but still appears on a block row, and a
#     cell-only count silently loses it (1/40: Bookings_Master_2024's
#     `Sheet1`).  Both counts are otherwise identical.
#
# NOT DERIVED: route/titles/kinds.  `route` is a silo-internal parser path,
# and titles/kinds measured 0/[] on 40/40 files.  All three have ZERO
# consumers in this repo (grep: no .route/.titles/.kinds reader) -- they are
# dropped deliberately rather than faked.
#
# `markup` -- THE HTML-MASQUERADE COUNTER, and the reason this lens emits a
# field silo has no analogue for.  This corpus plants .xls files that are
# really HTML export tables.  bin2md is multi-format, so it does not fail on
# them: it falls back to a CSV-ish reader and splits the raw MARKUP on
# commas, yielding cells whose values are literally `<tr><td colspan=11...`.
# That scores rc=0 with a healthy-looking cell count -- a false green that a
# zero-cell test cannot catch, because the cells are there; they are just
# not data.
#   MEASURED over all 23 legacy .xls in the corpus: contamination is
# BIMODAL -- 12 real files at 0%, 6 HTML files at 95-100%, nothing between.
# A caller can therefore threshold anywhere in the wide middle; the arm in
# index_folder.sh uses >=30%.  Files 11/14 (xlsx mislabeled .xls) and 17
# (plain text) score 0% and ARE genuine recoveries that silo cannot read --
# so this must NOT be a blanket "reject non-OLE" rule, or it would throw
# away 11,945 real cells to reject 1,221 junk ones.

# `junk` -- the THRESHOLDED verdict, so the ratio is computed once here
# rather than re-derived by every caller in shell (which cannot do float
# arithmetic without another fork).  The THRESHOLD is the caller's policy,
# passed as --arg markup_max; the default below is only a fallback so that
# existing callers that pass no such arg keep working unchanged.
([.[] | select(.k == "cell")]) as $c
| ([$c[] | select(has("f"))] | length) as $formulas
| ([$c[] | select((.v | type) == "string"
                  and (.v | test("</?(td|tr|table|html|body)\\b")))]
   | length) as $markup
| (($ARGS.named.markup_max // "0.30") | tonumber) as $max
| {path:     $path,
   markup:   $markup,
   junk:     (($c | length) > 0 and (($markup / ($c | length)) >= $max)),
   sheets:   ([.[] | .s // empty] | unique | length),
   cells:    (($c | length) - $formulas),
   formulas: $formulas,
   used:     ($c | length),
   charts:   ([.[] | select(.k == "chart")] | length),
   tables:   ([.[] | select(.k == "table")] | length),
   af:       ([.[] | select(.k == "af")]    | length)}
