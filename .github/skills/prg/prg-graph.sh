#!/usr/bin/env bash
# prg-graph.sh — LAYERED symbol-chain grapher.  NO LLM.
#
# Chain effect: seed symbol -> definition(s) -> references ->
# from each referencing SITE, harvest the enclosing symbol -> enqueue ->
# repeat to --depth.  Emits a DOT graph + an edges TSV.
#
# Two engines, layered (--engine auto|lsp|lexical, default auto):
#   Tier LSP (default for .ts/.tsx/.js/.py): prg-lsp.py drives an installed
#     language server (typescript-language-server / jedi-language-server) for
#     SEMANTIC, cross-file references with real enclosing-symbol resolution.
#     rg pre-discovers candidate files; the server distinguishes call vs
#     mention.  This is the precise tier.
#   Tier lexical (auto fallback / --engine lexical / unsupported files like
#     .md): rg --json + jq.  Fast, dependency-free, grep-grade.  Filters
#     import/re-export/comment lines but cannot distinguish call from field.
#
# auto dispatch: try LSP; if prg-lsp.py exits 3 (no server / unsupported
#   language / handshake fail) drop to lexical for that symbol.  So the tool
#   is always useful, and precise when a server is present.
#
# kiss: lexical tier is the floor, LSP tier is the ceiling the user asked for.
#   Neither invokes an LLM.
#
# Usage:
#   prg-graph.sh <symbol> [--seed FILE] [--root "modules agents"] [--depth 1]
#                [--glob '*.ts'] [--engine auto|lsp|lexical]
#                [--out /tmp/prg-graph] [--max-per-symbol 40]
#   --seed FILE : file containing the definition (enables the LSP tier;
#                 without it, auto falls back to lexical for the seed).
#
# Output ($OUT):
#   edges.tsv   src_symbol \t dst_symbol \t path \t line \t kind(def|ref)
#   graph.dot   Graphviz digraph (render: dot -Tsvg graph.dot -o graph.svg)
#   nodes.txt   discovered symbols, one per line
set -euo pipefail

command -v rg >/dev/null || { echo "prg-graph: ripgrep (rg) required" >&2; exit 2; }
command -v jq >/dev/null || { echo "prg-graph: jq required" >&2; exit 2; }

SYMBOL="${1:?usage: prg-graph.sh <symbol> [opts]}"; shift || true
# kiss: default depth=1 (seed -> its callers). Depth>=2 fans out fast; opt in.
ROOT="modules agents"; DEPTH=1; GLOB=""; OUT="/tmp/prg-graph"; MAXPER=40
SEED=""; ENGINE="auto"; PRETTY=0
while [ $# -gt 0 ]; do case "$1" in
  --root)  ROOT="$2"; shift 2;;
  --depth) DEPTH="$2"; shift 2;;
  --glob)  GLOB="$2"; shift 2;;
  --out)   OUT="$2"; shift 2;;
  --seed)  SEED="$2"; shift 2;;
  --engine) ENGINE="$2"; shift 2;;
  --max-per-symbol) MAXPER="$2"; shift 2;;
  --pretty) PRETTY=1; shift;;
  *) echo "prg-graph: unknown arg $1" >&2; exit 2;;
esac; done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LSP="$HERE/prg-lsp.py"
# first ROOT token = LSP workspace root anchor (LSP wants one folder).
LSP_ROOT="$(printf '%s' "$ROOT" | awk '{print $1}')"; [ -d "$LSP_ROOT" ] || LSP_ROOT="$PWD"

# run_lsp <symbol> <seed_file> -> appends edges to $OUT/edges.tsv, returns
# prg-lsp.py's exit (3 => caller should fall back to lexical).
run_lsp() { python3 "$LSP" "$1" "$2" --root "$PWD" --out "$OUT" >/dev/null 2>&1; }

mkdir -p "$OUT"; : > "$OUT/edges.tsv"; : > "$OUT/nodes.txt"
GLOB_ARGS=(); [ -n "$GLOB" ] && GLOB_ARGS=(-g "$GLOB")
# always skip vendored/generated trees
GLOB_ARGS+=(-g '!**/node_modules/**' -g '!**/dist/**' -g '!**/.git/**')

# def-shaped anchors: covers TS (export function/const/class/...) + Python (def/class).
# Arg is the already regex-escaped symbol; interpolate it directly (no sed indirection).
def_pattern() { local s="$1"
  printf 'export\\s+(async\\s+)?(function|const|class|interface|type|enum)\\s+%s\\b|(function|const|class|def)\\s+%s\\b|^\\s*%s\\s*[:=]\\s*(async\\s*)?\\(' "$s" "$s" "$s"
}

# enclosing symbol at a ref site: nearest preceding *named def* line (lexical, cheap).
# One awk pass: for every def-shaped line at or before L, capture the DECLARED name
# (the token right after function/const/class/interface/type/enum/def), keep the last.
enclosing_symbol() { # file line
  local file="$1" line="$2"
  awk -v L="$line" '
    NR>L { exit }
    {
      name=""
      if (match($0, /(function|const|class|interface|type|enum|def)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
        s=substr($0,RSTART,RLENGTH); sub(/^[a-z]+[ \t]+/,"",s); name=s
      } else if (match($0, /^[ \t]*(export[ \t]+)?[A-Za-z_$][A-Za-z0-9_$]*[ \t]*[:=][ \t]*(async[ \t]*)?\(/)) {
        s=$0; sub(/^[ \t]*(export[ \t]+)?/,"",s); sub(/[ \t]*[:=].*/,"",s); name=s
      }
      if (name!="") last=name
    }
    END { if (last!="") print last }
  ' "$file" 2>/dev/null
}

# find a def file for a symbol (first def-anchor hit) — feeds the LSP tier.
# An EMPTY result is legitimate (def lives outside --root, e.g. an imported
# symbol) — rg exits 1 on no-match and `set -o pipefail` would propagate that,
# killing the walk under `set -e` before the ref harvest runs.  Swallow it so
# a missing in-root def yields an empty string, not a fatal error.
def_file() { local S="$1"
  { rg -l --no-messages "$(def_pattern "$S")" "${GLOB_ARGS[@]}" $ROOT 2>/dev/null | head -1; } || true
}

declare -A SEEN
declare -A SEED_OF; [ -n "$SEED" ] && SEED_OF["$SYMBOL"]="$SEED"
LSP_OK=0
queue=("$SYMBOL")
for ((d=0; d<=DEPTH; d++)); do
  next=()
  for sym in "${queue[@]}"; do
    [ -n "${SEEN[$sym]:-}" ] && continue
    SEEN[$sym]=1; echo "$sym" >> "$OUT/nodes.txt"
    S=$(printf '%s' "$sym" | sed 's/[.[\*^$()+?{|]/\\&/g')

    # ---- Tier LSP (default): try semantic references first. ----
    if [ "$ENGINE" != "lexical" ]; then
      sfile="${SEED_OF[$sym]:-}"; [ -z "$sfile" ] && sfile="$(def_file "$S")"
      case "$sfile" in *.ts|*.tsx|*.js|*.jsx|*.mts|*.cts|*.py|*.pyi)
        before=$(wc -l < "$OUT/edges.tsv")
        if run_lsp "$sym" "$sfile"; then
          # harvest new enclosing symbols (col1) as next-depth seeds.
          tail -n +$((before+1)) "$OUT/edges.tsv" | awk -F'\t' '$5=="ref"{print $1"\t"$3}' \
            | while IFS=$'\t' read -r encl epath; do
                [ "${#encl}" -gt 2 ] && [ "$encl" != "«toplevel»" ] && printf '%s\t%s\n' "$encl" "$epath"
              done > "$OUT/.lsp_next.$$" || true
          while IFS=$'\t' read -r encl epath; do
            [ -z "${SEEN[$encl]:-}" ] && { next+=("$encl"); SEED_OF["$encl"]="$epath"; }
          done < "$OUT/.lsp_next.$$"; rm -f "$OUT/.lsp_next.$$"
          LSP_OK=1
          continue   # LSP handled this symbol; skip lexical tier
        fi ;;
      *)
        # forced-lsp on an unsupported ext is a hard error (no silent lexical).
        [ "$ENGINE" = "lsp" ] && { echo "prg-graph: --engine lsp but '$sfile' is not an LSP-supported file type" >&2; exit 3; } ;;
      esac
      # forced-LSP, supported ext, but server/handshake failed -> honest exit 3.
      [ "$ENGINE" = "lsp" ] && { echo "prg-graph: --engine lsp requested but no server produced refs for '$sym'" >&2; exit 3; }
    fi

    # ---- Tier lexical (fallback): rg --json + jq. ----
    # DEFs
    rg --json --no-messages "$(def_pattern "$S")" "${GLOB_ARGS[@]}" $ROOT 2>/dev/null \
      | jq -r --arg s "$sym" 'select(.type=="match") | [$s, "«def»", .data.path.text, (.data.line_number|tostring), "def"] | @tsv' \
      >> "$OUT/edges.tsv" || true

    # REFs -> enclosing symbol becomes a caller edge + next-depth seed
    while IFS=$'\t' read -r path lineno; do
      [ -z "$path" ] && continue
      encl=$(enclosing_symbol "$path" "$lineno")
      encl="${encl:-«toplevel»}"
      printf '%s\t%s\t%s\t%s\tref\n' "$encl" "$sym" "$path" "$lineno" >> "$OUT/edges.tsv"
      # kiss: don't seed noise (loop vars / 1-2 char names) into the next wave.
      if [ "$encl" != "«toplevel»" ] && [ "${#encl}" -gt 2 ] && [ -z "${SEEN[$encl]:-}" ]; then
        next+=("$encl")
      fi
    done < <(rg --json --no-messages "\\b${S}\\b" "${GLOB_ARGS[@]}" $ROOT 2>/dev/null \
              | jq -r 'select(.type=="match")
                       # kiss: drop import / re-export / comment mentions so edges
                       # approximate USE sites, not every lexical occurrence.
                       | (.data.lines.text) as $l
                       | select(($l | test("^\\s*(import|export)\\b")) | not)
                       | select(($l | test("^\\s*(//|\\*|#)")) | not)
                       | [.data.path.text, (.data.line_number|tostring)] | @tsv' \
              | head -n "$MAXPER")
  done
  queue=("${next[@]}")
  [ ${#queue[@]} -eq 0 ] && break
done

# Dedup edges.tsv in place: identical (src,dst,path,line,kind) rows collapse once.
if [ -s "$OUT/edges.tsv" ]; then
  sort -u "$OUT/edges.tsv" -o "$OUT/edges.tsv"
fi

# --pretty (only): column-align the TSV to stderr-preview + assemble graph.dot.
# Without --pretty, DO NOT spend time building DOT (agent-first default).
if [ "$PRETTY" -eq 1 ]; then
  {
    echo "digraph prg {"
    echo '  rankdir=LR; node [shape=box,fontsize=10];'
    awk -F'\t' '$5=="ref" && $1!="" && $2!="" {print "  \""$1"\" -> \""$2"\";"}' "$OUT/edges.tsv" | sort -u
    echo "}"
  } > "$OUT/graph.dot"
  column -t -s $'\t' "$OUT/edges.tsv" 2>/dev/null || cat "$OUT/edges.tsv"
else
  # agent-first default: raw TSV to stdout (also persisted at $OUT/edges.tsv).
  cat "$OUT/edges.tsv"
fi

NEDGES=$(wc -l < "$OUT/edges.tsv" | tr -d ' ')
echo "prg-graph: seed=$SYMBOL depth=$DEPTH engine=$ENGINE  nodes=$(sort -u "$OUT/nodes.txt" | wc -l | tr -d ' ')  edges=$NEDGES" >&2
echo "  $OUT/edges.tsv$([ "$PRETTY" -eq 1 ] && echo "  $OUT/graph.dot")  $OUT/nodes.txt" >&2
[ "$PRETTY" -eq 1 ] && echo "  render: dot -Tsvg $OUT/graph.dot -o $OUT/graph.svg  (if graphviz present)" >&2

# Safe degrade: non-zero ONLY when nothing at all could be produced.
[ "$NEDGES" -eq 0 ] && { echo "prg-graph: no edges produced for '$SYMBOL'" >&2; exit 4; }
exit 0
