#!/usr/bin/env bash
# sep-bench.sh — regression: -b accepts BOTH comma and whitespace box lists.
# Found by gold-parse.tsv row "/fleet_ssh c01 c02 rg version": the user SAYS
# boxes space-separated, the flag documented only commas, so `-b "c01 c02"`
# resolved to one bogus host and returned a single (unreachable) row with
# exit 0 -- a silent wrong answer, not an error.
# Exit: 0 both forms agree · 1 they differ
set -euo pipefail
W="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fleet-ssh.sh"
a=$("$W" -b "c01 c02" H='hostname' 2>/dev/null | tail -n +2 | awk '{print $1}' | sort)
b=$("$W" -b c01,c02    H='hostname' 2>/dev/null | tail -n +2 | awk '{print $1}' | sort)
if [ "$a" = "$b" ] && [ "$(printf '%s\n' "$a" | grep -c .)" = 2 ]; then
  echo "2/2 separator forms agree (space == comma)"; exit 0
fi
echo "FAIL: space=[$a] comma=[$b]"; exit 1
