# trace-lifecycle.jq — harvest FSM keyword rows from the agent lifecycle log.
#
# Input : one agent_lifecycle.jsonl record per line
#           {ts, type, eventType, fromState, toState, convId, sessionId,
#            fsmSeq, ...}
# Args  : --arg FROM <iso>  --arg TO <iso>   (inclusive span)
# Output: one row per record (JSON object per line):
#           {keyword:<eventType|"from->to">, kind:"event",
#            source:"agent.lifecycle", ts, ref:<convId // sessionId>}
#
# Uses .ts (lifecycle) not .timestamp.  Prefers eventType as the keyword;
# falls back to the "fromState->toState" transition so a row is never null.
select(.ts >= $FROM and .ts <= $TO)
| {keyword: ((.eventType
              // ((.fromState // "?") + "->" + (.toState // "?")))),
   kind: "event", source: "agent.lifecycle",
   ts: .ts, ref: (.convId // .sessionId // "unknown")}
