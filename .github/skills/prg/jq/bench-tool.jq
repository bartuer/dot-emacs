# contract: emits {tool, verdict} per graded case in an ssg-sim report.json
# input : ONE report object (keys: summary, cases[]) — NOT a stream of cases,
#         so invoke without -n:  jq -f bench-tool.jq report.json
# output: {tool, verdict} per case (null tool -> "NONE", i.e. the model chose
#         no tool or the turn errored — a real outcome, never dropped, or the
#         counts stop summing to summary.total).
#
# aggregate to the pass-rate-by-tool table:
#   jq -f bench-tool.jq report.json \
#     | jq -s 'group_by(.tool)|map({tool:.[0].tool, total:length,
#              passed:map(select(.verdict=="PASS"))|length})'
# or just read `.summary.by_tool`, which server.py now precomputes for every run.
#
# NOTE descriptive, not scored: the evalset carries no expected.tool, so this
# reports which tool the model PICKED, not whether it picked correctly.
.cases[] | { tool: (.actual.tool // "NONE"), verdict: .verdict }
