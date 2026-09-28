#!/usr/bin/env bash
# detect.sh FILE -> the R1..R4 ladder's candidate records for one workbook.
# The contract score.sh expects: one JSON object per line, carrying at least
# {sheet, ref, rung}.  Sharded BY FILE because the lens is not decomposable.
set -uo pipefail
JQF="${JQF:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../jq" && pwd)/silo-schema.jq}"
F="${1:?usage: detect.sh FILE.xlsx}"
[ -r "$F" ] || { echo "detect.sh: cannot read $F" >&2; exit 4; }
{ silo --dump-meta-json "$F"; silo --dump-json "$F"; } 2>/dev/null \
  | jq -s -c -f "$JQF" --arg file "$F" 2>/dev/null
