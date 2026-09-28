# contract: extract tool names offered/used in an L-server request json
# input : one L-server request object (keys: max_tokens, messages, system, tools)
# output: {tool_name} per declared tool (.tools[].function.name) — pipe through
#         `sort | uniq -c` for {tool_name,n}. Emits nothing when .tools is absent.
(.tools // [])[]
| { tool_name: (.function.name // .name // "«unnamed»") }
