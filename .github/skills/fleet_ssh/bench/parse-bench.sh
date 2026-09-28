#!/usr/bin/env bash
# parse-bench.sh — grade the fleet_ssh SKILL.md parse against the gold set of
# REAL user utterances mined from the session where each one FAILED.
#
# WHY THIS EXISTS AND A HUMAN RE-READ DOES NOT: the parse rules were fixed
# eight times in one session, each fix prompted by a user correction. Nothing
# stopped fix #8 from reintroducing failure #2 -- every check was a one-off
# eyeball. This pins all seven failures so a regression is mechanical.
#
# WHAT IT GRADES: the two slots decidable WITHOUT a model. SCOPE (which boxes)
# and PROBE (is a probe derivable at all) are lexical -- they fall out of the
# words in the utterance. COLS (how many columns, named what) is a modelling
# judgement and is graded only on ARITY, which is lexical too (count the
# conjunctions). It never asserts the exact bash a model would write.
#
# Subverbs:
#   (none)   run the whole gold set, print a per-row table + totals
#   --quiet  totals only
# Exit: 0 all rows pass · 1 any row fails · 2 missing dep/gold · 5 gold too small
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gold="${here}/gold-parse.tsv"
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1

[ -r "$gold" ] || { echo "MISSING gold set: $gold" >&2; exit 2; }
command -v python3 >/dev/null || { echo "MISSING python3" >&2; exit 2; }

python3 - "$gold" "$quiet" <<'PY'
import sys, re

gold, quiet = sys.argv[1], sys.argv[2] == "1"

# ---- the parse under test -------------------------------------------------
# A model-free reference implementation of SKILL.md's three sentences. If the
# rules are stated clearly enough to be mechanical, this passes; where it
# cannot, the rule is underspecified and the bench says so.

BOX = re.compile(r'\bc0\d\b', re.I)

def parse_scope(u):
    """SCOPE: any box named in the utterance; none named => the whole fleet."""
    boxes = [b.lower() for b in BOX.findall(u)]
    # dedupe, keep order
    seen, out = set(), []
    for b in boxes:
        if b not in seen:
            seen.add(b); out.append(b)
    return ",".join(out) if out else "all"

def strip_slash(u):
    return re.sub(r'^/fleet_ssh\s*', '', u).strip()

def parse_probe(u):
    """PROBE: derivable unless the utterance is empty. Refusing otherwise is
    forbidden by SKILL.md, so the ONLY 'no' is an empty utterance."""
    return "no" if not strip_slash(u) else "yes"

def parse_arity(u):
    """COLS arity: split on commas and the conjunctions 'and'/'&'. A trailing
    collective noun ('version', 'usage') is a label, not another column."""
    body = strip_slash(u)
    if not body:
        return 0
    # drop box names -- they are SCOPE, never a column
    body = BOX.sub('', body)
    body = re.sub(r'\?+$', '', body).strip(' ,')
    if not body:
        return 0
    parts = re.split(r',|\band\b|&', body)
    parts = [p.strip(' ,') for p in parts]
    parts = [p for p in parts if p]
    return max(1, len(parts))

# ---- scoring --------------------------------------------------------------
rows, fails = [], 0
total = 0
with open(gold) as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            print("MALFORMED:", line.strip(), file=sys.stderr); fails += 1; continue
        utt, scope, cols, probe = parts[0], parts[1], parts[2], parts[3]
        total += 1
        want_cols = [c for c in cols.split(",") if c.strip()]

        got_scope = parse_scope(utt)
        got_probe = parse_probe(utt)
        got_arity = parse_arity(utt)

        ok_scope = got_scope == scope
        ok_probe = got_probe == probe
        # arity only meaningful when a probe exists
        ok_arity = (got_arity == len(want_cols)) if want_cols else (got_arity == 0)

        ok = ok_scope and ok_probe and ok_arity
        if not ok:
            fails += 1
        rows.append((utt, scope, got_scope, ok_scope, probe, got_probe, ok_probe,
                     len(want_cols), got_arity, ok_arity, ok))

if total < 5:
    print(f"gold set too small ({total} rows) -- refusing to report", file=sys.stderr)
    sys.exit(5)

if not quiet:
    print(f"{'UTTERANCE':<46} {'SCOPE':<16} {'PROBE':<7} {'COLS':<9} OK")
    print("-" * 92)
    for (utt, ws, gs, oks, wp, gp, okp, wc, gc, okc, ok) in rows:
        u = utt if len(utt) <= 45 else utt[:42] + "..."
        sc = gs if oks else f"{gs}!={ws}"
        pr = gp if okp else f"{gp}!={wp}"
        co = str(gc) if okc else f"{gc}!={wc}"
        print(f"{u:<46} {sc:<16} {pr:<7} {co:<9} {'ok' if ok else 'FAIL'}")
    print("-" * 92)

print(f"{total - fails}/{total} parse rows pass")
sys.exit(1 if fails else 0)
PY
