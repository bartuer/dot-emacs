# join-model.jq -- emit the folder's join model as self-describing JSONL.
#
# Item 6.2.  The contract travels in ROW ONE, exactly as the bin2md sidecars
# this derives from do ({"k":"schema","of":..,"version":..,"doc":..}).  There is
# deliberately NO .schema.json: a second artifact can drift from the thing it
# describes, and one reader then handles both bin2md sidecars and this file.
#
# WHY THIS EXISTS AT ALL -- it is a CONTEXT artifact, not a speed cache.
# Item 6.0 took the pipeline 19.3s -> 2.0s, which deleted every latency
# argument for persisting anything.  What 6.0 did NOT change is output SIZE:
#   corpus     1 494 354 B
#   candidates 2 325 476 B  (~581k tok) -- LARGER THAN THE CORPUS, cannot be
#                                          read into a context window at all
# Pruned to contain>=0.9 AND n_shared>=5 this is ~114 kB (~28k tok), so a model
# can jump to the right node without ever reading 6 954 pairs.
#
# Input : the `candidates --all` stream, slurped.
# --slurpfile schema : the `schema` stream (one row per file/sheet).
# --arg minshared / --arg mincontain : the prune thresholds.
#
# Output rows, in this order:
#   {"k":"schema"} x1   the contract
#   {"k":"node"}        one per (file,sheet), carrying hdr_row + axis
#   {"k":"edge"}        the top-k SURVIVING candidates, best first
#   {"k":"trunc"}       iff k < N -- emitted ONLY when rows were dropped
#   {"k":"warn"}  x1    the collapsed name-agreement counter-example set
#
# ---- 6.16: THE REJECT ROWS DIE, THE REJECT FINDING DOES NOT ----------------
# User: "we will not export the reject, only most important joins sorted, the
# top-k just set as the model context-window limitation."  This supersedes the
# per-row {"k":"reject"} stream that 6.2 shipped.
#
# But 6.0's red control still stands: a join model that records only what CAN
# be joined cannot warn about what MUST NOT be.  Measured on the 123-file
# reference case, EVERY one of the 35 996 rejects is same_name AND
# n_shared==0 -- i.e. all of them are exactly the class 6.0 said must survive.
# Deleting the rows wholesale would delete the warning.
#
# The escape is that the 35 996 ROWS carry only 20 DISTINCT normalised header
# names.  So this is not a choice between "keep the warning" and "fit the
# context":
#   35 996 rows  9 500 304 B   ->   1 warn row, 20 names, ~222 B   (42 794x)
# One {"k":"warn"} row says "these headers agree by name with ZERO shared
# values; never join on name alone."  Rows die, finding lives.
#
# Note the names are NORMALISED (lowercased/trimmed) and deduped, which is the
# same comparison `same_name` itself uses -- carrying both `ACCT` and `Acct`
# as separate warnings would imply they are separate findings.
#
# ---- k FROM A CONTEXT BUDGET, NOT A MAGIC NUMBER ---------------------------
# --arg budgettok B sets k = floor(B * (1 - reserve) / tok_per_edge), measured
# at ~41 tok/edge on the real artifact (166 B/edge).  Measured sizings:
#     8k tok ->  k ~  192 edges     32k -> ~771     128k -> ~3084
# 0 (the default) means unlimited -- the flag must be opt-in so existing
# callers are unaffected.  --arg topk overrides the computation outright.
#
# SILENT TRUNCATION IS THIS PLAN'S NAMED FAILURE MODE, so whenever k < N a
# {"k":"trunc","shown":k,"total":N} row is emitted.  A reader that sees edges
# and no trunc row KNOWS it has the complete ranked set.

def nodekey: "\(.file)\u0000\(.sheet // "")";
def norm: (. // "") | ascii_downcase | gsub("^\\s+|\\s+$"; "");

# k: explicit --topk wins; else derive from --budgettok; else 0 = unlimited.
(($ARGS.named.topk // "0") | tonumber) as $TOPK
| (($ARGS.named.budgettok // "0") | tonumber) as $BUDGET
| 41 as $TOKPEREDGE
| (if $TOPK > 0 then $TOPK
   elif $BUDGET > 0 then (($BUDGET * 0.9 / $TOKPEREDGE) | floor)
   else 0 end) as $K

# The surviving edges, RANKED.  Ordering is load-bearing now that k truncates:
# an unranked prefix would silently drop the best joins.  Same key as
# join-candidates.jq's $acc (contain, then n_shared) so "top-k" means the same
# thing at both stages.
| ( [ .[] | select(.verdict == "candidate"
                   and (.contain >= ($mincontain | tonumber))
                   and (.n_shared >= ($minshared | tonumber))) ]
    | sort_by(-.contain, -.n_shared) )                                as $edges
| ($edges | length)                                                   as $NEDGE
| (if $K > 0 and $K < $NEDGE then $K else $NEDGE end)                 as $SHOWN
#
# The warning, collapsed.  Names are normalised+deduped: `same_name` is itself
# a normalised comparison, so emitting `ACCT` and `Acct` separately would imply
# two findings where there is one.
| ( [ .[] | select(.verdict == "reject" and .same_name and .n_shared == 0)
          | (.l.hdr | norm), (.r.hdr | norm) ]
    | unique )                                                        as $warnnames
# COUNT THE NAMED CLASS, not "everything that is not a candidate".  These were
# the same set until the "weak" verdict existed; then `!= "candidate"` silently
# swept 18 778 normalisation-only pairs into a row that says they "share ZERO
# values", which is the opposite of what weak means.  Measured on
# soc-29-2072.00_task-22878: 35 996 -> 54 774 before this was pinned to "reject".
| ( [ .[] | select(.verdict == "reject") ] | length )                  as $NREJ
| ( [ .[] | select(.verdict == "weak") ] | length )                    as $NWEAK

# Node table, in schema order.  Object-as-set for the id lookup: re-scanning a
# list per edge is quadratic, and this file exists to delete a quadratic.
| ($schema | map({key: nodekey, value: .})) as $nrows
| ($nrows | map(.key) | to_entries | map({key: .value, value: .key}) | from_entries) as $nid

| (
    {k: "schema", of: "prg-join.sh model", version: "prg-join/1",
     doc: ("row1=schema; k=node per (file,sheet); k=edge per surviving join "
         + "candidate, BEST FIRST (contain, then n_shared); k=trunc iff the "
         + "edge list was cut to fit a context budget; k=warn x1 carrying the "
         + "collapsed name-agreement counter-example set. "
         + "Edges reference nodes by .l.n/.r.n, which index the "
         + "k=node rows by .id -- read the nodes first. "
         + "PRUNED at contain>=\($mincontain) AND n_shared>=\($minshared): an "
         + "edge is a PROPOSAL backed by measured overlap, never a verified "
         + "join -- run `prg-join.sh dag` to verify and `run` to execute. "
         + "ABSENCE OF A k=trunc ROW MEANS THE RANKED SET IS COMPLETE. "
         + "The k=warn names are headers that agree BY NAME with ZERO shared "
         + "values somewhere in this folder -- never join on name alone."),
     keys: {
       id: "node ordinal, 0-based; the join key for .l.n/.r.n",
       file: "sidecar basename, without .prg.jsonl",
       sheet: "sheet name; \"\" for single-surface formats (csv/md/txt)",
       hdr_row: "1-based RENDERED header row, or null when the sheet refuses one",
       axis: "row|col|none -- WHERE the header lives. null hdr_row with axis=col is a key-value form, NOT a failure",
       c: "column ordinal within its node",
       hdr: "that column's header text",
       n_l: "distinct values in the left column",
       n_r: "distinct values in the right column",
       n_shared: "values present in BOTH; 0 with same_name=true is the reject case",
       contain: "n_shared / min(n_l,n_r) -- 1.0 means one side is a subset",
       uniq_l: "distinct/total on the left; ~1.0 suggests a key",
       uniq_r: "same, right",
       same_name: "headers match after normalisation. NOT evidence -- see the k=warn row",
       shown: "edges actually emitted (k=trunc)",
       total: "edges that survived the prune before truncation (k=trunc)",
       names: "normalised headers implicated in a same-name/zero-overlap pair (k=warn)"
     },
     why_codes: {
       same_name_zero_overlap:
         ("identical header, ZERO shared values -- name agreement is not "
        + "evidence.  These pairs were REJECTED; the k=warn row lists every "
        + "header name involved so a reader cannot propose one by mistake.")
     },
     counts: {
       node: ($nrows | length),
       edge: $NEDGE,
       shown: $SHOWN,
       # rejected PAIRS, kept as a count even though the rows are gone: it is
       # the one number that would otherwise vanish with them, and "0 rejects"
       # vs "35 996 rejects" is the difference between a clean folder and a
       # minefield.
       rejected_pairs: $NREJ,
       warn_names: ($warnnames | length)
     },
     eg: "jq -c 'select(.k==\"edge\" and .n_shared>=20)' join.prg.jsonl"}
  ),

  # Nodes, in schema order so .id is stable across runs of the same folder.
  ($nrows | to_entries[]
   | {k: "node", id: .key, file: .value.value.file, sheet: (.value.value.sheet // ""),
      hdr_row: .value.value.hdr_row, axis: .value.value.axis,
      cols: .value.value.cols, rows: .value.value.rows}),

  # Edges -- the pruned survivors, RANKED and cut to k.
  ($edges[0:$SHOWN][]
   | . as $e
   | {k: "edge",
      l: {n: $nid[$e.l | nodekey], c: $e.l.col, hdr: $e.l.hdr},
      r: {n: $nid[$e.r | nodekey], c: $e.r.col, hdr: $e.r.hdr},
      n_l: $e.n_l, n_r: $e.n_r, n_shared: $e.n_shared,
      contain: $e.contain, uniq_l: $e.uniq_l, uniq_r: $e.uniq_r,
      same_name: $e.same_name}),

  # Truncation is ANNOUNCED, never silent.  Emitted only when rows were
  # actually dropped, so its mere presence is the signal.
  (if $SHOWN < $NEDGE
   then {k: "trunc", shown: $SHOWN, total: $NEDGE,
         doc: "edge list cut to fit the context budget; ranked best-first, so the dropped edges are the weakest"}
   else empty end),

  # THE WARNING, COLLAPSED.  35 996 reject rows (9 500 304 B) become one row
  # of 20 names (~222 B) on the reference case -- 42 794x -- because every
  # reject is the same class (same_name, n_shared==0) and the ROWS were only
  # ever restating which NAMES are untrustworthy.
  #
  # Emitted even when empty: {"names":[]} is the positive statement "no header
  # in this folder agrees by name while sharing nothing", which is different
  # information from a missing row (= this model predates the warning).
  {k: "warn", code: "same_name_zero_overlap",
   n_pairs: $NREJ, names: $warnnames,
   doc: "these headers agree BY NAME with ZERO shared values somewhere in this folder -- never join on name alone; test membership, not names"},

# THE MIRROR-IMAGE WARNING.  The row above is "same name, no values"; this one
# is "no exact values, but they overlap once normalised" -- the case that used
# to be structurally INVISIBLE (never enumerated, so not even a reject).
# Collapsed the same way and for the same reason.  Emitted even when empty.
({k: "warn", code: "normalised_overlap_only",
  n_pairs: $NWEAK,
  rules: ([ .[] | select(.verdict == "weak") | .norm_rule ] | unique),
  pairs: ([ .[] | select(.verdict == "weak")
                | { l: (.l.hdr | norm), r: (.r.hdr | norm), rule: .norm_rule } ]
          | unique | .[0:40]),
  doc: "these columns share ZERO exact values but DO overlap after normalisation (see rules) -- a real join candidate that exact matching cannot see, but the match is MANGLED: cite the rule, never quote it as a measured overlap"})
