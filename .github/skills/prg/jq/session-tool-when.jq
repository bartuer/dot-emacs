# contract: TIME-AWARE variant of session-tool.jq — emit {tool, day} per
#           tool.execution_start in a session-state events.jsonl stream, so a
#           caller can filter the trajectory by a DATE/SPAN, not just by tool.
# input : one ~/.copilot/session-state/*/events.jsonl record
#         {data, id, parentId, timestamp | ts, type}.  The local schema uses
#         `.timestamp` on tool events and `.ts` on session lifecycle rows;
#         we accept either so the lens never drops a row on the ts key alone.
# output: {tool, day} for each tool.execution_start.  `day` is the ISO date
#         prefix (YYYY-MM-DD) — a coarse, stable time bucket the bench can
#         `select(.day==...)` or a runtime span filter can range over.
select(.type == "tool.execution_start")
| { tool: (.data.toolName // "«unknown»"),
    day:  ((.timestamp // .ts // "") | .[0:10]) }
