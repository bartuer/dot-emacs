#!/usr/bin/env bash
# parse-ab.sh — CONTROLLED A/B: does an embedded JSON Schema teach the parse
# contract at least as well (accuracy) and as fast (p50) as the prose tables?
#
# Four arms isolate two independent variables — INPUT (what teaching text is
# in the user turn) and OUTPUT (free-form vs schema-forced tool call):
#
#   arm            input (user turn)        output
#   ------------   ----------------------   ---------------------------------
#   prose          prose body + utterance   free-form JSON
#   prose-slim     SLIM prose + utterance   free-form JSON
#   schema         schema body + utterance  free-form JSON
#   forced         BARE utterance           forced tool (slots schema)
#   forced+prose   prose body + utterance   forced tool (slots schema)
#
# Clean A/Bs this gives us:
#   · prose  vs prose-slim    → teaching-text LENGTH only (plan 41 CKP-8.3):
#                               same contract, duplication + meta-commentary
#                               removed, one worked example kept.
#                               3,376 B -> 2,288 B (-32%).
#   · prose  vs schema        → contract REPRESENTATION (both free-form out)
#   · prose  vs forced+prose  → OUTPUT ENFORCEMENT only (same rich input)
#   · forced vs forced+prose  → INPUT examples only (same forced output)
# The forced tool's arguments ARE the flat {source,term,task}; all arms are
# scored by the identical downstream parser + a per-arm parse_fail_n.
#
# Scoring (plan 43 SLOT SCORING decision):
#   per-row  = mean of 3 slot scores
#     SOURCE = exact match (1/0)
#     TERM   = set-F1  = 2|P n G| / (|P|+|G|)   (1.0 when both empty)
#     TASK   = set-F1  (same)
#   arm accuracy = mean per-row over all gold rows.
#
# Emits one JSON line per arm:
#   {arm, n, slot_accuracy, p50_ms, p95_ms, parse_fail_n}
#
# Exit codes: 0 ok · 2 usage/dep · 3 proxy unreachable (same contract as
# every prg model path — degrade, do not crash, do not fake a 0 score).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRG="$(cd "$HERE/.." && pwd)"

GOLD="$HERE/gold-parse.tsv"
while [ $# -gt 0 ]; do
  case "$1" in
    --gold) GOLD="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "parse-ab: unknown arg $1" >&2; exit 2 ;;
  esac
done

# ---- exit-3 gate: proxy must be reachable, else degrade (do NOT fake a score)
if ! "$PRG/prg-llm.sh" --probe >/dev/null 2>&1; then
  echo "parse-ab: proxy unreachable (prg-llm.sh --probe != 0) — cannot run A/B" >&2
  exit 3
fi

PROSE_PROMPT="$(cat "$HERE/prompt.prose.txt")"
SLIM_PROMPT="$(cat "$HERE/prompt.prose.slim.txt")"
SCHEMA_PROMPT="$(cat "$HERE/prompt.schema.txt")"
FORCED_SCHEMA="$PRG/schema/slots.schema.min.json"
export PROSE_PROMPT SLIM_PROMPT SCHEMA_PROMPT FORCED_SCHEMA

python3 - "$GOLD" "$PRG/prg-llm.sh" <<'PY'
import sys, os, csv, json, subprocess, time, re

gold_path, llm = sys.argv[1], sys.argv[2]
# arm value encodes BOTH variables:
#   "<body>"                        → free-form output, <body> in user turn
#   "FORCED:<schema>"               → forced tool, BARE utterance (no body)
#   "FORCED:<schema>\x00<body>"     → forced tool, <body> ALSO in user turn
FORCED = os.environ["FORCED_SCHEMA"]
ARMS = {"prose":        os.environ["PROSE_PROMPT"],
        "prose-slim":   os.environ["SLIM_PROMPT"],
        "schema":       os.environ["SCHEMA_PROMPT"],
        "forced":       "FORCED:" + FORCED,
        "forced+prose": "FORCED:" + FORCED + "\x00" + os.environ["PROSE_PROMPT"]}

def csvset(s):
    return {x.strip().lower() for x in (s or "").split(",") if x.strip()}

# ---- load gold ------------------------------------------------------------
gold = []
with open(gold_path) as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 4:
            continue
        gold.append({"text": p[0], "source": p[1].strip().lower(),
                     "term": csvset(p[2]), "task": csvset(p[3])})

def set_f1(pred, gold):
    if not pred and not gold:
        return 1.0
    if not pred or not gold:
        return 0.0
    inter = len(pred & gold)
    return (2 * inter) / (len(pred) + len(gold))

def extract_json(txt):
    # tolerate a stray code fence even though we asked for none
    txt = txt.strip()
    txt = re.sub(r'^```(?:json)?', '', txt).strip()
    txt = re.sub(r'```$', '', txt).strip()
    m = re.search(r'\{.*\}', txt, re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None

def call(body, utterance):
    # forced arms: schema rides the REQUEST as a forced tool (prg-llm.sh
    # --tool-schema forces a tool whose parameters ARE the flat slots schema
    # and prints the tool call's arguments JSON).  An optional body AFTER the
    # NUL sentinel is still delivered in the user turn (forced+prose arm), so
    # enforcement can be tested with the SAME rich input as the prose arm.
    if body.startswith("FORCED:"):
        rest = body[len("FORCED:"):]
        schema_path, _, fbody = rest.partition("\x00")
        user = (fbody + "\n\nUtterance to parse:\n" + utterance) if fbody else utterance
        argv = [llm, user, "--tool-schema", schema_path]
    else:
        # NOTE: the L-server proxy IGNORES the OpenAI `system` role (verified: a
        # system-only "reply BANANA" instruction is dropped).  So the contract-
        # teaching BODY (the A/B variable) is delivered in the USER turn instead
        # — applied identically to the prose/schema arms.  The utterance is
        # appended after the body under a neutral header.
        user = body + "\n\nUtterance to parse:\n" + utterance
        argv = [llm, user]
    t0 = time.time()
    out = subprocess.run(argv, capture_output=True, text=True)
    dt = (time.time() - t0) * 1000.0
    return out.stdout, dt, out.returncode

results = []
for arm, system in ARMS.items():
    row_scores, lats, fails = [], [], 0
    for g in gold:
        text, dt, rc = call(system, g["text"])
        lats.append(dt)
        if rc == 3:
            print("parse-ab: proxy went away mid-run", file=sys.stderr)
            sys.exit(3)
        obj = extract_json(text)
        # Accept BOTH the flat {source,term,task} (from the shared tail) and the
        # nested {slots:{source,...}} shape (the schema arm naturally emits the
        # schema's own layout).  Identical acceptance for both arms.
        slots = obj.get("slots") if isinstance(obj, dict) and isinstance(obj.get("slots"), dict) else obj
        if slots is None or "source" not in slots:
            fails += 1
            row_scores.append(0.0)
            continue
        p_src = str(slots.get("source", "")).strip().lower()
        p_term = {str(x).strip().lower() for x in (slots.get("term") or [])}
        p_task = {str(x).strip().lower() for x in (slots.get("task") or [])}
        s_src = 1.0 if p_src == g["source"] else 0.0
        s_term = set_f1(p_term, g["term"])
        s_task = set_f1(p_task, g["task"])
        row_scores.append((s_src + s_term + s_task) / 3.0)

    n = len(gold)
    acc = sum(row_scores) / n if n else 0.0
    slat = sorted(lats)
    p50 = slat[(len(slat) - 1) // 2] if slat else 0.0
    i95 = max(0, int(len(slat) * 0.95) - 1)
    p95 = slat[i95] if slat else 0.0
    line = {"arm": arm, "n": n,
            "slot_accuracy": round(acc, 4),
            "p50_ms": round(p50, 1), "p95_ms": round(p95, 1),
            "parse_fail_n": fails}
    print(json.dumps(line))
    results.append(line)
PY
