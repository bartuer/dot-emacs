# corpus-case.jq — index.jsonl / sheets.jsonl row -> {case, path, ...} contract.
# input : ONE row from a binary-index corpus produced by
#         src/collect/index_folder.sh (index.jsonl or sheets.jsonl).
# output: the row, plus `case` = the case-folder id extracted from .path.
#
# WHY: the corpus is organized so files inside one case folder are
# semantically related — the CASE, not the file, is the unit of meaning
# (plan 256 Context).  Every lens over this corpus must be able to roll up
# to the case, so the case id is derived once, here, and never re-guessed
# with an ad-hoc sed in a caller.
#
# The id is the path segment immediately after "/cases/".  A row whose path
# sits outside a cases/ tree gets "«nocase»" — a stable literal sentinel,
# matching the «toplevel»/«def» convention in prg-graph.sh.  It is NEVER
# silently dropped: an unattributable row is a finding, not noise.
. as $r
| ( $r.path // "" ) as $p
| ( if ($p | test("/cases/"))
    then ($p | split("/cases/")[1] | split("/")[0])
    else "«nocase»" end ) as $case
| $r + { case: $case }
