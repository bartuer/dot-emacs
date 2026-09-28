#!/usr/bin/env bash
# check-embed.sh — no-drift guard: the JSON Schema embedded in SKILL.md MUST
# equal the compiled schema/parse.schema.min.json byte-for-byte.  Exit 0 in
# sync, 1 on drift.  (Plan 43 CKP-2.3.)
#
# The embed is delimited in SKILL.md by these exact marker lines so extraction
# is unambiguous:
#   <!-- prg:parse-schema:begin -->
#   ```json
#   {...one line...}
#   ```
#   <!-- prg:parse-schema:end -->
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill="${here}/../SKILL.md"
minf="${here}/parse.schema.min.json"

[ -f "$skill" ] || { echo "check-embed: SKILL.md not found at $skill" >&2; exit 1; }
[ -f "$minf" ]  || { echo "check-embed: min schema not found (run the regen pipe first)" >&2; exit 1; }

# Extract the single json line between the begin marker's ```json fence and the
# closing fence.
embedded="$(awk '
  /<!-- prg:parse-schema:begin -->/ {inblk=1; next}
  /<!-- prg:parse-schema:end -->/   {inblk=0}
  inblk && /^```/ {infence = !infence; next}
  inblk && infence {print}
' "$skill")"

if [ -z "$embedded" ]; then
  echo "check-embed: no embedded parse-schema block found in SKILL.md" >&2
  exit 1
fi

if diff <(printf '%s\n' "$embedded") "$minf" >/dev/null 2>&1; then
  echo "check-embed: IN SYNC"
  exit 0
fi

echo "check-embed: DRIFT — embedded block != $minf" >&2
diff <(printf '%s\n' "$embedded") "$minf" >&2 || true
exit 1
