# contract: flatten a trace.otel.jsonl record to its identity fields
# input : one trace.otel record {sessionId, timestamp, type, trace:{groupId,name,traceId,...}}
# output: {sessionId, ts, type, traceId, groupId, name} — the connectable keys
#         (traceId links a span to a trajectory). Fields absent -> null.
{
  sessionId: .sessionId,
  ts:        .timestamp,
  type:      .type,
  traceId:   (.trace.traceId // null),
  groupId:   (.trace.groupId // null),
  name:      (.trace.name // null)
}
