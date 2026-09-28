# contract: emit {tool} per tool.execution_start event in a session-state
#           events.jsonl stream; caller aggregates -> {tool,n}.
# input : one ~/.copilot/session-state/*/events.jsonl record, shape
#         {data, id, parentId, timestamp, type}.  Tool name lives at
#         .data.toolName (verified live: bash 17518, view 4182, grep 877 ...).
#         This is the LIVE local schema — NOT the trace.otel / transcript
#         shape the older otel-span.jq / transcript-turns.jq lenses assume
#         (those corpora are absent locally; their gold cases must SKIP).
# output: {tool} for each tool.execution_start (null -> "«unknown»").
#         Pipe through `sort | uniq -c`, or filter one tool for a gold count.
select(.type == "tool.execution_start")
| { tool: (.data.toolName // "«unknown»") }
