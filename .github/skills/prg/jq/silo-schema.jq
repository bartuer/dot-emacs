# silo-schema.jq -- TABLE DISCOVERY over silo's mixed meta+cell stream.
#
# WHAT IT EMITS, one object per detected table, rung-agnostic by design so the
# bench can score every rung through one code path:
#   {file, sheet, hdr_row, c_lo, c_hi, r_lo, r_hi, ref, rung, conf}
#
# THE LADDER -- cheapest signal first, stop at the first rung that fires.
#   R1 frozen band  .fr on the sheet meta => author froze rows 1..fr as header
#   R2 declared     table/af .ref         => the rectangle, verbatim
#   R3 shape        a top row that LOOKS like a header, confirmed by a TYPE
#                   TRANSITION into the rows below it
#   R4 multi-hit    several header runs in ONE row => tables side by side
#   -- COLUMN AXIS (a schema is not always a row) --
#   C1 frozen cols  .fc on the sheet meta => author froze cols 1..fc as label
#   C3 shape        a left column that LOOKS like a label column, confirmed by
#                   a TYPE TRANSITION into the columns to its right
#
# WHY A SECOND AXIS.  Measured on 600 random microcosmo files: only 17% are
# row-tables with the header on r1, 29% are row-tables with the header BELOW
# r1 (R3 covers those), and 21% are KEY-VALUE FORMS whose schema runs DOWN
# COLUMN 1 -- `Insured` / `Loss Date` / `Odometer` in c1, values in c2.  A
# row-only ladder reads that fifth of the corpus as noise.  The cell stream
# itself is orientation-agnostic (r and c are symmetric), so this costs a
# mirrored rung, not a new format.
#   :caveat: .fc is present on only 4% of files vs .fr's 21% -- for key-value
#   forms the author's own hint is usually ABSENT, so C3 carries the load.
#   :order: the C rungs fire LAST, only when every row rung came up empty.
#   A sheet that is a row-table must never be re-read as a form.
#
# !! CIRCULARITY WARNING -- READ BEFORE QUOTING ANY R2 NUMBER.
# The gold positives were themselves DERIVED from `table`/`af` declarations.
# R2 therefore re-reads the oracle's own source: its recall is a tautology,
# not a measurement, and scoring it "high" says nothing about detection.
# R3/R4 are the only rungs that can be honestly scored against declared gold.
# The bench prints R2 separately and labels it, so the headline is not
# inflated by a rung that cannot fail.
#
# CONF is a TIER, NOT A PROBABILITY (silo's own schema row says so):
#   2 = declared by the author (R1 frozen is an author act too, but it names
#       only a BAND, not a rectangle, so it is demoted to 1)
#   1 = inferred
#
# INPUT.  ONE mixed stream: `silo --dump-meta-json F; silo --dump-json F`.
# meta rows HAVE .k; cell rows do NOT.  Per silo's schema row, ANY row-rebuild
# MUST filter on .k first or the meta rows collapse into a phantom r:null row
# that poisons every group_by(.r).  We filter first, every time.
#
# USAGE (jq -s -- the ladder needs the whole sheet in hand)
#   { silo --dump-meta-json F; silo --dump-json F; } \
#     | jq -s -c -f silo-schema.jq --arg file F
#
# NOT DECOMPOSABLE -- same reason as select.jq: a --pipe block boundary can cut
# a sheet in half, and half a sheet yields a confidently WRONG rectangle rather
# than a visible error.  Shard by FILE.

# ---- A1 helpers (top-level defs) --------------------------------------------
def colnum: ascii_upcase | explode | reduce .[] as $ch (0; . * 26 + $ch - 64);
def colname:
  [ recurse( if . > 0 then ((. - 1) / 26 | floor) else empty end )
  | select(. > 0) | (((. - 1) % 26) + 65) ] | reverse | implode;
def parseref:
    ascii_upcase | split(":") as $p
  | ($p[0] | capture("(?<c>[A-Z]+)(?<r>[0-9]+)")) as $a
  | (if ($p | length) > 1
     then ($p[1] | capture("(?<c>[A-Z]+)(?<r>[0-9]+)")) else $a end) as $b
  | { c_lo: ($a.c | colnum), r_lo: ($a.r | tonumber),
      c_hi: ($b.c | colnum), r_hi: ($b.r | tonumber) };
def mkref: "\(.c_lo|colname)\(.r_lo):\(.c_hi|colname)\(.r_hi)";

# a cell counts as POPULATED only if it carries a value.  silo's :gotcha: --
# an uncached formula is t=z,v=null but HAS .f -- so an f-bearing cell is
# populated even though its value is null, else whole formula columns vanish.
def populated: (.v != null and .v != "") or (has("f"));

# "is this cell TEXT?"  R3's whole discriminator is a type transition, so this
# predicate decides whether schema detection works at all.
# PREFER THE DECLARATION: when the parser tells us the type (silo `.t`), trust
# it -- that is conf:2 information read verbatim from the file, and a declared
# text cell holding "007" must stay text.  Only INFER when `.t` is absent, which
# is the whole bin2md stream (MEASURED: .t is null on all 551402 cells while
# silo types 212083 of them "n").  Without this fallback every rung sees a
# perfectly uniform "0% stringy" sheet, the transition test can never clear its
# 0.25 threshold, and schema detection returns EMPTY with rc=0 -- silent.
# The inference is deliberately the SAME rule as the select.jq WHERE mitigation
# (`tonumber?` declines => text), so the two files cannot drift apart.
# :trap: the `// null` is LOAD-BEARING, not defensive noise.  `tonumber?` on
# non-numeric text yields EMPTY, not null -- so `(tonumber?) == null` evaluates
# to empty, `select` receives no value, and the cell is DROPPED instead of
# counted as text.  That fails in the most confusing possible direction: every
# row reports 0 stringy cells and R3 finds nothing, exactly as if the fallback
# were absent.  `// null` converts empty to null so the comparison yields true.
def is_text:
  if has("t") then (.t == "s")
  else ((.v | tostring | tonumber? // null) == null) end;

  ($ARGS.named.file // "")            as $FILE
| ($ARGS.named.maxhdr // 10)          as $MAXHDR   # R3 scan depth; see :trap:
| ($ARGS.named.minw   // 2)           as $MINW     # min populated header cells
| ($ARGS.named.minstr // 0.6)         as $MINSTR   # min string fraction
| ($ARGS.named.minuniq // 0.7)        as $MINUNIQ  # min distinct-label frac
| ($ARGS.named.mincov  // 0.5)       as $MINCOV   # C3: label col vs sheet rows
| ($ARGS.named.minpair // 0.6)       as $MINPAIR  # C3: labels having a value
| ($ARGS.named.minshortc // 0.5)     as $MINSHORTC # C3: <=4-word label frac
| ($ARGS.named.minstem // 0.5)       as $MINSTEM  # C3: distinct first-words
| ($ARGS.named.minkeys // 6)         as $MINKEYS  # C3: min keys in a form

# ---- split the mixed stream -------------------------------------------------
| ( map(select(.k != null)) )                              as $meta
# STRUCTURAL cell test, same rule as jq/select.jq -- see the long comment there.
# The two parsers tag with OPPOSITE polarity (silo: cells carry no .k; bin2md:
# cells carry k:"cell" and the UNtagged rows are markdown blocks), so a tag test
# is right for exactly one of them.  Here the old `.k == null` was the more
# dangerous of the two call sites: on a bin2md stream the trailing `.r != null`
# quietly filters the markdown rows back out, so $cells goes EMPTY and every
# rung below reports "no table found" with rc=0 -- a silent wrong answer rather
# than a crash.  `.r != null and .c != null` is exact on both parsers.
| ( map(select(.r != null and .c != null)) | map(select(populated)) ) as $cells
| ( $cells | group_by(.s) | map({key: .[0].s, value: .}) | from_entries ) as $bysheet

# ---- per-sheet ladder -------------------------------------------------------
# The meta path is AUTHORITATIVE and comes first: it preserves the workbook's
# declaration ORDER, which the derived path cannot (`keys` sorts alphabetically).
# But it is silo-specific -- bin2md emits only schema|cell meta, no k="sheet" --
# so driving the ladder from it alone yields $sheets==[] on a bin2md stream and
# the whole ladder produces an EMPTY result with rc=0.  MEASURED: silo 6 sheet
# rows, bin2md 0, while the sheet NAMES are intact on all 551402 bin2md cells
# (`[.s]|unique` returns the same 6).  So fall back to the names the cells
# already carry.  A derived record has `.s` only -- no `.fr` -- so the R1
# frozen-pane rung at :104 simply does not fire, which is correct: bin2md emits
# `fr` on zero rows of this workbook, so R1 is unreachable there regardless.
| ( ( $meta | map(select(.k == "sheet")) ) ) as $metash
| ( if ($metash | length) > 0 then $metash
    else ($bysheet | keys | map({k: "sheet", s: .})) end ) as $sheets
| [ $sheets[]
    | . as $sh
    | ($sh.s) as $S
    | ($bysheet[$S] // []) as $cs
    | select($cs | length > 0)

    # rows of this sheet, as {r, cells}
    | ($cs | group_by(.r) | map({r: .[0].r, cells: .})) as $rows
    | ($rows | map(.r)) as $rnums
    | ($cs | map(.c) | min) as $cmin
    | ($cs | map(.c) | max) as $cmax
    | ($rnums | max) as $rmax

    # ---- R2: DECLARED -- table/af refs naming THIS sheet --------------------
    | ( [ $meta[]
          | select((.k == "table" or .k == "af") and .s == $S and .ref != null)
          | (.ref | parseref) as $R
          | { file: $FILE, sheet: $S, hdr_row: $R.r_lo,
              c_lo: $R.c_lo, c_hi: $R.c_hi, r_lo: $R.r_lo, r_hi: $R.r_hi,
              ref: ($R | mkref), rung: "R2", conf: 2 } ] ) as $r2

    # ---- R1: FROZEN band ----------------------------------------------------
    # .fr names a header BAND, never a rectangle, so the body extent still has
    # to be walked.  Demoted to conf 1 for exactly that reason.
    | ( if ($sh.fr != null and $sh.fr >= 1 and $sh.fr <= $MAXHDR)
        then ($sh.fr) as $H
          | ($rows | map(select(.r == $H)) | .[0]) as $hr
          | if $hr == null then []
            else
              ($hr.cells | map(.c) | min) as $clo
            | ($hr.cells | map(.c) | max) as $chi
            # body = contiguous rows below the band until a fully-empty row
            | ( [ $rnums[] | select(. > $H) ] | sort ) as $below
            | ( reduce $below[] as $x ($H; if $x == . + 1 then $x else . end) ) as $rhi
            | if $rhi > $H
              then [ { file: $FILE, sheet: $S, hdr_row: $H,
                       c_lo: $clo, c_hi: $chi, r_lo: $H, r_hi: $rhi,
                       ref: ({c_lo:$clo,r_lo:$H,c_hi:$chi,r_hi:$rhi} | mkref),
                       rung: "R1", conf: 1 } ]
              else [] end
            end
        else [] end ) as $r1

    # ---- R3: SHAPE ----------------------------------------------------------
    # A header row is mostly SHORT STRINGS, and -- the part that carries the
    # weight -- the rows BELOW it have a DIFFERENT type profile.  The string
    # test alone fires on every prose block and every title band; the type
    # TRANSITION is what separates a header from a caption.
    | ( [ $rows[]
          | select(.r <= $MAXHDR)
          | . as $row
          | ($row.cells | length) as $w
          | select($w >= $MINW)
          | ($row.cells | map(select(is_text)) | length) as $ns
          | select(($ns / $w) >= $MINSTR)
          # "short (1-3 words)": a header labels, it does not narrate
          | ($row.cells | map(select(is_text and ((.v|tostring)
                | split(" ") | length) <= 3)) | length) as $nshort
          | select(($nshort / $w) >= $MINSTR)
          # DISTINCTNESS: a header NAMES columns, so repeated labels are
          # evidence AGAINST a header ("dog cat dog cat" is a scratch row).
          | ($row.cells | map(.v|tostring) | unique | length) as $nuniq
          | select(($nuniq / $w) >= $MINUNIQ)
          # TYPE TRANSITION: the 3 rows below must be materially less stringy
          | ( [ $rows[] | select(.r > $row.r and .r <= $row.r + 3) ] ) as $blw
          | select($blw | length > 0)
          | ( $blw | map(.cells) | add ) as $bc
          | ( $bc | length ) as $bn
          | select($bn > 0)
          | ( $bc | map(select(is_text)) | length ) as $bs
          | select( ($ns / $w) - ($bs / $bn) >= 0.25 )
          | { r: $row.r, w: $w,
              c_lo: ($row.cells | map(.c) | min),
              c_hi: ($row.cells | map(.c) | max) } ] ) as $cand

    | ( if ($cand | length) == 0 then []
        else ($cand | sort_by(.r) | .[0]) as $h            # topmost wins
          | ( [ $rnums[] | select(. > $h.r) ] | sort ) as $below
          | ( reduce $below[] as $x ($h.r; if $x == . + 1 then $x else . end) ) as $rhi
          | if $rhi > $h.r
            then [ { file: $FILE, sheet: $S, hdr_row: $h.r,
                     c_lo: $h.c_lo, c_hi: $h.c_hi, r_lo: $h.r, r_hi: $rhi,
                     ref: ({c_lo:$h.c_lo,r_lo:$h.r,c_hi:$h.c_hi,r_hi:$rhi} | mkref),
                     rung: "R3", conf: 1 } ]
            else [] end
        end ) as $r3

    # ---- R4: MULTI-HIT ------------------------------------------------------
    # Two header runs in ONE row separated by a gap => tables SIDE BY SIDE.
    # Emitted only when a gap actually exists, so R4 never shadows R3 on the
    # ordinary single-table sheet.
    | ( if ($cand | length) == 0 then []
        else ($cand | sort_by(.r) | .[0]) as $h
          | ($rows | map(select(.r == $h.r)) | .[0].cells | map(.c) | sort) as $hc
          | ( reduce $hc[] as $c ([];
                if (length == 0) or ($c > (.[-1][-1] + 1))
                then . + [[$c]] else (.[:-1] + [.[-1] + [$c]]) end ) ) as $runs
          | if ($runs | length) < 2 then []
            else
              ( [ $rnums[] | select(. > $h.r) ] | sort ) as $below
            | ( reduce $below[] as $x ($h.r; if $x == . + 1 then $x else . end) ) as $rhi
            | [ $runs[] | select(length >= $MINW)
                | { file: $FILE, sheet: $S, hdr_row: $h.r,
                    c_lo: .[0], c_hi: .[-1], r_lo: $h.r, r_hi: $rhi,
                    ref: ({c_lo:.[0],r_lo:$h.r,c_hi:.[-1],r_hi:$rhi} | mkref),
                    rung: "R4", conf: 1 } ]
            end
        end ) as $r4

    # ---- C1: FROZEN COLUMNS -------------------------------------------------
    # Mirror of R1 across the diagonal: .fc names a LABEL BAND of columns.
    | ( if ($sh.fc != null and $sh.fc >= 1 and $sh.fc <= $MAXHDR)
        then ($sh.fc) as $K
          | ($cs | map(select(.c == $K))) as $kc
          | if ($kc | length) < $MINW then []
            else
              ($kc | map(.r) | min) as $rlo
            | ($kc | map(.r) | max) as $rhi
            | ( [ $cs[] | .c ] | unique | map(select(. > $K)) | sort ) as $right
            | ( reduce $right[] as $x ($K; if $x == . + 1 then $x else . end) ) as $chi
            | if $chi > $K
              then [ { file: $FILE, sheet: $S, hdr_row: $rlo, key_col: $K,
                       c_lo: $K, c_hi: $chi, r_lo: $rlo, r_hi: $rhi,
                       ref: ({c_lo:$K,r_lo:$rlo,c_hi:$chi,r_hi:$rhi} | mkref),
                       rung: "C1", axis: "col", conf: 1 } ]
              else [] end
            end
        else [] end ) as $c1

    # ---- C3: SHAPE ON THE COLUMN AXIS ---------------------------------------
    # Same evidence as R3, transposed: a label COLUMN is mostly short, mostly
    # distinct strings, and the columns to its RIGHT are materially less
    # stringy.  Without the type transition this fires on every prose column.
    | ( ($cs | group_by(.c) | map({c: .[0].c, cells: .})) as $cols
      | [ $cols[]
          | select(.c <= $MAXHDR)
          | . as $col
          | ($col.cells | length) as $h
          # FLOOR: a form is a form because it has a RUN of keys.  A 4-row
          # scratch sheet (cat/dog/cat2) satisfies every ratio below, since
          # ratios are meaningless at n=4.  $MINW=2 is right for a row header
          # but far too permissive down the column axis.
          | select($h >= $MINKEYS)
          | ($col.cells | map(select(is_text)) | length) as $ns
          | select(($ns / $h) >= $MINSTR)
          # a FORM LABEL is wordier than a column header -- "Assignment type",
          # "CCC estimate - written" -- so the <=3-word rule that fits a row
          # header rejects real forms (measured 55% on a genuine TL sheet).
          # Allow 4 and score the fraction lower.
          | ($col.cells | map(select(is_text and ((.v|tostring)
                | split(" ") | length) <= 4)) | length) as $nshort
          | select(($nshort / $h) >= $MINSHORTC)
          | ($col.cells | map(.v|tostring) | unique | length) as $nuniq
          | select(($nuniq / $h) >= $MINUNIQ)
          | ( [ $cols[] | select(.c > $col.c and .c <= $col.c + 3) ] ) as $rgt
          | select($rgt | length > 0)
          | ( $rgt | map(.cells) | add ) as $rc
          | ( $rc | length ) as $rn
          | select($rn > 0)
          | ( $rc | map(select(is_text)) | length ) as $rs
          # !! NO TYPE TRANSITION ON THIS AXIS.  R3 leans on "header stringy,
          # body not"; a FORM's values are text too (`PHILLIPS, R`, `DRP -
          # Collision Concepts`) -- measured 64% strings to the right of a
          # real label column, so demanding a 0.25 drop rejects every form.
          # The column axis must earn its keep from COVERAGE + PAIRING +
          # DISTINCTNESS instead, which is why those two guards above are
          # mandatory here and merely helpful on the row axis.
          | select( ($ns / $h) >= ($rs / $rn) )
          # STEM DIVERSITY: form keys NAME DIFFERENT THINGS -- "Insured",
          # "Loss Date", "Odometer" share no first word.  An enumerated DATA
          # column ("Text 1" .. "Text 40", "Header") is `unique` on every
          # value yet has one stem, so the distinctness test above cannot see
          # it.  Real false positive on the bench; require varied first words.
          | ( $col.cells | map(.v|tostring|ascii_downcase|split(" ")[0])
              | unique | length ) as $nstem
          | select( ($nstem / $h) >= $MINSTEM )
          # COVERAGE: a schema spans its sheet.  A 3-cell LEGEND ("A - ABSENT",
          # "L - LEAVE") in the corner of a 40-row roster passes every test
          # above -- stringy, short, distinct, numbers to the right -- and is
          # not a schema.  Observed as a real false positive on the bench.
          | select( ($h / ($rnums | length)) >= $MINCOV )
          # PAIRING: a key-value form has VALUES BESIDE ITS KEYS.  A bare word
          # list (75 words in c1, one number in c2) also passes everything
          # above.  Require most labels to have a neighbour on their right.
          | ( $col.cells | map(.r) ) as $lrows
          | ( $rc | map(.r) | unique ) as $vrows
          | ( [ $lrows[] | select(. as $x | $vrows | index($x)) ] | length ) as $paired
          | select( ($paired / $h) >= $MINPAIR )
          | { c: $col.c, h: $h,
              r_lo: ($col.cells | map(.r) | min),
              r_hi: ($col.cells | map(.r) | max) } ] ) as $ccand

    | ( if ($ccand | length) == 0 then []
        else ($ccand | sort_by(.c) | .[0]) as $k          # leftmost wins
          | ( [ $cs[] | .c ] | unique | map(select(. > $k.c)) | sort ) as $right
          | ( reduce $right[] as $x ($k.c; if $x == . + 1 then $x else . end) ) as $chi
          | if $chi > $k.c
            then [ { file: $FILE, sheet: $S, hdr_row: $k.r_lo, key_col: $k.c,
                     c_lo: $k.c, c_hi: $chi, r_lo: $k.r_lo, r_hi: $k.r_hi,
                     ref: ({c_lo:$k.c,r_lo:$k.r_lo,c_hi:$chi,r_hi:$k.r_hi} | mkref),
                     rung: "C3", axis: "col", conf: 1 } ]
            else [] end
        end ) as $c3

    # ---- STOP AT THE FIRST RUNG THAT FIRES ----------------------------------
    | ( if   ($r1 | length) > 0 then $r1
        elif ($r2 | length) > 0 then $r2
        elif ($r4 | length) > 0 then $r4
        elif ($r3 | length) > 0 then $r3
        # column axis LAST: only a sheet with no row-table at all is a form
        elif ($c1 | length) > 0 then $c1
        elif ($c3 | length) > 0 then $c3
        else [] end )[]
  | (if .axis == null then . + {axis: "row"} else . end)
  ]
| .[]
