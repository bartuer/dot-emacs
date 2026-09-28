#!/usr/bin/env bash
# prg-schema.sh — project a bin2md SQL corpus down to what a MODEL needs
# to write a correct query, and nothing else.  NO LLM.
#
# WHY THIS EXISTS
# A scanned corpus publishes two artifacts: schema.prg.json (the rich
# description) and insert.prg.sql (the DDL that built the database).  The
# rich one is what a model gets handed today, and it is too expensive:
#
#   schema.prg.json ..... 109,738 B  ~27,434 tok   28 tables
#   this projection .....   4,106 B  ~ 1,026 tok   24 tables   26.7x less
#
# 27k tokens is a fifth of a 128k window spent before the model has read
# the question.  Plan 07, item I.1.
#
# WHY IT READS THE DDL AND NOT THE JSON  (this is the whole point)
# The obvious projection is one jq expression over schema.prg.json:
#
#   jq -c '[.tables[]|{t:.id,c:[.columns[].name]}]'      # WRONG
#
# It is 3,189 B and it is USELESS, because neither field is a SQL name:
#
#   .id      is a JQ PATH        ".tables[0]"   not a table name
#   .name    is the HUMAN HEADER "Orig St"      not a column name
#
# The emitter normalizes both ("Orig St" -> orig_st).  MEASURED on the
# freight corpus, one `select <first col> from <table> group by 1` per
# table, executed against the real database:
#
#   projection from schema.prg.json ..... 17/24 tables queryable
#   projection from insert.prg.sql ...... 24/24 tables queryable
#
# 17/24 is the WORST possible outcome — it looks like it works, then
# fails on a quarter of the corpus with `no such column`.  The DDL is
# the only artifact that contains the identifiers SQL will actually
# accept, so it is the only defensible source.  Do not "simplify" this
# back to jq over the JSON; that is the bug this tool exists to avoid.
#
# WHY IT REPORTS 24 AND NOT 28
# schema.prg.json describes 28 tables; the DDL creates 24.  The other 4
# are not lost — emitsql declines them out loud:
#
#   SKIPPED (no columns detected): Carrier Scorecard Q4-2024.xlsx [Sheet1]
#
# and each has columns=[] in the JSON.  A projection built from the JSON
# would advertise 4 tables that do not exist in the database.  Reading
# the DDL makes that class of error unrepresentable rather than merely
# unlikely.
#
# USAGE
#   prg-schema.sh <insert.prg.sql>          compact JSON, one line
#   prg-schema.sh <insert.prg.sql> --text   one table per line, for humans
#   prg-schema.sh <insert.prg.sql> --stats  sizes and reduction vs the JSON
#
# OUTPUT  [{"t":<sql table>,"n":<rows>,"c":[<sql columns>]}]
# `n` is row count: a model picking between two similar tables should
# prefer the populated one, and it costs 4 bytes.
#
# FOREIGN KEYS: --fk, and only the SURPRISING ones.  Plan 07 item I.2.
# schema.prg.json carries 570 fk edges over 161 of 244 columns.  All of
# them cost 9.4x over names-only, which eats most of the 26.7x win.  But
# MEASURED, 140 top-1 edges executed as real joins against the database:
#
#   edges that join and return rows ......... 140/140  (0 errors, 0 empty)
#   edges where BOTH SIDES HAVE THE SAME NAME  128/140  (91%)
#
# 91% of the graph tells a model something it can see for itself: join
# carrier to carrier.  Paying ~8,600 tokens to say so is the definition
# of a bad projection.  The remaining 12 are the ones worth money --
# e.g. "awarded" -> "scac", a column of carrier codes under a name that
# gives no hint, which NO name-matching model finds.  So --fk carries
# the surprise and drops the obvious:
#
#   names only ........  4,106 B   26.7x reduction
#   names + 12 surprising  5,658 B   19.4x reduction   (--fk)
#   names + all 570 fk .. 38,697 B    2.8x reduction
#
# --fk is 1.38x over names-only rather than 9.4x, for the edges that
# actually carry information.
set -euo pipefail

sql=""
mode=json
withfk=0
withhdr=0
for a in "$@"; do
	case "$a" in
	--fk) withfk=1 ;;
	--hdr) withhdr=1 ;;
	--text | --stats) mode=$a ;;
	-*) echo "prg-schema: unknown option $a" >&2; exit 2 ;;
	*) sql=$a ;;
	esac
done
if [ -z "$sql" ] || [ ! -f "$sql" ]; then
	echo "usage: prg-schema.sh <insert.prg.sql> [--text|--stats] [--fk] [--hdr]" >&2
	exit 2
fi
export PRG_SCHEMA_FK=$withfk
export PRG_SCHEMA_HDR=$withhdr

python3 - "$sql" "$mode" <<'PY'
import re, sys, json, io, os

path, mode = sys.argv[1], sys.argv[2]
sql = io.open(path, encoding='utf-8', errors='replace').read()

# The DDL comment carries file/sheet/rows; the CREATE that follows carries
# the SQL identifiers.  Pairing them is what makes the output both
# queryable (SQL names) and explainable (origin).
blk = re.compile(
    r'^-- (.+?)(?: \[(.*?)\])?  hdr_row=\S+ rows=(\d+)\n'
    r'CREATE TABLE "([^"]+)" \((.*?)\n\);', re.S | re.M)
# NUM was added by plan 07 T.5, which gave columns a declared type.  A
# type this pattern does not list is INVISIBLE here: the column vanishes
# from the projection and the model never learns it exists.  That is a
# silent under-report, exactly the failure this tool's header warns
# about, so keep this alternation in sync with emitsql's declared types.
col = re.compile(r'^\s*"?([A-Za-z_][A-Za-z0-9_]*)"?\s+(?:TEXT|INTEGER|REAL|NUM)', re.M)
# Same line, but accepting ANY quoted name.  The two counts must agree:
# emitsql's mangler guarantees [a-z0-9_] with a non-digit start
# (src/emitsql.c:214), so a column the strict pattern rejects means the
# DDL did not come from this emitter.  Dropping it silently would hand a
# model an incomplete table, so the difference is reported, not hidden.
anycol = re.compile(r'^\s*"([^"]+)"\s+(?:TEXT|INTEGER|REAL|NUM)', re.M)

out, dropped = [], 0
order = []
for f, s, rows, name, body in blk.findall(sql):
    c = col.findall(body)
    dropped += max(0, len(anycol.findall(body)) - len(c))
    out.append({"t": name, "n": int(rows), "c": c})
    order.append((f.strip(), s or ''))

# --fk: attach ONLY the edges a name-matching model would miss.  The
# join target in schema.prg.json is already a qualified SQL identifier
# ("table"."column"), unlike .id/.name -- so it can be used verbatim.
if os.environ.get('PRG_SCHEMA_FK') == '1':
    rich = os.path.join(os.path.dirname(path) or '.', 'schema.prg.json')
    if not os.path.exists(rich):
        sys.stderr.write("prg-schema: --fk needs schema.prg.json beside "
                         "the DDL; continuing without fk\n")
    else:
        sch = json.load(io.open(rich, encoding='utf-8'))
        by = {}
        for t in sch.get("tables", []):
            by[(t["file"].strip(), t.get("sheet") or '')] = t
        for i, tb in enumerate(out):
            src = by.get(order[i])
            if not src:
                continue
            fk = {}
            for j, cdef in enumerate(src["columns"]):
                if j >= len(tb["c"]) or not cdef.get("fk"):
                    continue
                top = max(cdef["fk"], key=lambda z: z.get("jaccard", 0))
                tgt = top["join"]
                # same-name edges are inferable; carrying them is waste
                if tgt.split('".')[-1].strip('"') != tb["c"][j]:
                    fk[tb["c"][j]] = tgt
            if fk:
                tb["fk"] = fk

# --hdr: give back the ORIGINAL header for columns whose SQL name cannot
# speak for itself.  Plan 06 item 3.21, option B.
#
# The normalizer strips every non-alphanumeric character, so "Var $" and
# "Var %" both sanitize to `var` and the second becomes `var_2`.  The
# suffix is POSITIONAL -- it carries no meaning, and the original header
# appears NOWHERE in the DDL.  A model choosing between `var` and
# `var_2` has a 50% chance and no signal that it is guessing.  This is
# the CAST trap one level up: cast-numeric-trap.md records `72.5%`
# casting to 72.5, looks right and is 100x wrong -- here the same
# percent/dollar distinction is lost EARLIER, at naming, where no CAST
# can recover it because the character is already gone.
#
# MEASURED over all 1,222 emitted schemas, 1,490 true collision groups:
#   true duplicate (identical header) . 763  51.2%   _2 is honest
#   currency $ / percent % / count # .. 524  35.2%
#   +/- and range markers ............. 188  12.6%
#   letters or case only ..............   7   0.5%
# So HALF are honest and lose nothing, and of the rest, an eighth are
# +/- and <>= families a $/%/# symbol table would miss entirely.  That
# is why this CARRIES the header rather than interpreting it: renaming
# to var_pct/var_usd would invent semantics from punctuation, fire on
# 763 groups where nothing was lost, and still miss `Tol +`/`Tol -`.
# Carry, never compute -- the same ruling 07 A.2 reached for addresses.
#
# Emitted ONLY for collided columns, so the cost is proportional to the
# ambiguity rather than to the corpus, and the DDL is not touched.
if os.environ.get('PRG_SCHEMA_HDR') == '1':
    rich = os.path.join(os.path.dirname(path) or '.', 'schema.prg.json')
    if not os.path.exists(rich):
        sys.stderr.write("prg-schema: --hdr needs schema.prg.json beside "
                         "the DDL; continuing without headers\n")
    else:
        sch = json.load(io.open(rich, encoding='utf-8'))
        by = {}
        for t in sch.get("tables", []):
            by[(t["file"].strip(), t.get("sheet") or '')] = t
        for i, tb in enumerate(out):
            src = by.get(order[i])
            if not src:
                continue
            names = [c.get("name", "") for c in src["columns"]]
            # A column needs its header back when its SQL name is not
            # recoverable from it: either it took a positional suffix,
            # or a sibling in the same table sanitizes to the same stem.
            hdr = {}
            for j, sqlname in enumerate(tb["c"]):
                if j >= len(names):
                    break
                orig = names[j]
                m = re.match(r'^(.*)_(\d+)$', sqlname)
                collided = bool(m and m.group(1) in set(tb["c"]))
                if not collided:
                    # the un-suffixed member of a collision group is
                    # equally ambiguous -- "var" beside "var_2" gives no
                    # hint which is dollars.
                    collided = any(
                        re.match(r'^' + re.escape(sqlname) + r'_\d+$', o)
                        for o in tb["c"])
                if collided and orig:
                    hdr[sqlname] = orig
            if hdr:
                tb["hdr"] = hdr

if dropped:
    sys.stderr.write("prg-schema: WARNING %d column(s) are not valid SQL "
                     "identifiers and were omitted; this DDL was not "
                     "produced by emitsql\n" % dropped)

if not out:
    sys.stderr.write("prg-schema: no CREATE TABLE found in %s\n" % path)
    sys.exit(1)

if mode == '--text':
    for t in out:
        print("%s  (%d rows)\n  %s" % (t["t"], t["n"], ", ".join(t["c"])))
elif mode == '--stats':
    j = json.dumps(out, separators=(',', ':'))
    print("tables      %d" % len(out))
    print("columns     %d" % sum(len(t["c"]) for t in out))
    print("projection  %d B  ~%d tok" % (len(j), len(j) // 4))
    rich = os.path.join(os.path.dirname(path) or '.', 'schema.prg.json')
    if os.path.exists(rich):
        b = os.path.getsize(rich)
        print("schema.json %d B  ~%d tok" % (b, b // 4))
        print("reduction   %.1fx" % (b / len(j)))
        # Report the gap rather than hiding it: a count mismatch here is
        # the emitter's SKIPPED set, and the reader should see it.
        try:
            n = len(json.load(io.open(rich, encoding='utf-8'))["tables"])
            if n != len(out):
                print("skipped     %d (no columns detected; not in the DDL)"
                      % (n - len(out)))
        except Exception:
            pass
else:
    print(json.dumps(out, separators=(',', ':')))
PY
