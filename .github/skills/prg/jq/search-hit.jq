# search-hit.jq — rg native --json ("type":"match") -> flat search-hit contract.
# OUTPUT (one object per hit): {path, line, col, keyword, content, index}
#   path    = matched file (rg .data.path.text)
#   line    = 1-based line number (rg .data.line_number)
#   col     = 1-based column of the first submatch (rg .start + 1)
#   keyword = the matched text of the first submatch
#   content = the matched line, trailing newline stripped
#   index   = 1-based ordinal of this hit across the whole stream
# Drops rg's begin/end/summary records; only "match" records survive, and
# `index` re-numbers 1..N over the SURVIVING hits (not rg's raw JSONL lines).
# Feed with:  rg --json <pat> <root> | jq -n -c -f search-hit.jq
foreach inputs as $r (
  0;
  if $r.type == "match" then . + 1 else . end;
  if $r.type == "match" then
    ($r.data) as $d
    | ($d.submatches[0]) as $s
    | {
        path:    $d.path.text,
        line:    $d.line_number,
        col:     ($s.start + 1),
        keyword: $s.match.text,
        content: ($d.lines.text | rtrimstr("\n")),
        index:   .
      }
  else empty end
)
