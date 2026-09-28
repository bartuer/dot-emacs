#!/usr/bin/env bash
# prg-noaddr-nonxlsx.sh — verify that non-xlsx sources REFUSE to supply
# an A1 address rather than fabricating a plausible one.  NO LLM.
# Plan 07, item A.3.
#
# WHY THIS EXISTS
# src/bin2md.c:2132 publishes a contract consumers rely on:
#
#   "a" is present ONLY for xlsx, and is ABSENT (not null) on
#   docx/pptx/csv/md/pdf -- so has("a") is a real test
#
# ABSENT rather than null is the load-bearing part.  A null would still
# be a key, and `has("a")` would answer true for a pdf.  Synthesising a
# plausible-looking A1 for a csv is the same class of bug as computing
# one for a sheet (see prg-noaddrmath.sh): it does not fail, it
# succeeds at a cell that does not exist.
#
# MEASURED on this corpus, over the .prg.jsonl streams:
#   cass_paid_detail_OCT2024.csv    3000 cells,   0 with "a"
#   2024 LTL Bid Award ....xlsx      274 cells, 274 with "a"
# Clean and total in both directions.
#
# WHY IT READS THE STREAM AND NOT THE TABLE NAME
# The mangled table name keeps a `_csv` suffix, and on this corpus
# inferring the format from that suffix is right 24/24.  It is still
# the wrong signal: `q3_csv_export.xlsx` mangles to `q3_csv_export_xlsx`
# and reads as csv.  Those errors happen to fall on the SAFE side
# (over-refusing, never fabricating), but a rule that is correct by
# luck of filenames is not a contract.  The stream is authoritative;
# the name is a coincidence.
#
# EXIT 0 contract holds   1 an "a" appeared on a non-xlsx source, or a
#        null "a" was used where the key must be absent   2 usage
set -euo pipefail

corpus=${1:-}
[ -n "$corpus" ] && [ -d "$corpus" ] || {
	echo "usage: prg-noaddr-nonxlsx.sh CORPUS_DIR" >&2
	exit 2
}

find "$corpus" -name '*.prg.jsonl' -print0 |
	python3 -c '
import json, os, sys

data = sys.stdin.buffer.read().split(b"\0")
paths = [p.decode() for p in data if p.strip()]
if not paths:
    sys.stderr.write("prg-noaddr-nonxlsx: no .prg.jsonl found\n")
    sys.exit(2)

XLSX = ".xlsx"
bad, rows = [], []
for p in sorted(paths):
    src = os.path.basename(p)[: -len(".prg.jsonl")]
    is_xlsx = src.lower().endswith(XLSX)
    cells = with_a = null_a = 0
    with open(p, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("k") != "cell":
                continue
            cells += 1
            if "a" in d:
                with_a += 1
                if d["a"] is None:
                    null_a += 1
    rows.append((src, is_xlsx, cells, with_a, null_a))
    # A non-xlsx source must never carry the key at all.
    if not is_xlsx and with_a:
        bad.append((src, "non-xlsx carries %d \"a\" keys" % with_a))
    # Nobody may use null to mean absent -- that defeats has("a").
    if null_a:
        bad.append((src, "%d cells carry \"a\":null; the contract says "
                         "ABSENT, and null still answers has(\"a\")" % null_a))

nx = sum(1 for r in rows if not r[1])
print("sources: %d  (xlsx %d, non-xlsx %d)" % (len(rows), len(rows) - nx, nx))
for src, is_x, c, wa, _ in rows:
    if not is_x and c:
        print("  non-xlsx %-46s cells=%-6d with a=%d" % (src[:46], c, wa))

if bad:
    print()
    print("FAIL: the has(\"a\") discriminator is broken")
    for s, why in bad:
        print("  %s: %s" % (s, why))
    sys.exit(1)
print()
print("ok: every non-xlsx source refuses an address by OMITTING the key")
sys.exit(0)
'
