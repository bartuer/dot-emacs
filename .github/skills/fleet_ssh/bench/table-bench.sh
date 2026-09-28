#!/usr/bin/env bash
# table-bench.sh — does the RENDERED table conform to table.schema.json?
#
# WHY THIS EXISTS AND parse-bench.sh DOES NOT COVER IT: parse-bench.sh grades
# the INPUT side (utterance -> scope/cols). A correct parse that renders a
# lying table is still a wrong answer, and the table is the ONLY thing the user
# reads. This arm runs the real wrapper against the real fleet and validates
# what comes back.
#
# WHAT IT PINS (each was a real or near-miss failure):
#   1. header[0] == "BOX"            -- the box column is positional, not named
#   2. one row per box in scope      -- a failed box still gets a row, never
#                                       silently dropped (the -b "c01 c02" bug
#                                       returned ONE row for TWO boxes at exit 0)
#   3. cell count == header count    -- a short row means a column was eaten
#   4. the three cell states stay distinct: value / "-" / "(unreachable)"
#   5. "(unreachable)" appears ONCE per row, not per column
#
# Uses a deliberately unreachable box so states 4/5 are exercised for real
# rather than asserted in prose. That box is EXPECTED to fail -- its failure is
# the fixture, not an error.
#
# Subverbs:
#   (none)   run the checks, print pass/fail per check
#   --quiet  totals only
# Exit: 0 all checks pass · 1 any fail · 2 missing dep
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wrapper="${here}/../fleet-ssh.sh"
schema="${here}/table.schema.json"
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1

[ -x "$wrapper" ] || { echo "MISSING wrapper: $wrapper" >&2; exit 2; }
[ -r "$schema"  ] || { echo "MISSING schema: $schema"  >&2; exit 2; }
command -v python3 >/dev/null || { echo "MISSING python3" >&2; exit 2; }

# Fixture: two real boxes + one that cannot resolve, so the unreachable and
# empty-output states are produced by the tool, not hand-written.
raw=$("$wrapper" -b "c01,c02,nosuchbox" CORES='nproc' EMPTY='true' 2>/dev/null) || true

# NOTE: the python body arrives as a HEREDOC, which IS stdin -- so a table
# piped in would be swallowed and read() returns "". Pass it as a FILE.
tbl=$(mktemp); printf '%s\n' "$raw" > "$tbl"
trap 'rm -f "$tbl"' EXIT

python3 - "$schema" "$quiet" "$tbl" <<'PY'
import sys, json, re

schema_path, quiet, tbl = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
schema = json.load(open(schema_path))
raw = open(tbl).read().rstrip("\n")
lines = [l for l in raw.split("\n") if l.strip()]

checks, fails = [], 0
def check(name, ok, detail=""):
    global fails
    if not ok: fails += 1
    checks.append((name, ok, detail))

if not lines:
    print("no table produced -- fleet unreachable?", file=sys.stderr)
    sys.exit(2)

# Parse the rendered table back into the schema's shape. Columns are
# 2+-space separated and right-padded by the awk renderer.
header = re.split(r'\s{2,}', lines[0].strip())
body   = [re.split(r'\s{2,}', l.rstrip()) for l in lines[1:]]

check("header[0] == BOX", header and header[0] == "BOX", f"got {header[0] if header else None!r}")

want_boxes = ["c01", "c02", "nosuchbox"]
got_boxes = [r[0] for r in body if r]
check("one row per box in scope",
      got_boxes == want_boxes,
      f"want {want_boxes} got {got_boxes}")

ncols = len(header) - 1  # excluding BOX
obj_rows = []
for r in body:
    if not r: continue
    box, cells = r[0], r[1:]
    unreachable = any(c.strip() == "(unreachable)" for c in cells)
    obj_rows.append({"box": box, "cells": cells, "unreachable": unreachable})

    if unreachable:
        # state 5: the sentinel appears ONCE, not repeated per column
        n = sum(1 for c in cells if c.strip() == "(unreachable)")
        check(f"{box}: (unreachable) printed once", n == 1, f"appeared {n}x")
    else:
        check(f"{box}: cell count == header count",
              len(cells) == ncols, f"want {ncols} got {len(cells)}")

# state 4: the three states are distinct and all observed in this fixture
flat = [c.strip() for r in obj_rows for c in r["cells"]]
check("state '-' (answered, no output) present", "-" in flat, f"cells={flat}")
check("state '(unreachable)' present", "(unreachable)" in flat, f"cells={flat}")
check("state value present", any(c.isdigit() for c in flat), f"cells={flat}")

# schema conformance of the reconstructed object
doc = {"header": header, "rows": obj_rows}
try:
    import jsonschema
    jsonschema.validate(doc, schema)
    check("validates against table.schema.json", True)
except ImportError:
    # fallback: assert the required keys the schema names
    ok = (isinstance(doc.get("header"), list) and len(doc["header"]) >= 1
          and isinstance(doc.get("rows"), list)
          and all(isinstance(r.get("box"), str) and isinstance(r.get("cells"), list)
                  for r in doc["rows"]))
    check("validates (required-field fallback, no jsonschema)", ok)
except Exception as e:
    check("validates against table.schema.json", False, str(e).split("\n")[0][:60])

if not quiet:
    for name, ok, detail in checks:
        print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f"   [{detail}]" if not ok and detail else ""))

print(f"{len(checks)-fails}/{len(checks)} table checks pass")
sys.exit(1 if fails else 0)
PY
