#!/usr/bin/env python3
# parse.py — the prg PARSE-TIME contract, as a single-source-of-truth model.
#
# WHAT THIS IS
#   The rules that turn ONE user utterance into the SOURCE/TERM/TASK slots
#   (and, for a multi-step workflow, the upstream/downstream Flow) currently
#   live only as PROSE in SKILL.md ("## Parse the utterance first").  This
#   module is the SAME contract expressed as a Pydantic v2 model, so the shape
#   is machine-checkable and can be COMPILED to JSON Schema, minified, and
#   embedded back into SKILL.md as the machine contract alongside the prose.
#
#   No behavior, no parsing logic — just the shape + field docs.  prg stays
#   MODEL-FREE below the loop head; this file is read (as an embedded schema)
#   by the ONE model call, prg-llm.sh.  It never itself calls a model.
#
# PORTABLE: pure stdlib + pydantic, no repo paths, runs from anywhere.
#
# REGENERATE the embedded minified schema (CKP-2 of plan 43):
#   python3 schema/parse.py --emit-schema | jq -c . > schema/parse.schema.min.json
#   then: bash schema/check-embed.sh   # asserts SKILL.md embed == that file
#
# Usage:
#   python3 schema/parse.py --emit-schema    # pretty JSON Schema to stdout, exit 0
#   (validation: callers import Utterance and use .model_validate_json(...) —
#    no --validate subcommand, per the plan's kiss decision.)
from __future__ import annotations

import json
import sys

from pydantic import BaseModel, Field


class Slots(BaseModel):
    """The three-slot decomposition of one utterance (the parse recipe)."""

    source: str = Field(
        ...,
        description=(
            "WHICH corpus -> which prg verb + corpus env.  Parsed from the "
            "source words, not assumed: 'who calls X / follow X' -> repo graph; "
            "'when did X change / last hour' -> trace/log; 'in the L-server "
            "logs ... by model' -> log; 'in this case folder / the delivery / "
            "these files' -> case folder (prg-case.sh ls/stat, inventory FIRST); "
            "a lone symbol -> repo search.  A FOLDER is a legitimate source: "
            "the SOURCE picks the folder, TERM is the file/sheet/column seed, "
            "and TASK routes downstream unchanged."
        ),
    )
    term: list[str] = Field(
        default_factory=list,
        description=(
            "The seed(s) fed to the verb (token / symbol / regex / span).  "
            "Obeys the fuzz-vs-anchor split: FUZZ the separator for a REPO "
            "seed; ANCHOR the identifier when COUNTING over a corpus."
        ),
    )
    task: list[str] = Field(
        default_factory=list,
        description=(
            "The downstream OPERATION on the tool's JSON, routed by the "
            "downstream-op table (find / count / summarize->doc / callers / "
            "when).  A long instruction fuses a SEARCH clause (source+term) "
            "with an OPERATION clause (task); the task must not be dropped."
        ),
    )


class Flow(BaseModel):
    """Upstream/downstream direction — the trajectory spine for a workflow.

    For a single utterance both lists may be empty.  For a multi-turn
    workflow, upstream names what feeds this intent and downstream names what
    this intent feeds — the same connection prg-trace.sh connect derives
    deterministically between turns.
    """

    upstream: list[str] = Field(
        default_factory=list,
        description="Intents/refs that feed THIS one (what came before).",
    )
    downstream: list[str] = Field(
        default_factory=list,
        description="Intents/refs THIS one feeds (what it enables next).",
    )


class Utterance(BaseModel):
    """One parsed user utterance: its text, its slots, and its flow direction."""

    text: str = Field(..., description="The raw user utterance being parsed.")
    slots: Slots = Field(..., description="SOURCE / TERM / TASK decomposition.")
    flow: Flow = Field(
        default_factory=Flow,
        description="Upstream/downstream direction (empty for a lone utterance).",
    )


# Resolve annotations eagerly so the model is usable when this file is loaded
# via importlib (e.g. bench validators) as well as when run as __main__.
Utterance.model_rebuild()


def _emit_schema() -> int:
    print(json.dumps(Utterance.model_json_schema(), indent=2))
    return 0


def _emit_slots_schema() -> int:
    # FLAT {source, term[], task[]} — the parse contract with no Utterance
    # envelope.  Used as the FORCED-TOOL input_schema (plan 43 CKP-6) so the
    # tool call's arguments are shape-identical to the prose/schema arms'
    # JSON output ({source,term,task}), keeping the A/B downstream parser one.
    print(json.dumps(Slots.model_json_schema(), indent=2))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 1 and argv[0] == "--emit-schema":
        return _emit_schema()
    if len(argv) == 1 and argv[0] == "--emit-slots-schema":
        return _emit_slots_schema()
    sys.stderr.write(
        "usage: parse.py [--emit-schema | --emit-slots-schema]\n"
        "  --emit-schema        full Utterance JSON Schema (embedded in SKILL.md)\n"
        "  --emit-slots-schema  flat Slots {source,term,task} for forced-tool arg\n"
        "  (to validate: import Utterance and call .model_validate_json(...))\n"
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
