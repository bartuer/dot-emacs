# contract: keep only records whose ISO-8601 timestamp falls in [$from,$to]
# usage : jq -c --arg from 2026-08-09T14:00 --arg to 2026-08-09T15:00 \
#              -f span-window.jq <file.jsonl>
# input : any line-JSON record carrying a timestamp under .timestamp or .ts
# output: the record unchanged iff $from <= ts <= $to (lexical ISO compare is
#         correct for zero-padded ISO-8601). Records with no timestamp are dropped.
(.timestamp // .ts) as $t
| select($t != null and ($t >= $from) and ($t <= $to))
