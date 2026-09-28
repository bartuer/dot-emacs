#!/usr/bin/env bash
# prg-source.sh — resolve WHERE A FILE'S CONTENT COMES FROM.  Sourceable lib.
#
# Not a SOURCE itself: the shared resolver every file-reading prg tool needs.
# Sourcing gives prg_resolve / prg_kind / prg_is_sidecar / prg_sheets.
#
# WHY THIS EXISTS AND A COPY IN EACH TOOL DOES NOT DO IT
# prg-silo.sh grew the index-first resolver first (plan 256 8.13).  prg-case.sh
# needs the SAME three-way decision over a whole folder.  Two copies of a
# staleness rule is two chances to drift, and drift here fails SILENTLY --
# plausible rows, wrong workbook.  One definition, two callers.  Same pattern
# as prg-when.sh, which prg-trace.sh sources for the shared time normalizer.
#
# THE THREE-WAY DECISION — the index is the default, the binary is the
# fallback, a bare text file is read directly:
#
#   index    a FRESH `<FILE>.prg.jsonl` (cells) or `<FILE>.prg.md` (bin2md
#            text) sidecar exists -> read the sidecar, never touch the binary
#   binary   a parseable binary with no fresh sidecar -> parse on demand
#   text     csv/tsv/txt/eml/R/py/sql/json/md -> read it directly
#
# !! A BARE TEXT FILE IS NEVER INDEXED INTO A NEW SIDECAR.  It is already the
# thing a sidecar would contain; writing one would double the corpus to add
# nothing.  `source=text` is a FINAL answer, not a to-do.
#
# STALENESS IS THE WHOLE RISK.  A sidecar older than its source describes a
# file that no longer exists.  `-nt` is false when EITHER file is missing,
# which is the safe direction: unknown mtime degrades to re-parse, never to
# trusting a stale index.
#
# Exit: sourced, so it never exits -- prg_resolve returns 0 always and reports
# via the PRG_SRC / PRG_SIDECAR globals.  Callers own their own exit codes.
set -uo pipefail

# ---- extension classes ------------------------------------------------------
# `kind` is the SEMANTIC class (what the file is); `source` is the ACCESS path
# (how to read it).  They are independent: a workbook is `binary` without a
# sidecar and `index` with one, but it is a workbook either way.
prg_kind() {
  case "${1,,}" in
    *.xlsx|*.xlsm|*.xlsb|*.xls)  echo workbook ;;
    *.docx|*.doc|*.rtf|*.odt)    echo doc ;;
    *.pptx|*.ppt)                echo slides ;;
    *.pdf)                       echo pdf ;;
    *.csv|*.tsv)                 echo table ;;
    *.eml|*.msg)                 echo mail ;;
    *.r|*.py|*.sql|*.sh|*.js)    echo code ;;
    # A NOTEBOOK IS CODE, NOT A MYSTERY FILE.  Measured: 20 .ipynb in the
    # corpus, 0 with sidecars, every one classified `other`.  That is not
    # cosmetic -- `other` is in the degraded-route arm below that sends a
    # file to VISION, so a JSON notebook could be photographed as pixels
    # instead of read.  A reach diff caught it: the teacher on
    # soc-15-2031.00 calibrates from calib.ipynb and wpx never opened it,
    # reproducibly (n=2).
    *.ipynb)                     echo code ;;
    *.json|*.jsonl|*.yaml|*.yml) echo data ;;
    *.txt|*.md|*.log)            echo text ;;
    *)                           echo other ;;
  esac
}

# Files that are NOT inventory records in their own right.
#   ~$foo.xlsx      Excel lock file -- an artifact of a program being OPEN,
#                   not a deliverable.  Counting it inflates every total and
#                   it disappears the moment the author closes the book.
#   *.prg.jsonl     our own sidecars.  A sidecar is an ACCESS PATH to its
#   *.prg.md        source file, already reported as that file's `sidecar`
#                   field.  Listing it separately double-counts the corpus.
#   *.prg.md.failed A FAILED sidecar is still a sidecar -- it belongs to its
#                   source file and is reported as that file's `degraded`
#                   field.  Listing it as a record of its own invented a
#                   phantom file with ext=failed / kind=other / source=text,
#                   and `plan` then told the caller to `cat` a provenance
#                   stub as if it were delivery content.
prg_is_sidecar() {
  case "$(basename -- "$1")" in
    '~$'*)                              return 0 ;;
    *.prg.jsonl|*.prg.md)               return 0 ;;
    *.prg.jsonl.failed|*.prg.md.failed) return 0 ;;
    *)                                  return 1 ;;
  esac
}

# ---- why an extraction failed ----------------------------------------------
# Echoes the bin2md `degraded` reason for FILE, or "" when it extracted fine.
# A failed sidecar is not noise: it is the ONLY record that this file was seen
# and could not be turned into text.  Without it a scanned PDF is
# indistinguishable from one nobody tried, and the caller silently answers
# from the files that happened to parse.
prg_degraded() {
  local f
  for f in "$1.prg.md.failed" "$1.prg.jsonl.failed"; do
    [ -s "$f" ] || continue
    jq -r '.degraded // empty' -- "$f" 2>/dev/null && return 0
  done
  return 0
}

# ---- the resolver -----------------------------------------------------------
# Sets PRG_SRC (index|binary|text) and PRG_SIDECAR (path, or empty).
# Warns on stderr when a sidecar is stale, then falls back to the binary.
prg_resolve() {
  local file="$1" kind sc
  kind="$(prg_kind "$file")"
  PRG_SRC=""; PRG_SIDECAR=""

  # 1. a fresh sidecar wins over everything, whatever the kind.
  for sc in "${file}.prg.jsonl" "${file}.prg.md"; do
    [ -s "$sc" ] || continue
    if [ "$file" -nt "$sc" ]; then
      echo "prg-source: sidecar STALE (source newer), ignoring '$sc'" >&2
      continue
    fi
    PRG_SIDECAR="$sc"; PRG_SRC=index; return 0
  done

  # 2. EXTRACTION WAS TRIED AND FAILED -> the content is PIXELS, not text.
  # A scanned pdf has no text layer, so `binary` is a lie: it routes the
  # caller to prg-silo.sh, which exits 5.  `vision` says the only way in is
  # to LOOK at it.  Measured: 39 of 1,264 corpus pdfs (3%), across 30 cases.
  #
  # !! ROUTE ON THE *REASON*, NOT MERELY ON "IT FAILED".  Only EmptyDocument
  # (and a genuinely broken render) means pixels.  UnsupportedFormat does NOT:
  # the corpus .kmz/.npz that carry it are ZIP CONTAINERS, and calling them
  # "vision" would repeat the very lie this branch exists to fix -- sending a
  # caller to render an archive that has no pages.  They stay `binary`, which
  # is honest: unwrap them (unzip -> doc.kml / .npy), do not photograph them.
  case "$(prg_degraded "$file")" in
    "") ;;
    EmptyDocument*|ExtractionFailed*)
      case "$kind" in
        pdf|slides|doc|other) PRG_SRC=vision; return 0 ;;
      esac ;;
  esac

  # 3. no fresh sidecar: a binary must be parsed, text is read as-is.
  case "$kind" in
    workbook|doc|slides|pdf)  PRG_SRC=binary ;;
    table|mail|code|data|text) PRG_SRC=text ;;
    *)
      # Unknown extension: ASK, don't assume.  grep -I calls a file binary
      # when it contains NUL; that is the same test `rg` uses to skip files,
      # so an unknown-but-readable file stays readable instead of being
      # silently dropped or silently parsed as a workbook.
      if grep -qI . -- "$file" 2>/dev/null; then PRG_SRC=text; else PRG_SRC=binary; fi
      ;;
  esac
  return 0
}

# ---- cheap sheet count ------------------------------------------------------
# !! COUNTERMEASURE, DO NOT "OPTIMIZE" BACK TO grep.  This used to count
# `"k":"sheet"` rows with grep, justified as "43x faster than jq".  Both
# halves were wrong against a bin2md sidecar:
#   1. WRONG ANSWER.  k=sheet is a SILO-era meta row; bin2md never emits one
#      (its families are schema|file|table|af|chart|cell -- see `bin2md
#      --help`).  So the count was 0 for EVERY workbook, silently.  Sheet
#      names survive as `.s` on the rows themselves, so the honest count is
#      the number of DISTINCT `.s` values.
#   2. NOT FASTER.  Measured on the 58MB FY24_v6 sidecar: jq 1833ms vs
#      `grep -o '"s":"..."' | sort -u` 3985ms.  grep is 2.2x SLOWER here
#      because `.s` is on ~every row, so it never gets the early-exit the
#      old meta-row-only pattern enjoyed -- and it must scan the whole file
#      either way.  grep is also WRONG by one: the k=schema row's own doc
#      text contains the literal `"s":"section: sheet name..."`, which
#      `sort -u` happily counts as a 7th sheet (6 real).  Skipping line 1
#      fixes the count but costs 4439ms -- slower still.
# jq is therefore both correct and fastest; keep it.
# !! `grep -c` EXITS 1 ON ZERO MATCHES, and it has ALREADY printed "0" by
# then, so `grep -c ... || echo 0` emits "0\n0" -- two lines, not a number.
# The sole caller feeds this to `jq --argjson`, which rejects it with
# "invalid JSON text" and kills the whole `ls` verb at exit 2.  Measured:
# 60 of 60 corpus case folders failed, i.e. the verb was 100% dead for any
# case containing a sidecar with no k=sheet row (every csv/txt/pdf, so
# effectively all of them).  Keep the `|| true` form -- it suppresses the
# exit status WITHOUT adding a second line.
prg_sheets() {
  local n
  # The sole caller feeds this to `jq --argjson`, which rejects anything that
  # is not exactly one integer -- an absent/unreadable sidecar prints nothing
  # and a failed jq prints nothing, so normalize before returning.
  n="$(jq -r '.s // empty' -- "$1" 2>/dev/null | sort -u | wc -l)"
  printf '%s\n' "${n:-0}"
}

# `return` succeeds only in a sourced context.  This file has no CLI.
(return 0 2>/dev/null) || {
  echo "prg-source.sh is a library; source it, don't run it" >&2; exit 2
}
