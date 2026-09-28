# contract: emits {model} per L-server *.response.json; caller aggregates -> {model,n}
# input : one L-server response object (keys: model, requestId, ...)
# output: {model} (null model -> "«unknown»") — pipe through `sort | uniq -c` or
#         `jq -s 'group_by(.model)|map({model:.[0].model,n:length})'` to get {model,n}.
{ model: (.model // "«unknown»") }
