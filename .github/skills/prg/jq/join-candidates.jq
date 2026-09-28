# join-candidates.jq -- JOIN CANDIDACY BY MEASURED VALUE OVERLAP.
#
# INPUT: the column-value index emitted by `prg-join.sh candidates` --
#   {file, sheet, col, hdr, n, vals:[...]}    one per (file,sheet,column)
# slurped with `jq -s`.
#
# OUTPUT, one object per ordered-insensitive column pair:
#   {l:{file,sheet,col,hdr}, r:{...}, n_l, n_r, n_shared, jaccard,
#    contain, verdict, why}
#
# THE ONE RULE.  `verdict` is derived ONLY from n_shared -- never from header
# names.  Two columns both called "NOTES" share a name and nothing else; two
# columns called `EmpID` and `EMP #` are the same key spelled differently.
# Measured on this corpus: EmpID vs EMP # share 0 of 21 values, and joining
# them by name produces a confident, silent, WRONG answer.  So:
#
#   n_shared == 0  ->  verdict "reject"  EVEN IF THE HEADERS ARE IDENTICAL.
#
# That case is the whole point of this lens.  A rejected pair carries its
# counter-evidence (n_l, n_r, n_shared, and a sample of each side) so that
# "these two tables cannot be joined" is a CITABLE FINDING rather than an
# absence -- in the reference QBR analysis the single most valuable line in the
# report was a broken join.
#
# NORMALISATION is deliberately WEAK: trim + casefold only.  Aggressive
# normalisation (stripping punctuation, leading zeros, "#") manufactures
# overlap that does not exist in the data, which is precisely the failure this
# lens exists to catch.  If two keys only match after mangling, that IS the
# finding, and the caller should see the raw miss.
#
# CARDINALITY (:trap: from the plan).  88 schemas x ~10 cols is ~880 columns,
# whose full pair space is ~386k comparisons.  We cut it with cheap tests
# BEFORE the expensive set intersection:
#   - never pair a column with one in the SAME sheet
#   - both sides need >= $minvals distinct values (a 1-value column joins to
#     everything and means nothing)
#   - domain sizes within $ratio x of each other
#
# USAGE
#   prg-join.sh candidates <folder>
#   ... | jq -s -c -f jq/join-candidates.jq --arg minshared 1 --arg top 0

  ($ARGS.named.minvals   // "2"   | tonumber) as $MINVALS
| ($ARGS.named.ratio     // "100" | tonumber) as $RATIO
| ($ARGS.named.minshared // "1"   | tonumber) as $MINSHARED
| ($ARGS.named.top       // "0"   | tonumber) as $TOP
| (($ARGS.named.all      // "0") == "1")      as $ALL

# ---- THE BACK-PROPAGATION LEDGER (06/4.3) ----------------------------------
# Stage 1 (this file) judges a join with no database.  Stage 2 (a real SQLite
# query) judges the same join with one.  A stage-2 finding used to have NO WAY
# BACK: the corpus re-derived the identical wrong verdict on every run --
# MEASURED in 4.1, two `dag` runs producing byte-identical rejects.tsv.
#
# $LEDGER is that return path.  Optional and absent by default, so every
# existing invocation is unchanged.  Read via --slurpfile, so a missing file
# is an absent $ARGS.named entry rather than an error.
#
# WHAT A LEDGER RECORD MAY AND MAY NOT DO.  It may CHANGE `verdict`.  It may
# NOT touch n_shared, n_shared_norm, contain, or any other measurement --
# those are what the data said, and the whole value of this lens is that the
# question "what did the DATA say" stays answerable after a promotion.  So a
# promoted row keeps every measured field intact and gains three:
#   verdict_measured   the verdict n_shared alone produced
#   promoted_by        "ledger" (never set by measurement)
#   ledger_rows        the n_rows_observed that earned it
# THE ONE RULE at the top of this file is therefore still true as written --
# `verdict` is derived from n_shared alone UNLESS a second engine has
# OBSERVED ROWS for that exact pair, and when it has, both verdicts are on
# the row and the disagreement is visible rather than resolved silently.
#
# A confirm with n_rows_observed <= 0 is IGNORED, not honoured.  4.2 makes
# "confirm REQUIRES n_rows_observed > 0" a rule of the format; a reader that
# trusts the format instead of checking it turns one bad line into a
# fabricated join, which is the exact failure class this plan is about.
# The check lives HERE, in the consumer, because the writer cannot be trusted
# by a file that travels with a corpus.
#
# Keyed on {file,sheet,hdr} and NOT on col: a column INDEX is a property of
# today's extraction and dies the moment a column is inserted upstream.
# Direction-insensitive -- a finding about (a,b) applies to the pair however
# this file happens to enumerate it.
| ( ($ARGS.named.ledger // []) | map(select(.k == "finding")) )       as $LEDGER
| def lkey($x): [($x.file // ""), ($x.sheet // ""), (($x.hdr // "") | tostring | ascii_downcase)];
  def pkey($l; $r): ([lkey($l), lkey($r)] | sort);
  ( reduce $LEDGER[] as $f ({};
      if ($f.kind == "confirm" and (($f.n_rows_observed // 0) > 0))
         or $f.kind == "refute"
      then .[pkey($f.l; $f.r) | tostring] = $f
      else . end) )                                                  as $LIDX

# Weak normalisation only -- see NORMALISATION above.
| def norm: tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase;

# ---- THE RECIPE LEDGER: norm_rule ------------------------------------------
# NORMALISATION above says a match that needs mangling is a FINDING, and the
# caller must see the raw miss.  It does NOT say the finding should be thrown
# away, which is what happened until now: a pair that joins only after
# mangling scored n_shared 0 and left as an ordinary "reject", indistinguishable
# from two columns with genuinely nothing in common.
#
# So mangled matches get their own verdict, "weak", and their own count,
# n_shared_norm, and they name the rule that produced them in `norm_rule`.
# Three properties make this safe to add without weakening the one rule above:
#
#   1. `verdict` is STILL derived from n_shared alone.  "weak" is only ever
#      reached when n_shared == 0, so no pair that used to be a candidate can
#      become weak, and no weak pair can be mistaken for a measured one.
#   2. n_shared is NEVER touched by normalisation.  The exact count stays
#      exact; the normalised count lives in a separate field.
#   3. norm2 is a COARSENING of norm -- defined as f(norm(x)), never on the
#      raw value -- so equal norm implies equal norm2 and n_shared_norm is
#      always >= n_shared.
#
# affix/zero-pad is the FIRST accumulated rule.  Measured on the freight
# corpus, it is also the only join in that corpus needing repair:
#   cass.SHIPMENT_REF   "4887"        shape 9      x400
#   MG."Shipment Nbr"   "SH-0004651"  shape A-9    x400
# Neither whitespace nor case can bridge a PREFIX plus a ZERO-PAD, so this
# pair scored n_shared 0 and was never enumerated at all.  Under the rule the
# two sides meet on 2162 distinct keys -- the same 2162 an independent
# sqlite join returns, so the rule is checked against a second engine and not
# just against itself.
#
# DELIBERATELY NARROW, and the narrowness is the whole design:
#   - the affix must be NON-DIGIT.  Stripping a digit prefix would merge
#     genuinely different numbers.
#   - what remains must be ALL DIGITS.  Applying this to free text would
#     manufacture overlap everywhere, which is the exact failure the
#     NORMALISATION note warns about.
#   - a value that is not <non-digits><digits> is left ALONE, so the rule
#     cannot fire on a column it does not describe.
# Accepted collision: "SH-0004651" and "INV-4651" both reduce to "4651".
# Tolerable only because weak edges are advisory and are never admitted to
# the join ladder.
def norm2:
    . as $s
    | ($s | sub("^[^0-9]+"; "")) as $t
    | if ($t | length) > 0 and ($t | test("^[0-9]+$"))
      then (($t | sub("^0+"; "")) | if . == "" then "0" else . end)
      else $s end;

  [ .[]
  | select((.vals | length) >= $MINVALS)
  | (.vals | map(norm) | unique) as $set
  | . + { set: $set, set2: ($set | map(norm2) | unique) } ]          as $cols

| [ range(0; $cols | length) as $i
  | range($i + 1; $cols | length) as $j
  | $cols[$i] as $L | $cols[$j] as $R
  | select($L.file != $R.file or $L.sheet != $R.sheet)
  | ($L.set | length) as $nl
  | ($R.set | length) as $nr
  # cheap domain-size gate before the intersection
  | select( ($nl <= $nr * $RATIO) and ($nr <= $nl * $RATIO) )
  | (($L.set - ($L.set - $R.set)) | length)                          as $ns
  | ($nl + $nr - $ns)                                                as $uni
  # The normalised intersection is computed ONLY when the exact one is empty.
  # That is not just a speed guard: it makes it structurally impossible for
  # normalisation to influence a pair that already has measured evidence.
  | (if $ns == 0
     then (($L.set2 - ($L.set2 - $R.set2)) | length)
     else $ns end)                                                   as $nsn
  | { l: {file: $L.file, sheet: $L.sheet, col: $L.col, hdr: $L.hdr},
      r: {file: $R.file, sheet: $R.sheet, col: $R.col, hdr: $R.hdr},
      n_l: $nl, n_r: $nr, n_shared: $ns,
      # uniqueness = distinct/populated.  Carried HERE rather than recomputed
      # later because `dag` escalating name->value->pk must not need a second
      # pass over the sidecars: one call, everything the next decision needs.
      uniq_l: (if ($L.n_all // 0) == 0 then 0
               else (($nl / $L.n_all) * 1000 | round) / 1000 end),
      uniq_r: (if ($R.n_all // 0) == 0 then 0
               else (($nr / $R.n_all) * 1000 | round) / 1000 end),
      jaccard: (if $uni == 0 then 0 else (($ns / $uni) * 1000 | round) / 1000 end),
      # containment: the max side-coverage.  A small dimension table joining
      # into a big fact table has low jaccard but containment near 1.0, and
      # jaccard alone would hide it.
      contain: (if $nl == 0 or $nr == 0 then 0
                else ((([$ns / $nl, $ns / $nr] | max) * 1000 | round) / 1000) end),
      same_name: (($L.hdr | norm) == ($R.hdr | norm)),
      # THE ONE RULE, intact: candidacy is decided by n_shared and nothing
      # else.  "weak" is a subdivision of the reject side, never of the
      # candidate side.
      verdict: (if $ns >= $MINSHARED then "candidate"
                elif $nsn > 0 then "weak"
                else "reject" end),
      n_shared_norm: $nsn,
      # THE FALSE-POSITIVE PROBLEM, AND WHY THIS FIELD EXISTS RATHER THAN A
      # THRESHOLD.  Measured on the freight corpus: the rule produces 34 weak
      # edges, of which 4 are the real cass/MG shipment join and 30 are
      # coincidence -- BILLED_WT and Wgt "match" Shipment Nbr because
      # stripping "SH-" and the zero-pad leaves a bare number that happens to
      # collide with a weight.  That is precisely the "manufactures overlap"
      # failure the NORMALISATION note warns about, so it must be visible.
      #
      # contain_norm separates them cleanly and WITHOUT a tuned constant:
      #     0.974  SHIPMENT_REF <-> Shipment Nbr   (the real join, 2162)
      #     0.667  and below                       (every false positive)
      # uniq_l/uniq_r do NOT separate them (0.999/1 vs 0.941/1), so this is
      # the field that carries the signal.
      #
      # No cut-off is applied here on purpose.  A weak edge is advisory and is
      # never admitted to the join ladder, so a false positive costs a line of
      # output, while a threshold picked to make this corpus look clean is a
      # tuned constant that would silently drop a real join on the next one.
      # The rows are SORTED by this field instead, so the true edge is first
      # and `--top` truncates the tail.
      contain_norm: (if $nl == 0 or $nr == 0 or $nsn == 0 then 0
                     else ((([$nsn / $nl, $nsn / $nr] | min) * 1000 | round) / 1000)
                     end),
      # Names WHICH rule earned the weak edge, so the ledger accumulates
      # rules rather than anonymous near-misses.  null on every non-weak row,
      # so `select(.norm_rule)` is exactly the set of mangled matches.
      norm_rule: (if $ns == 0 and $nsn > 0 then "affix/zero-pad" else null end),
      why: (if $ns == 0 and $nsn > 0 then
              "0 shared values EXACT; \($nsn) only after affix/zero-pad -- advisory, NOT a measured join"
            elif $ns == 0 then
              (if (($L.hdr | norm) == ($R.hdr | norm))
               then "IDENTICAL HEADER, ZERO SHARED VALUES -- name agreement is not evidence"
               else "no shared values" end)
            else "\($ns) shared values" end),
      # counter-evidence, so a reject is citable rather than an absence
      sample_l: ($L.set | .[0:3]),
      sample_r: ($R.set | .[0:3]) }
  # 06/4.3.  Apply the ledger LAST, after every measured field is final, so
  # the promotion is provably incapable of feeding back into a measurement.
  | . as $row
  | ($LIDX[pkey($row.l; $row.r) | tostring]) as $f
  | if $f == null then .
    elif $f.kind == "confirm" and $row.verdict != "candidate" then
      . + { verdict: "candidate",
            verdict_measured: $row.verdict,
            promoted_by: "ledger",
            ledger_rows: $f.n_rows_observed,
            norm_rule: ($f.norm_rule // $row.norm_rule),
            why: "PROMOTED FROM \($row.verdict) BY LEDGER: \($f.n_rows_observed) rows OBSERVED by \($f.by // "?") under \($f.norm_rule // "no rule") -- measured overlap here is still \($row.n_shared)" }
    elif $f.kind == "refute" and $row.verdict == "candidate" then
      . + { verdict: "reject",
            verdict_measured: $row.verdict,
            promoted_by: "ledger",
            ledger_rows: $f.n_rows_observed,
            why: "DEMOTED FROM candidate BY LEDGER: refuted by \($f.by // "?") -- measured overlap here is \($row.n_shared)" }
    # A finding that agrees with the measurement changes nothing and must not
    # add fields: an unnecessary diff is how a no-op reads as a regression.
    else . end ]


# ---- WHAT TO ACTUALLY EMIT -------------------------------------------------
# The full pair space on the reference corpus is 171630 pairs / 64MB.  Emitting
# that defeats the entire purpose: the point of this tool is to SAVE model
# round-trips, and no model can read 64MB.  So the default output is
# DECISION-SIZED, and `--all` is available when a human wants the raw space.
#
# Which rejects are worth printing?  Only the PLAUSIBLE ones.  A reject between
# two columns nobody would ever have joined is noise; a reject between two
# columns that SHARE A NAME is the finding -- it is exactly the join a
# name-matching agent (or a human skimming headers) would have made.  Measured
# here: 809 such pairs, every one a silent wrong join avoided.
| ( map(select(.verdict == "candidate"))
    | sort_by(-.contain, -.n_shared) )                               as $acc
| ( map(select(.verdict == "reject" and .same_name))
    | sort_by(-.n_l) )                                               as $rej
# Weak edges are emitted REGARDLESS of same_name.  The same-name filter above
# exists to keep rejects decision-sized by printing only the ones a
# name-matcher would have made -- but a weak edge has already earned its place
# by measured normalised overlap, and the cass/MG pair that motivates this
# rule does NOT share a name ("SHIPMENT_REF" vs "Shipment Nbr").  Filtering
# weak by same_name would drop the exact case the rule was written for.
| ( map(select(.verdict == "weak"))
    | sort_by(-.contain_norm, -.n_shared_norm) )                     as $wk
| ( if $ALL then (map(.) | .[])
    else
      ( (if $TOP > 0 then $acc[0:$TOP] else $acc end)[]
      , (if $TOP > 0 then $wk[0:$TOP]  else $wk  end)[]
      , (if $TOP > 0 then $rej[0:$TOP] else $rej end)[] )
    end )
# Samples are counter-evidence for a human reading ONE reject, not bulk output.
| if $ALL then . else del(.sample_l, .sample_r) end
