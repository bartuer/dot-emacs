# dag-verify.jq -- VERIFY a proposed join graph.  Never invents an edge.
#
# The model (or a human) proposes edges; this lens decides whether each one is
# REAL by measuring the value overlap, then decides whether the surviving graph
# is acyclic by a genuine three-colour DFS.
#
# WHY VERIFY RATHER THAN ENUMERATE.  join-candidates.jq scores the whole pair
# space and is the right tool for "what COULD join".  That is not this job.
# Here the question is "is the graph I am about to reason over sound", and the
# expensive part of the pair space is irrelevant: only the proposed pairs are
# measured.  On the reference case that is ~12 pairs instead of 6954.
#
# :decision: (plan 261, item 2.1) refuse to emit a DAG containing an unverified
# edge.  A silently-plausible DAG is worse than no DAG, because every downstream
# join inherits its authority.  So an edge whose n_shared is 0 is DROPPED and
# moved to rejects with its counter-evidence attached -- it is never quietly
# retained to keep the picture connected.
#
# INPUT   the colvals stream (jq -s), i.e. {file,sheet,col,hdr,n,n_all,vals}
# ARGS    --arg edges   TSV text: src<TAB>dst<TAB>lcol<TAB>rcol  (one per line)
#         --arg minshared N   overlap needed to accept an edge (default 1)
# OUTPUT  ONE object: {rule, n_proposed, n_edges, n_rejects, acyclic, cycle,
#                      order, edges:[...], rejects:[...]}

  ($ARGS.named.minshared // "1" | tonumber)  as $MINSHARED
| ($ARGS.named.rule      // "value")         as $RULE
| ($ARGS.named.pkuniq    // "0.9" | tonumber) as $PKUNIQ
| ($ARGS.named.edges     // "")              as $EDGETXT

| def norm: tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase;

# ---- node + column resolution ----------------------------------------------
# A node is a (file, sheet) pair.  Proposals are written by a model reading the
# schema catalog, so they may name a node by "file::sheet", by sheet alone, or
# by file alone.  Accept all three, but treat an AMBIGUOUS name as a failure
# rather than picking one -- silently choosing between two sheets called
# "Sheet1" is exactly the class of error this plan exists to prevent.
  ( map(. + { node: ((.file // "") + "::" + (.sheet // "")) }) )    as $COLS
| ( $COLS | group_by(.node) | map({key: .[0].node, value: .}) | from_entries ) as $BYNODE
| ( $COLS | map(.node) | unique )                                  as $NODES

| def resolve_node($name):
    ($name | norm) as $q
    | [ $NODES[] | select( (. | norm) == $q ) ]                    as $exact
    | (if ($exact | length) > 0 then $exact
       else [ $NODES[]
            | select( ((split("::")[1] // "") | norm) == $q
                   or ((split("::")[0] // "") | norm) == $q ) ]
       end);

# A column is named by header text, by "c<N>", or by a bare column number.
  def resolve_col($node; $name):
    ($name | norm) as $q
    | ($BYNODE[$node] // [])                                       as $cs
    | [ $cs[] | select( (.hdr | norm) == $q
                     or ("c" + (.col | tostring)) == $q
                     or (.col | tostring) == $q ) ];

# ---- parse the proposal ----------------------------------------------------
  ( $EDGETXT
    | split("\n")
    | map(select( (gsub("^\\s+|\\s+$"; "")) != "" and (startswith("#") | not) ))
    | map(split("\t") | map(gsub("^\\s+|\\s+$"; "")))
    | to_entries
    | map({ ln: (.key + 1),
            src: (.value[0] // ""), dst: (.value[1] // ""),
            lcol: (.value[2] // ""), rcol: (.value[3] // "") }) )   as $PROP

# ---- measure every proposed edge -------------------------------------------
| ( [ $PROP[]
    | . as $p
    | (resolve_node($p.src)) as $sn
    | (resolve_node($p.dst)) as $dn
    | if ($sn | length) != 1 or ($dn | length) != 1 then
        $p + { ok: false, n_l: 0, n_r: 0, n_shared: 0, contain: 0,
               tried: $RULE,
               why: (if ($sn | length) == 0 then "unknown src node: \($p.src)"
                     elif ($sn | length) > 1 then "AMBIGUOUS src node: \($p.src)"
                     elif ($dn | length) == 0 then "unknown dst node: \($p.dst)"
                     else "AMBIGUOUS dst node: \($p.dst)" end) }
      else
        $sn[0] as $s | $dn[0] as $d
        | (resolve_col($s; $p.lcol)) as $lc
        | (resolve_col($d; $p.rcol)) as $rc
        | if ($lc | length) != 1 or ($rc | length) != 1 then
            $p + { ok: false, n_l: 0, n_r: 0, n_shared: 0, contain: 0,
                   tried: $RULE, src_node: $s, dst_node: $d,
                   why: (if ($lc | length) == 0 then "unknown src column: \($p.lcol)"
                         elif ($lc | length) > 1 then "AMBIGUOUS src column: \($p.lcol)"
                         elif ($rc | length) == 0 then "unknown dst column: \($p.rcol)"
                         else "AMBIGUOUS dst column: \($p.rcol)" end) }
          else
            $lc[0] as $L | $rc[0] as $R
            | ($L.vals | map(norm) | unique) as $ls
            | ($R.vals | map(norm) | unique) as $rs
            | ($ls | length) as $nl | ($rs | length) as $nr
            | (($ls - ($ls - $rs)) | length)  as $ns
            | $p + { src_node: $s, dst_node: $d,
                     lhdr: $L.hdr, rhdr: $R.hdr,
                     n_l: $nl, n_r: $nr, n_shared: $ns,
                     contain: (if $nl == 0 or $nr == 0 then 0
                               else ((([$ns / $nl, $ns / $nr] | max) * 1000
                                     | round) / 1000) end),
                     uniq_l: (if ($L.n_all // 0) == 0 then 0
                              else (($nl / $L.n_all) * 1000 | round) / 1000 end),
                     uniq_r: (if ($R.n_all // 0) == 0 then 0
                              else (($nr / $R.n_all) * 1000 | round) / 1000 end),
                     tried: $RULE,
                     # THE LADDER IS A CHAIN OF CONJUNCTS, NOT A SWAP.
                     #   name  : the proposal resolves -- name agreement is the
                     #           ONLY evidence.  Deliberately unsound (item 1.2
                     #           measured 844 same-name pairs with zero shared
                     #           values); it exists as the loosest rung so the
                     #           escalation has somewhere to start.
                     #   value : name AND measured overlap >= minshared.
                     #   pk    : value AND one side is actually a KEY.
                     # Each rung ADDS a conjunct, so the accepted set can only
                     # ever shrink.  That is what makes the plan's
                     # "n_edges non-increasing" assertion a theorem about this
                     # code rather than a hope about the corpus.
                     ok: ( if $RULE == "name" then true
                           elif $RULE == "pk" then
                             ($ns >= $MINSHARED)
                             and ((([ (if ($L.n_all // 0) == 0 then 0 else $nl / $L.n_all end),
                                      (if ($R.n_all // 0) == 0 then 0 else $nr / $R.n_all end) ]
                                    | max)) >= $PKUNIQ)
                           else ($ns >= $MINSHARED) end ),
                     # The reject reason must name the counter-evidence, not
                     # merely negate: "0 shared" is a measurement, "not a join"
                     # is an opinion.
                     why: (if $ns < $MINSHARED
                           then "ZERO shared values across \($nl) x \($nr) distinct -- proposed edge is not a join"
                           elif $RULE == "pk"
                                and ((([ (if ($L.n_all // 0) == 0 then 0 else $nl / $L.n_all end),
                                         (if ($R.n_all // 0) == 0 then 0 else $nr / $R.n_all end) ]
                                       | max)) < $PKUNIQ)
                           then "\($ns) shared values but NEITHER side is a key (uniqueness < \($PKUNIQ)) -- rejected under rule=pk"
                           else "\($ns) shared values" end),
                     sample_l: ($ls | .[0:3]), sample_r: ($rs | .[0:3]) }
          end
      end ] )                                                      as $MEAS

| ( $MEAS | map(select(.ok)) )                                     as $EDGES
| ( $MEAS | map(select(.ok | not)) )                               as $REJ

# ---- three-colour DFS over the SURVIVING edges only -------------------------
# Colours: absent/0 = white (unvisited), 1 = grey (on the current stack),
# 2 = black (finished).  A grey hit is a back edge, i.e. a real cycle; a black
# hit is a cross/forward edge and is NOT a cycle.  Conflating the two is the
# classic bug -- it reports a cycle for any diamond, and this corpus is full of
# diamonds (two dimensions joining one fact table).
| ( $EDGES | group_by(.src_node)
    | map({key: .[0].src_node, value: (map(.dst_node) | unique)})
    | from_entries )                                               as $ADJ

| def dfs($n; $stack):
    . as $st
    | (($st.color[$n]) // 0) as $c
    | if $c == 2 then $st
      elif $c == 1 then
        # back edge -- cut the stack at the first occurrence to get the cycle
        $st | .cycle = ( ($stack[ ($stack | index($n)) : ]) + [$n] )
      else
        ( $st | .color[$n] = 1 )
        | reduce (($ADJ[$n]) // [])[] as $m
            ( . ; if .cycle then . else dfs($m; $stack + [$n]) end )
        | if .cycle then . else (.color[$n] = 2 | .order += [$n]) end
      end;

  ( reduce ($EDGES | map(.src_node, .dst_node) | unique)[] as $n
      ( {color: {}, cycle: null, order: []}
      ; if .cycle then . else dfs($n; []) end ) )                   as $ST

# ---- UNDIRECTED CYCLICITY -- the question the corpus statistics actually ask -
# MEASURED TRAP (item 2.1): edges derived from `candidates` are emitted with the
# left column always earlier in the colvals stream than the right (6954/6954 =
# 100%).  Feeding that straight in yields a graph that is topologically sorted
# BY CONSTRUCTION, so the directed DFS returns acyclic=true for 6110 edges over
# 79 nodes and proves NOTHING.  Directed acyclicity is a property of the
# ORIENTATION the proposer chose; join acyclicity (and every cyclicity number in
# this plan's Context section) is a property of the UNDIRECTED graph.
# So report both, and say plainly when the directed answer is vacuous.
| ( reduce $EDGES[] as $e
      ( {p: {}, cyc: false}
      ; def find($x): if (.p[$x] // $x) == $x then $x else find(.p[$x] // $x) end;
        (find($e.src_node)) as $a | (find($e.dst_node)) as $b
        | if $a == $b then .cyc = true else .p[$a] = $b end ) )       as $UF

  | { rule: $RULE,
    n_proposed: ($PROP | length),
    n_edges: ($EDGES | length),
    n_rejects: ($REJ | length),
    acyclic: ($ST.cycle == null),
    cycle: $ST.cycle,
    # true = the UNDIRECTED join graph has a cycle.  This is the number
    # comparable to the corpus sweep (name 25.6% / value 10.6% / pk 5.1%).
    undirected_cyclic: $UF.cyc,
    # A directed DAG sitting on an undirected cycle means acyclicity came from
    # the orientation, not from the data.  Refuse to let that read as proof.
    vacuous_dag: (($ST.cycle == null) and $UF.cyc),
    # reverse postorder = topological order, valid only when acyclic
    order: (if $ST.cycle == null then ($ST.order | reverse) else [] end),
    edges: $EDGES,
    rejects: $REJ }
