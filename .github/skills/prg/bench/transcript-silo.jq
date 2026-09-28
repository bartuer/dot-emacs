# transcript-silo.jq — turn a case's transcript.json into a silo-style
# .prg.jsonl sidecar so it joins the SAME stream-parallel (rg -l over
# *.prg.jsonl) search as every workbook/document in the corpus.
#
# input : one transcript.json — an OBJECT with exactly two keys,
#         .turns[]      = {speaker, text, turn}
#         .tool_calls[] = {after_turn, arguments, by, call, result,
#                          result_truncated, tool}
# output: JSONL, one row per line, in the prg sidecar convention:
#         line 1 is a {"k":"schema",...} WITNESS (how index_folder.sh and
#         rg-based tooling recognise prg output), then meta, then data rows.
#
# THE TRAP (256 item 10.4b, 259 Notes — do NOT rediscover a third time):
# .tool_calls[].arguments is PROSE describing a tool, NOT a command line.
# A grep for a tool name matches English sentences. So tool-call rows carry
# k:"tool_call" and their prose lands in `args` (clearly labelled), while the
# practitioner/interviewer prose a real statement lives in lands in k:"turn"
# rows. A statement search scopes to `select(.k=="turn")`, never to args.
#
# usage:  jq -c -f transcript-silo.jq <case>/transcript.json > \
#             <writable-mirror>/<case>/transcript.json.prg.jsonl
(
  {
    k: "schema",
    doc: "transcript",
    rows: {
      k: "turn|tool_call|meta|schema",
      turn: "1-based turn number (turns rows)",
      speaker: "interviewer|participant (turns rows)",
      text: "turn prose — where a practitioner STATES things (search here)",
      call: "1-based tool-call ordinal (tool_call rows)",
      by: "tool-call actor (tool_call rows)",
      tool: "tool name (tool_call rows)",
      args: "tool-call arguments as prose — PROSE-BEARING, NOT a command line"
    },
    trap: "tool_call.args is English describing a tool, not a command line; a grep for a tool name matches prose. Search .k==\"turn\" .text for practitioner statements, never .args."
  },
  { k: "meta", turns: (.turns | length), tool_calls: (.tool_calls | length) },
  ( .turns[]      | { k: "turn", turn: .turn, speaker: .speaker, text: .text } ),
  ( .tool_calls[] | { k: "tool_call", call: .call, after_turn: .after_turn,
                      by: .by, tool: .tool, args: (.arguments | tostring),
                      result_truncated: .result_truncated } )
)
