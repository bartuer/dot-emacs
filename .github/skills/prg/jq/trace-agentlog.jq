# trace-agentlog.jq — harvest keyword rows from the agent event log.
#
# Input : one agent.log.jsonl record per line
#           {timestamp, level, component, event, file?}
# Args  : --arg FROM <iso>  --arg TO <iso>   (inclusive span)
# Output: up to two rows per record (one JSON object per line):
#           {keyword:<component|event>, kind:"event", source:"agent.log",
#            ts, ref:<file // component>}
#           {keyword:<file-without-lineno>, kind:"path", source:"agent.log",
#            ts, ref:<file>}                       (only when .file present)
#
# The path row strips a trailing :LINE so the keyword is the file, not a
# location; the location survives in ref.  Span filter is a lexicographic
# ISO-timestamp compare (no date parsing).
select(.timestamp >= $FROM and .timestamp <= $TO)
| . as $r
| ( {keyword: (($r.event // $r.component) // "unknown"),
     kind: "event", source: "agent.log",
     ts: $r.timestamp, ref: ($r.file // $r.component // "unknown")} ),
  ( select($r.file != null)
    | {keyword: ($r.file | sub(":[0-9]+$"; "")),
       kind: "path", source: "agent.log",
       ts: $r.timestamp, ref: $r.file} )
