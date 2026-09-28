#!/usr/bin/env python3
"""Assemble the preflight bundle.  Driven by prg-preflight.sh -- see that
file for WHY each section is present; every one is a measured lever from
fix.archive/text2sql-methodology.md, not a preference.

Reads (all already written by a bin2md --join --emit-ddl run):
    insert.prg.sql    the DDL sqlite will actually see  -> AUTHORITATIVE NAMES
    schema.prg.json   real headers, types, row counts, fk edges
    *.prg.jsonl       cell sidecars -> sample values
    shapes jsonl      item 3.1 value-shape histograms   -> join verdicts

Writes one text bundle on stdout (or --out).
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

ap = argparse.ArgumentParser()
ap.add_argument('--dir', required=True)
ap.add_argument('--shapes', default='')
# NOTE: this default is NEVER the effective one -- prg-preflight.sh always
# passes --samples explicitly, so the binding default lives in the wrapper
# (NSAMP=3).  Found while sabotage-testing the gate: changing THIS number
# alone had no observable effect on the bundle.  Kept in sync deliberately
# so a direct `python3 prg-preflight.py` invocation behaves the same.
ap.add_argument('--samples', type=int, default=3)
ap.add_argument('--out', default='-')
a = ap.parse_args()

D = a.dir


def rd(p):
    with open(p, encoding='utf-8', errors='replace') as f:
        return f.read()


# ---- 1. authoritative names, straight out of the DDL ---------------------
# Parsing the DDL rather than re-deriving names is the whole point: it is the
# only source that carries uniq()'s _2/_3 disambiguation.
ddl = rd(os.path.join(D, 'insert.prg.sql'))
ddl_tabs = re.findall(r'CREATE TABLE "([^"]+)" \(\n(.*?)\n\);', ddl, re.S)
ddl_names = [(t, re.findall(r'^\s+"([^"]+)"', b, re.M)) for t, b in ddl_tabs]

schema = json.loads(rd(os.path.join(D, 'schema.prg.json')))
# Only tables with columns reach the DDL; the emitter skips the rest, so the
# two lists align positionally.  Assert it rather than trust it -- a silent
# misalignment would attach every real header to the WRONG column, which is
# far worse than having no headers at all.
jtabs = [t for t in schema.get('tables', []) if t.get('columns')]
if len(jtabs) != len(ddl_names):
    sys.exit('preflight: DDL has %d tables, schema.prg.json has %d with '
             'columns -- refusing to guess the mapping'
             % (len(ddl_names), len(jtabs)))
for (tn, cols), t in zip(ddl_names, jtabs):
    if len(cols) != len(t['columns']):
        sys.exit('preflight: column-count mismatch on %s (%d vs %d) -- '
                 'refusing to emit a bundle with mislabelled columns'
                 % (tn, len(cols), len(t['columns'])))

# ---- 2. sample values, COLUMN-WISE ---------------------------------------
# Pulled from the sidecars, below the header row.  Column-wise because the
# INSERT INTO form of the same three values measurably HURTS (-1.2 vs +2.6).
samples = defaultdict(list)          # (file, sheet, col) -> [v, v, v]
seen = defaultdict(set)
want = a.samples
for t in jtabs:
    hdr = t.get('hdr_row') or 0
    fn = os.path.join(D, t['file'] + '.prg.jsonl')
    if not os.path.exists(fn):
        continue
    sheet = t.get('sheet', '')
    key_need = {c['col'] for c in t['columns']}
    with open(fn, encoding='utf-8', errors='replace') as f:
        for line in f:
            if not line.strip():
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get('s', '') != sheet:
                continue
            r, c, v = o.get('r'), o.get('c'), o.get('v')
            if r is None or c is None or v is None or c not in key_need:
                continue
            if r <= hdr:
                continue
            v = str(v).strip()
            if not v:
                continue
            k = (t['file'], sheet, c)
            # DISTINCT samples: a column that repeats one value would
            # otherwise spend all three slots saying the same thing.
            if len(samples[k]) < want and v not in seen[k]:
                samples[k].append(v)
                seen[k].add(v)

# ---- 3. shape verdicts (item 3.1) ----------------------------------------
shapes = {}                          # (file, sheet, col) -> top shape
if a.shapes and os.path.exists(a.shapes):
    for line in rd(a.shapes).splitlines():
        if not line.strip():
            continue
        try:
            o = json.loads(line)
        except ValueError:
            continue
        shapes[(o.get('file', ''), o.get('sheet', ''), o.get('col'))] = o.get('top')

# ---- 4. emit --------------------------------------------------------------
out = []
w = out.append

w('# PREFLIGHT BUNDLE -- read before writing SQL.')
w('# %d tables, %d columns.  The schema is NOT pruned: at this size'
  % (len(ddl_names), sum(len(c) for _, c in ddl_names)))
w('# pruning measurably hurts, so everything you need is already here.')
w('')
w('## DIALECT: SQLite, and one rule that is specific to this corpus')
w('# EVERY COLUMN IS TEXT, ON PURPOSE -- the emitter does not guess types.')
w('# So a numeric or date comparison MUST cast:')
w("#     WHERE CAST(paid_amt AS REAL) > 1000        -- not paid_amt > 1000")
w("#     ORDER BY CAST(wgt AS REAL) DESC            -- TEXT sorts '500' < '9'")
w('# Un-CAST TEXT compares LEXICALLY.  This is the most likely single cause')
w('# of a query that runs clean and returns the wrong rows.')
w('')

# per-table block
for (tn, cols), t in zip(ddl_names, jtabs):
    rows = (t.get('shape') or {}).get('rows')
    w('## %s' % tn)
    w('#   from: %s%s%s   rows=%s'
      % (t['file'],
         ' :: ' if t.get('sheet') else '',
         t.get('sheet', ''),
         rows if rows is not None else '?'))
    for sqlname, cdef in zip(cols, t['columns']):
        k = (t['file'], t.get('sheet', ''), cdef['col'])
        sv = samples.get(k, [])
        sh = shapes.get(k)
        # sanitized name | REAL HEADER | type | shape | 3 sample values
        line = '  %-28s | %s' % (sqlname, cdef.get('name', ''))
        bits = []
        if cdef.get('type'):
            bits.append('t=%s' % cdef['type'])
        if sh:
            bits.append('shape=%s' % sh)
        if bits:
            line += '  [%s]' % ' '.join(bits)
        if sv:
            line += '  eg: ' + ' | '.join(sv)
        w(line)
    w('')

# ---- 5. join edges, with the SHAPE VERDICT --------------------------------
# This section is the one the literature does not have, and it aims at the
# failure class that actually dominates: schema linking, 37-42% of errors.
w('## JOIN CANDIDATES (measured value overlap)')
w('# These edges are derived from values the two columns ACTUALLY SHARE,')
w('# so they are safe to join as written.  The shape is printed because you')
w('# need it to write the predicate -- it is NOT a check: overlap-derived')
w('# edges cannot have disagreeing shapes.  The joins that BREAK are the')
w('# ones absent from this list; see the name-alike section at the end.')
idx = {}
for i, t in enumerate(schema.get('tables', [])):
    idx[i] = t
ddl_of = {}
for (tn, cols), t in zip(ddl_names, jtabs):
    ddl_of[t['id']] = (tn, cols, t)

nedge = 0
mismatch = 0
for (tn, cols), t in zip(ddl_names, jtabs):
    for sqlname, cdef in zip(cols, t['columns']):
        for fk in (cdef.get('fk') or [])[:3]:
            m = re.match(r'\.tables\[(\d+)\]\.columns\[(\d+)\]', fk.get('column', ''))
            if not m:
                continue
            rt = idx.get(int(m.group(1)))
            if not rt or rt['id'] not in ddl_of:
                continue
            rtn, rcols, rtj = ddl_of[rt['id']]
            ci = int(m.group(2))
            if ci >= len(rcols):
                continue
            lk = (t['file'], t.get('sheet', ''), cdef['col'])
            rk = (rtj['file'], rtj.get('sheet', ''), rtj['columns'][ci]['col'])
            ls, rs = shapes.get(lk), shapes.get(rk)
            # NOT A CHECK -- PROVENANCE.  These edges were built from
            # measured value OVERLAP, and columns that share values
            # necessarily share shapes, so a shape comparison here CANNOT
            # disagree.  Measured: 333/333 edges "agree", and 0 of 244
            # columns have more than one distinct shape.  Printing "shapes
            # agree" would be an x-x check that always passes and would
            # manufacture false confidence -- exactly the self-validation
            # plan item 3.5 forbids.  The shape STRING is still worth
            # printing: it is what you need to WRITE the join predicate.
            # The real veto lives in the name-alike section below, which
            # operates on pairs the graph REJECTED.
            verdict = ''
            if ls and rs:
                if ls == rs:
                    verdict = '  shape %s' % ls
                else:
                    # Retained deliberately: if this EVER fires it means an
                    # invariant broke upstream, and that is worth shouting.
                    verdict = '  ** SHAPE MISMATCH %s vs %s -- INVARIANT VIOLATION **' % (ls, rs)
                    mismatch += 1
            w('  %s.%s = %s.%s   shared=%s jaccard=%s%s'
              % (tn, sqlname, rtn, rcols[ci], fk.get('shared'),
                 fk.get('jaccard'), verdict))
            nedge += 1
w('#   %d safe-to-join edges (%d invariant violations)' % (nedge, mismatch))
w('')

# ---- 6. cross-file joins the GRAPH DOES NOT PROPOSE -----------------------
# The dangerous join is not the one our artifacts recommend -- the graph
# already declines zero-overlap edges.  It is the one a MODEL invents from
# matching column NAMES.  So warn about same-name pairs that the graph
# rejected, which is exactly the cass/MG case.
w('## COLUMN PAIRS THAT **LOOK** JOINABLE AND ARE NOT')
w('# These share a name token, so a model will join them; their values have')
w('# different shapes, so the join returns ZERO ROWS.  This list exists')
w('# because a model writes joins from NAMES, while our fk edges are built')
w('# from measured value OVERLAP -- the graph already declined these, which')
w('# is exactly why they are invisible in the section above.')

# Match on shared TOKENS, not on the whole identifier.  The motivating case
# is shipment_ref vs shipment_nbr: an exact-name match never pairs them, yet
# that is the join that silently returns nothing.  Generic tokens are
# excluded or every id/name/total column pairs with every other.
def cls(shape):
    """The set of character classes in a shape: {'9'}, {'A'}, {'9','A','-'}.
    Insensitive to how many times each repeats, which is the difference
    between a word-count artefact and a real key-format mismatch."""
    return frozenset(ch for ch in shape if not ch.isspace())


STOP = {'id', 'no', 'nbr', 'num', 'ref', 'code', 'name', 'type', 'date', 'dt',
        'amt', 'total', 'qty', 'c', 'key', 'value', 'val', 'n', 'pct', 'avg'}
tok_idx = defaultdict(list)
for (tn, cols), t in zip(ddl_names, jtabs):
    for sqlname, cdef in zip(cols, t['columns']):
        k = (t['file'], t.get('sheet', ''), cdef['col'])
        sh = shapes.get(k)
        if not sh:
            continue
        for tok in set(sqlname.split('_')):
            if len(tok) >= 4 and tok not in STOP:
                tok_idx[tok].append((t['file'], tn, sqlname, sh))

warned = set()
nwarn = 0
for tok, lst in sorted(tok_idx.items()):
    for i in range(len(lst)):
        for j in range(i + 1, len(lst)):
            lf, lt, ln, ls = lst[i]
            rf, rt, rn, rs = lst[j]
            # Only cross-FILE pairs: two columns in one workbook are usually
            # the same quantity restated, not a join a model would invent.
            if lf == rf or ls == rs:
                continue
            # SHAPE STRING INEQUALITY IS TOO WEAK A TEST -- measured.  On this
            # corpus it fires 116 times, and 55 of those are `carrier`
            # "A" vs "A A", which is a WORD COUNT difference between "Estes"
            # and "Old Dominion".  Those columns join perfectly (the graph
            # measures jaccard=1), so warning about them would train a reader
            # to ignore the section.  What actually blocks a join is a
            # different CHARACTER CLASS SET: bare digits cannot match a
            # letter-prefixed key.  cass "9" -> {9} vs MG "A-9" -> {9,A,-}.
            if cls(ls) == cls(rs):
                continue
            key = (lt, ln, rt, rn)
            if key in warned:
                continue
            warned.add(key)
            w('  %s.%s [%s]  vs  %s.%s [%s]   <- shared token "%s", shapes differ'
              % (lt, ln, ls, rt, rn, rs, tok))
            nwarn += 1
w('#   %d name-alike cross-file pairs whose value shapes disagree' % nwarn)

txt = '\n'.join(out) + '\n'
if a.out == '-':
    sys.stdout.write(txt)
else:
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write(txt)
    sys.stderr.write('preflight: %d bytes -> %s\n' % (len(txt.encode()), a.out))
