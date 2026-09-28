#!/usr/bin/env bash
# parse-gold-validate.sh — CKP-3.2 conformance: every gold row, converted to
# the Utterance JSON shape, MUST validate against the Pydantic model (proves
# the gold set and the schema agree).  Emits "N/N gold rows valid", exit 0 when
# all valid, 1 otherwise.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gold="${here}/gold-parse.tsv"
schemadir="${here}/../schema"

python3 - "$gold" "$schemadir" <<'PY'
import sys, csv, json, importlib.util, os

gold, schemadir = sys.argv[1], sys.argv[2]

# import the single-source-of-truth model from schema/parse.py
spec = importlib.util.spec_from_file_location("prg_parse", os.path.join(schemadir, "parse.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
Utterance = mod.Utterance

def csvlist(s):
    s = (s or "").strip()
    return [x.strip() for x in s.split(",") if x.strip()]

total = valid = 0
errors = []
with open(gold) as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            errors.append(("MALFORMED", line.strip()))
            continue
        utt, source, term, task = parts[0], parts[1], parts[2], parts[3]
        total += 1
        obj = {
            "text": utt,
            "slots": {"source": source, "term": csvlist(term), "task": csvlist(task)},
        }
        try:
            Utterance.model_validate_json(json.dumps(obj))
            valid += 1
        except Exception as e:
            errors.append((utt[:40], str(e).splitlines()[0]))

for u, e in errors:
    print(f"INVALID: {u} -> {e}", file=sys.stderr)
print(f"{valid}/{total} gold rows valid")
sys.exit(0 if valid == total and total > 0 else 1)
PY
