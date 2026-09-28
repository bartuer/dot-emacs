# trace-otel.jq — harvest keyword rows from an OTel trajectory export.
#
# Input : one trace.otel.jsonl record per line
#           {sessionId, timestamp, type, trace:{traceId,name,groupId,
#            startTime?, durationMs?}}
# Args  : --arg FROM <iso>  --arg TO <iso>   (inclusive span, lexicographic)
# Output: stable keyword rows, one JSON object per line:
#           {keyword, kind:"span", source:"trace.otel", ts, ref:<traceId>}
#
# Only records carrying a real name+traceId (in THIS export, type
# "round_snapshot") contribute; empty spans/session_start are skipped so the
# harvest never emits null keywords.  Span filter is a string compare on the
# ISO-8601 Z timestamp, so it needs no date parsing.
select(.timestamp >= $FROM and .timestamp <= $TO)
| select((.trace.name // null) != null and (.trace.traceId // null) != null)
| {keyword: .trace.name, kind: "span", source: "trace.otel",
   ts: (.trace.startTime // .timestamp), ref: .trace.traceId}
