# contract: normalize a transcript.jsonl turn to a flat, harvestable row
# input : one transcript record {content, role, ts, turn}
# output: {turn, ts, role, text} where text = content coerced to a string
#         (content may be a string or an array of parts). Used by prg-trace.sh
#         harvest to scan turns within a time span.
{
  turn: .turn,
  ts:   .ts,
  role: .role,
  text: (if (.content|type) == "string" then .content
         elif (.content|type) == "array"
           then (.content | map(.text? // .content? // (tostring)) | join(" "))
         else (.content|tostring) end)
}
