# contract: reduce a child session events.jsonl into the ORDERED tool chain,
#           each step joined to its completion, with a <=60-char digest.
# input : the full events.jsonl stream, slurped (jq -s) so a single pass can
#         join tool.execution_start to tool.execution_complete on toolCallId.
#         LIVE local schema (same as session-tool.jq):
#           tool.execution_start    .data.{toolName, arguments, toolCallId}
#           tool.execution_complete .data.{toolCallId, success, result.content,
#                                          toolTelemetry.restrictedProperties}
# output: one {n, tool, ok, digest} object per tool.execution_start, in file
#         order.  ok is true/false/null (null = no completion seen).  digest
#         picks the salient arg (skill name / basename(path)) else trims args.
#         Pipe to the caller which renders "n. tool  OK|ERR  digest".
def basename: sub("^.*/"; "");
def clip(n): if (.|length) > n then (.[0:n] + "…") else . end;
def digest(args):
  if   (args.skill? // null) != null then ("skill=" + (args.skill|tostring))
  elif (args.path?  // null) != null then (args.path|tostring|basename)
  elif (args.command? // null) != null then ("cmd=" + (args.command|tostring))
  elif (args.query? // null) != null then ("q=" + (args.query|tostring))
  else (args|tostring) end
  | clip(60);
# build toolCallId -> success map from completions
(map(select(.type=="tool.execution_complete")
     | {key:(.data.toolCallId), value:(.data.success)}) | from_entries) as $ok
| [ .[] | select(.type=="tool.execution_start") ] 
| to_entries[]
| { n:   (.key + 1),
    tool: (.value.data.toolName // "«unknown»"),
    ok:   ($ok[.value.data.toolCallId] // null),
    digest: (.value.data.arguments // {} | digest(.)) }
