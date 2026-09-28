#!/usr/bin/env bash
# prg-case.sh — inventory a CASE FOLDER: what is here, and how do I read it?
#
# The sixth prg SOURCE, beside repo / log / trace / corpus / silo.  Its corpus
# is ONE case folder — a delivery as it actually arrived, mixed formats:
#
#   files/   9 xlsx + 1 pdf + 2 csv + 1 txt + 1 eml + 1 R + 8 sidecars
#
# WHY THIS EXISTS AND PLAIN `ls` DOES NOT DO IT
# `ls` answers "what files", and that is the question NOBODY has.  The real
# question is "what can I READ, and HOW" — and the answer differs per file:
# a workbook with a fresh sidecar is a jsonl read, the same workbook without
# one is a silo parse, and a csv beside it is neither.  Three access paths,
# indistinguishable from the filename alone.  This resolves all three in one
# pass and says so per file, so a caller never guesses.
#
# THE MEASURED GAP THIS CLOSES.  Across 300 case folders, 2,224 files carry a
# sidecar and 1,071 (32%) do NOT — 545 csv, 355 txt, 39 eml, ~40 R/py/sql.  A
# tool that only reads sidecars is BLIND to a third of every delivery, and
# blind in the worst way: it returns a confident, incomplete answer.  In the
# Delgado case the invisible third is the counts csv, the delivery email, and
# the multiqc summary — i.e. the provenance for the numbers in the workbooks.
#
# !! `source` IS NOT `kind`.  `kind` is what the file IS (workbook, table,
# mail); `source` is how you READ it (index, binary, text).  Route on `source`,
# describe with `kind`.  A caller that switches on the extension will get the
# sidecar case wrong every time.
#
# !! A BARE TEXT FILE IS NOT A MISSING INDEX.  `source=text` is final — do not
# "fix" it by generating a sidecar.  See prg-source.sh.
#
# !! A SIDECAR IS A TEXT FILE -- `rg` IT BEFORE YOU `jq` IT.  The sidecar is
# JSONL, so the rg -l PREFILTER rule from SKILL.md applies to its LINES: rg
# cheaply drops the rows that cannot match, jq parses only survivors.  Measured
# on this corpus (37MB sidecar, 42,403 data rows, one column projected):
#     jq over the whole stream ............ 4.99s
#     rg '"c":4' | jq (identical output) ... 0.17s     29x, byte-identical
# The prefilter is LOSSLESS only when the rg pattern CANNOT be narrower than
# the jq predicate -- rg over-selects, jq decides.  `"c":4` is implied by
# `.c==4`, so it is safe; a pattern on `.v` would NOT be.
#
# !! DO NOT QUOTE 29x AS THIS TOOL'S SPEEDUP.  That is the ceiling for ONE
# column on ONE file -- the narrowest possible prefilter.  `diff` projects
# THREE columns across TWO files and then runs its guards, so rg keeps far
# more lines and the end-to-end win is 2.6x (4795ms -> 1835ms, case-bench.sh).
# Still worth having, but the honest number is the one the bench prints, not
# the microbenchmark that motivated the change.  Selectivity IS the speedup:
# the wider the projection, the less the prefilter buys.
#
# !! A FILE THAT FAILED EXTRACTION IS PIXELS, NOT AN EMPTY FILE -- AND THE
# MODEL, NOT OCR, IS THE READER.  `source=vision` means bin2md tried and left
# a `.failed` sidecar (`degraded` carries why).  Measured: 39 of 1,264 corpus
# pdfs (3%) across 30 cases, ALL verified fonts=0/chars=0 -- genuine scans, not
# a parser bug.  Two rules, both learned by measuring:
#
#   1. DO NOT OCR.  A tesseract `-l eng` pass on a corpus page dropped every
#      checkbox: the source shows "[x] Psychological  [ ] Speech-Language",
#      the OCR text lists all five assessments as clean prose.  "Which were
#      proposed?" then has NO answer in the text, and nothing marks it as
#      lossy -- a confident, incomplete result, which is the failure mode this
#      whole tool exists to prevent.  The vision model read the SAME page and
#      preserved checkbox state.  The corpus is full of exactly the glyphs OCR
#      mangles: 918 sidecars carry non-ASCII, dominated by symbols/math/marks
#      (<=, >=, +/-, ->, mu, degree, Sigma, epsilon, Delta).  A single-language
#      OCR sweep over that is invalid by construction.
#   2. RENDER, THEN LOOK.  `render` writes png pages and stops.  The agent
#      already HAS a vision-capable eye; the tool's job is to hand it pixels,
#      not to guess at glyphs with a second-rate transcriber.  Rendering is
#      model-free (pdftoppm) so the tool keeps the no-LLM contract.
#
# `read` on a vision file EXITS 6 rather than printing nothing -- empty output
# with exit 0 is indistinguishable from "this file says nothing".
#
# Subverbs:
#   ls    DIR [--kind K] [--source S]  -> one inventory record per file
#   stat  DIR [--by kind|source|ext]   -> rolled-up counts
#   read  DIR FILE                     -> that file's content on stdout
#   plan  DIR                          -> per-file command a caller would run
#   diff  DIR A B --sheet S --key C[,C] --val C  -> keyed row diff of 2 books
#
# Exit: 0 ok · 2 bad args/deps · 4 folder absent · 5 unreadable file.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRETTY=0
BY=kind
FILTER_KIND=""
FILTER_SOURCE=""
SHEET=""
KEYC=""
VALC=""
SCOPEC=""

command -v jq >/dev/null || { echo "prg-case: jq required" >&2; exit 2; }

# shared three-way resolver: index / binary / text, plus staleness.
# NOT reimplemented here -- prg-silo.sh reads the same rule from the same file.
# shellcheck source=prg-source.sh
. "$HERE/prg-source.sh"

usage() {
  # --help is JSON so a model needs no second document, and so a caller can
  # branch on it.  Same contract as prg-silo.sh --help.
  jq -n '{
    name: "prg-case.sh",
    desc: "inventory a case folder: one record per file, with its access path. NO LLM.",
    ocr_ruling: "source=vision means text extraction FAILED (see .degraded): the content is pixels. RENDER it and LOOK at the pages with your own vision. DO NOT OCR -- measured: tesseract -l eng dropped every checkbox on a corpus page, yielding confident incomplete prose; 918 corpus sidecars carry non-ASCII (math/symbols/marks) that single-language OCR mangles.",
    subverbs: {
      ls:   "DIR [--kind K] [--source S] -> {path,ext,kind,source,sidecar,bytes,sheets?,media?,peer?}",
      "  media?": "count of embedded images (figures/scans). A sidecar indexes CELLS; a figure is not a cell, so media>0 means part of this file is UNREADABLE by rows/grep -- go look at it another way or say so.",
      "  peer?":  "size of this file'"'"'s near-duplicate family (v2/- Copy/(1)/rev). FLAG ONLY -- never auto-picks a winner: which member supersedes which is stated in prose, not in the bytes. Compare sheets/bytes, then go read the email or Notes tab.",
      stat: "DIR [--by kind|source|ext]  -> {key, n, bytes}",
      read: "DIR FILE                    -> content on stdout (routes on source)",
      plan: "DIR                         -> {path, source, cmd} the command per file",
      diff: "DIR A B --sheet S --key C[,C] --val C -> {key,from,to,status} keyed row diff",
      render: "DIR FILE -> {dir,pages,total_pages,withheld,files} png pages for a VISION read. Caps at PRG_RENDER_MAX=8 pages @ PRG_RENDER_DPI=200 and reports withheld. No OCR, no model."
    },
    source_values: {
      index:  "fresh .prg.jsonl/.prg.md sidecar exists; read that, never the binary",
      binary: "xlsx/pdf/docx with no fresh sidecar; parse on demand via prg-silo.sh",
      text:   "csv/tsv/txt/eml/R/py/sql/json/md; read directly. FINAL, not a to-do.",
      vision: "extraction FAILED (.failed sidecar; see .degraded) -- a scan/image-only file. `render` it and READ THE PAGES YOURSELF. Never OCR; never report it as empty."
    },
    skipped: ["~$* lock files", "*.prg.jsonl / *.prg.md sidecars (reported as a field)"],
    exit: {"0":"ok","2":"bad args/deps","3":"unsupported for this verb","4":"folder absent","5":"unreadable file","6":"no text layer -- render and LOOK (vision), do not OCR"}
  }'
}

args=(); while [ $# -gt 0 ]; do case "$1" in
  --pretty) PRETTY=1; shift;;
  --by)     BY="${2:?--by needs kind|source|ext}"; shift 2;;
  --kind)   FILTER_KIND="${2:?--kind needs a value}"; shift 2;;
  --source) FILTER_SOURCE="${2:?--source needs a value}"; shift 2;;
  --sheet)  SHEET="${2:?--sheet needs a name}"; shift 2;;
  --key)    KEYC="${2:?--key needs col number(s)}"; shift 2;;
  --val)    VALC="${2:?--val needs a col number}"; shift 2;;
  --scope)  SCOPEC="${2:?--scope needs a col number}"; shift 2;;
  -h|--help) usage; exit 0;;
  *) args+=("$1"); shift;;
esac; done
set -- "${args[@]:-}"
SUB="${1:-}"; shift || true

# Validate the SUBVERB before the folder: a mistyped subverb must not report
# "folder absent", which sends the caller looking at the wrong thing.
case "$SUB" in
  ls|stat|read|plan|diff|render) ;;
  ""|-h|--help) usage; exit 0;;
  *) echo "prg-case: unknown subverb '$SUB'" >&2; usage >&2; exit 2;;
esac

DIR="${1:-}"; shift || true
[ -n "$DIR" ] || { echo "prg-case: $SUB needs a DIR" >&2; exit 2; }
[ -d "$DIR" ] || { echo "prg-case: '$DIR' absent" >&2; exit 4; }

# A case folder may BE the case root (with files/ inside) or the files/ dir
# itself.  Callers have both shapes in hand; accept either rather than making
# them remember which.  files/ wins when present.
#
# THE TWO START-POINT FILES ARE SOURCES (256 item 10.4b, 2026-08-26 ruling).
# `summary.md` and `transcript.json` live at the case ROOT, NOT in files/ --
# so descending into files/ turned them into unindexed strays: the delivery's
# own decision record (summary.md) and the interview it came from
# (transcript.json) were invisible to the inventory.  Unlike utterance.json /
# solver/ / answer/ (20 seeded cases only), these two exist for ALL 1,224
# cases -- the single largest source in the corpus.  Keep the case ROOT so the
# inventory can list them as first-class entries beside files/.
CASEROOT=""
if [ -d "$DIR/files" ]; then CASEROOT="$DIR"; DIR="$DIR/files"; fi

# ---- the inventory ----------------------------------------------------------
# One record per readable file.  find -print0 because a real delivery has
# spaces AND parentheses in filenames ("gene list for fig 2 (SR).xlsx"), and
# word-splitting them silently drops files.
inventory() {
  local f base ext kind bytes sheets media degraded
  while IFS= read -r -d '' f; do
    prg_is_sidecar "$f" && continue
    base="$(basename -- "$f")"
    ext="${base##*.}"; [ "$ext" = "$base" ] && ext=""
    kind="$(prg_kind "$f")"
    prg_resolve "$f"
    [ -n "$FILTER_KIND" ]   && [ "$kind" != "$FILTER_KIND" ]     && continue
    [ -n "$FILTER_SOURCE" ] && [ "$PRG_SRC" != "$FILTER_SOURCE" ] && continue
    # stat -L, not stat: this inventory is reached via `find -L` precisely
    # because wpx jails a case as a tree of SYMLINKS.  Plain `stat -c %s` on a
    # symlink reports the length of the LINK TARGET STRING (137 bytes), not the
    # file -- so every workbook in a jailed case reported ~137 bytes instead of
    # 3173254, and `bytes` is exactly the field the decoy/peer comparison in
    # SKILL.md Recipe I tells a caller to rank on.  Silent: 137 is a plausible
    # number, so nothing errors.
    bytes="$(stat -Lc %s -- "$f" 2>/dev/null || echo 0)"
    # sheets only where it is both cheap and meaningful: a jsonl sidecar.
    sheets=null
    case "$PRG_SIDECAR" in
      *.prg.jsonl) sheets="$(prg_sheets "$PRG_SIDECAR")" ;;
    esac
    # !! A SIDECAR IS A CELL INDEX; A FIGURE IS NOT A CELL.  For a workbook,
    # `source=index` silently means "the cells, and nothing else" -- an
    # embedded image is invisible to rg/jq over the sidecar no matter how
    # the query is written.  Measured on the 16943 case: the link-ID ->
    # segment mapping the whole task turns on exists ONLY in
    # xl/media/image1.png, and `rg -c 'image|media|png|drawing'` over the
    # sidecar returns ZERO.  Rare (4 of 6,667 corpus xlsx) but SILENT, which
    # is the whole reason it is worth 3 lines here.  Emitted only when N>0,
    # so output is byte-identical for the 99.9% that carry none.
    media=null
    case "${ext,,}" in
      xlsx|xlsm|docx|pptx)
        media="$(unzip -l -- "$f" 2>/dev/null | grep -c '/media/' || true)"
        [ "${media:-0}" -eq 0 ] && media=null ;;
    esac
    # WHY extraction failed, carried on the record that owns it.  Emitted
    # only when non-empty, so output is byte-identical for files that parsed.
    degraded="$(prg_degraded "$f")"
    jq -nc --arg p "$base" --arg e "${ext,,}" --arg k "$kind" \
           --arg s "$PRG_SRC" --arg sc "$PRG_SIDECAR" \
           --argjson b "$bytes" --argjson sh "$sheets" \
           --argjson md "$media" --arg dg "$degraded" '
      {path:$p, ext:$e, kind:$k, source:$s,
       sidecar: (if $sc == "" then null else ($sc|split("/")|last) end),
       bytes:$b}
      | if $sh == null then . else . + {sheets:$sh} end
      | if $md == null then . else . + {media:$md} end
      | if $dg == ""   then . else . + {degraded:$dg} end'
  # find -L, not find: -type f does NOT match a symlink, so a corpus of
  # symlinks (how wpx jails a case without copying 2.2MB per run) inventoried
  # as ZERO FILES while exiting 0 -- a silent empty result that reads as
  # "empty case" rather than "I cannot see these".  -L follows the link and
  # tests the target, which is what every downstream consumer already assumes.
  #
  # The two start-point SOURCES (summary.md, transcript.json) sit at the case
  # ROOT, one level up from files/.  Splice them into the SAME NUL stream so
  # they get the identical source-resolution and record shape as everything in
  # files/ -- listed by their bare name, so `read`/`plan` find them there too.
  # Only these two: requirement.md / meta.json / sampling.json / utterance.json
  # are harness scaffolding, not the delivery's own sources, and are left out.
  done < <({ find -L "$DIR" -maxdepth 1 -type f -print0
             if [ -n "$CASEROOT" ]; then
               for s in summary.md transcript.json; do
                 [ -f "$CASEROOT/$s" ] && printf '%s\0' "$CASEROOT/$s"
               done
             fi; } | sort -z)
}

emit() { if [ "$PRETTY" = 1 ]; then jq -s .; else cat; fi; }

# ---- near-duplicate grouping ------------------------------------------------
# !! THE DECOY IS THE COMMON CASE, NOT THE EXCEPTION.  Measured over this
# corpus: 1,136 of 1,224 cases (93%) label at least one delivered file
# "unrelated", and 891 of those 5,210 decoy lines match a version-or-copy
# token.  Until now `ls` presented all of them as equals -- on the 16943 case
# it emitted an identical record shape for the real target, a stale v1 with an
# unfunded road widening coded in, and a " - Copy" that is missing a sheet.
#
# !! FLAG ONLY.  NEVER AUTO-PICK.  Which member supersedes which is stated
# ONLY in prose (a Notes tab, an email body) -- it is not in the bytes. On
# 16943 every mechanical heuristic loses: filename recency picks "v2 ... -
# Copy", mtime picks the copy too, and largest-file picks v1.  So this
# reports the GROUP and the discriminators already free in the inventory
# (sheets, bytes) and stops there.  Separating the pair is enough:
#   Maple_Ave_LOS_calcs_v2_JR.xlsx         14 sheets  <- real target
#   Maple_Ave_LOS_calcs_v2_JR - Copy.xlsx  13 sheets  <- missing Maple-Pine PM
# A caller that sees "peer" knows to go read the prose. That is the win.
peers() {
  jq -sc '
    def stem:
      ascii_downcase
      | sub("\\.[a-z0-9]+$"; "")
      | gsub("[ _-]*(- *)?copy"; "")
      | gsub(" *\\([1-9][0-9]?\\)"; "")
      | gsub("[ _-]v ?[0-9]+"; "")
      | gsub("[ _-]+(old|bak|backup|prior|previous|rev|final|draft)"; "")
      | gsub("[ _-]+[a-z]{2,3}$"; "")
      | gsub("[^a-z0-9]+"; "");
    # key includes ext: a photo and its .txt transcription share a stem but
    # are not rival versions of each other (IMG_4471.JPG / IMG_4471.txt).
    [ .[] | . + {_g: ((.path|stem) + "\u0000" + (.ext // ""))} ]
    | group_by(._g)
    | map( length as $n
           | map( . + (if $n > 1 then {peer: $n} else {} end) ) )
    | flatten
    | map(del(._g))
    | sort_by(.path) | .[]'
}

case "$SUB" in
  ls)
    inventory | peers | emit
    ;;

  stat)
    case "$BY" in kind|source|ext) ;; *)
      echo "prg-case: --by must be kind|source|ext" >&2; exit 2;; esac
    inventory | jq -sc --arg by "$BY" '
      group_by(.[$by]) | map({key: .[0][$by], n: length,
                              bytes: (map(.bytes) | add)})
      | sort_by(-.n) | .[]' | emit
    ;;

  plan)
    # The routing table, made explicit.  A caller reads `cmd` instead of
    # re-deriving it -- and re-deriving it is exactly where the sidecar case
    # gets dropped.  Paths are relative to DIR, which is echoed once.
    # The two start-point sources live at the case ROOT, so their cmd must
    # point there, not into files/ -- otherwise `plan` prints a path that does
    # not exist for exactly the two files this ruling just made visible.
    inventory | jq -c --arg d "$DIR" --arg root "${CASEROOT:-$DIR}" '
      (if (.path=="summary.md" or .path=="transcript.json") then $root else $d end) as $base
      | . + {cmd: (
        if .source == "index"  then "prg-silo.sh rows \($base)/\(.path)"
        elif .source == "binary" then "prg-silo.sh rows \($base)/\(.path)   # parses the binary"
        elif .source == "vision" then "prg-case.sh render \($base) \(.path)   # -> png pages; READ THEM YOURSELF, no OCR"
        # transcript.json is source=text but cat is the WRONG verb for it:
        # it is 35 turns of nested JSON, and the thing a caller wants is the
        # TURN a statement was made in.  Route to the sidecar recipe, and say
        # the trap in the cmd itself -- an unscoped grep over this file scores
        # 16 hits of which 9 are the OWN generated code of the agent, not the
        # practitioner (MEASURED, 17709).  Scope to k == turn.
        # !! NO APOSTROPHES IN THIS BLOCK -- the jq program is bash
        # single-quoted, so one apostrophe ends the quote and the script
        # dies with a syntax error at the next elif.
        elif .path == "transcript.json"
          then "jq -c -f bench/transcript-silo.jq \($base)/\(.path)   # -> sidecar; then select(.k==\"turn\") — NEVER grep it unscoped"
        else "cat \($base)/\(.path)"
        end)}' | emit
    ;;

  diff)
    # WHY A SUBVERB AND NOT A ONE-LINER.  "which rows changed between last
    # month's copy and this month's" is THE recurring case-folder question,
    # and it has exactly three ways to go silently wrong.  All three are
    # mechanical, so the tool owns them instead of the caller re-deriving:
    #
    #  1. THE KEY IS NOT UNIQUE.  Joining on a single id column when the id
    #     repeats fabricates changes.  Measured here: 77 of 862 CustIDs map
    #     to 2+ names, so a CustID-only join invents moves that never
    #     happened.  --key takes a COMPOSITE (--key 2,3) for this reason,
    #     and the tool REFUSES to run when the key is not unique in the
    #     reference side (exit 5) rather than emitting plausible garbage.
    #
    #  2. KEY-SCOPE MISMATCH.  Diffing a 13-month file against a 1-month
    #     slice compares different populations and yields a big, wrong,
    #     entirely plausible number.  --scope pins both sides to the same
    #     slice so the comparison is like-for-like.
    #
    #  3. ABSENCE IS NOT A VALUE.  A key missing from one side did not
    #     "change" -- it was not observed.  Those rows are emitted with an
    #     explicit status (only_a / only_b), NEVER folded into changed and
    #     never silently dropped.  A caller that wants only real changes
    #     filters status=="changed"; it cannot get that by accident.
    #
    # Output is one JSON record per key, status ∈ changed|only_a|only_b.
    A="${1:-}"; B="${2:-}"
    [ -n "$A" ] && [ -n "$B" ] || { echo "prg-case: diff needs FILE_A FILE_B" >&2; exit 2; }
    [ -n "$SHEET" ] || { echo "prg-case: diff needs --sheet" >&2; exit 2; }
    [ -n "$KEYC" ]  || { echo "prg-case: diff needs --key" >&2; exit 2; }
    [ -n "$VALC" ]  || { echo "prg-case: diff needs --val" >&2; exit 2; }

    # project ONE side to "key<TAB>value", via the rg prefilter documented in
    # the header.  The rg alternation is built from the very columns jq will
    # test, so it cannot be narrower than the predicate.
    _side() {
      local file="$1" cols pat
      [ -f "$file" ] || file="$DIR/$file"
      [ -f "$file" ] || { echo "prg-case: '$1' absent" >&2; exit 4; }
      prg_resolve "$file"
      [ "$PRG_SRC" = index ] || { echo "prg-case: diff needs an indexed workbook, '$1' is $PRG_SRC" >&2; exit 5; }

      local scol="" sval=""
      if [ -n "$SCOPEC" ]; then
        case "$SCOPEC" in
          *=*) scol="${SCOPEC%%=*}"; sval="${SCOPEC#*=}" ;;
          *) echo "prg-case: --scope must be COL=VALUE (e.g. --scope 1=2024-10)" >&2; exit 2 ;;
        esac
      fi
      cols="$KEYC,$VALC"; [ -n "$scol" ] && cols="$cols,$scol"
      pat="$(printf '%s' "$cols" | tr ',' '\n' | sort -un | sed 's/.*/"c":&[,}]/' | paste -sd'|')"

      rg -N "$pat" "$PRG_SIDECAR" \
        | jq -r --arg sh "$SHEET" 'select(.s==$sh and .r>=2)|"\(.r)\t\(.c)\t\(.v)"' \
        | awk -F'\t' -v kc="$KEYC" -v vc="$VALC" -v sc="$scol" -v sv="$sval" '
            BEGIN { SEP = sprintf("%c", 29) }   # GS; a literal \x1d in a -v
                                                # value is NOT unescaped here.
            { d[$1][$2] = $3 }
            END {
              nk = split(kc, K, ",")
              for (r in d) {
                if (sc != "" && d[r][sc] != sv) continue
                k = ""
                for (i = 1; i <= nk; i++) k = k (i > 1 ? SEP : "") d[r][K[i]]
                print k "\t" d[r][vc]
              }
            }' | sort -u
    }

    ta="$(mktemp)"; tb="$(mktemp)"
    trap 'rm -f "$ta" "$tb"' EXIT
    _side "$A" > "$ta"
    _side "$B" > "$tb"

    # GUARD 0: an EMPTY projection is not "no differences".  A --scope that
    # matches nothing (typo'd value, wrong column) yields two empty sides,
    # which the differ below renders as silence + exit 0 -- indistinguishable
    # from a genuinely stable slice, and wrong in the more dangerous
    # direction.  "No changes" and "I looked at nothing" are different
    # answers, so say which.  (Same reasoning as prg-corpus.sh's exit-5 on an
    # unparseable manifest: absent and broken must not share an exit code.)
    # Only BOTH sides empty is the refusal.  ONE empty side is a legitimate
    # and common query -- scoping to a month only the target has is how you
    # ask "what is new here", and every row correctly comes back only_b.
    # Refusing that would break the question the scope flag exists to answer;
    # it earns a stderr note (so an empty-looking run is explained) and a
    # normal exit.
    if [ ! -s "$ta" ] && [ ! -s "$tb" ]; then
      echo "prg-case: projection is empty on BOTH sides${SCOPEC:+ (--scope $SCOPEC)}; nothing was compared" >&2
      exit 5
    fi
    if [ ! -s "$ta" ] || [ ! -s "$tb" ]; then
      _side_empty=A; [ -s "$ta" ] && _side_empty=B
      echo "prg-case: note: side $_side_empty is empty${SCOPEC:+ under --scope $SCOPEC}; all output will be one-sided" >&2
    fi

    # GUARD 1: the key must be unique on the reference side.  A duplicate key
    # here means the projection cannot represent the row, so every downstream
    # count is unsound -- refuse instead of reporting it.
    dup_a="$(cut -f1 "$ta" | uniq -d | wc -l)"
    if [ "$dup_a" -gt 0 ]; then
      echo "prg-case: --key is not unique in A ($dup_a duplicated keys); add a column to --key" >&2
      exit 5
    fi
    # A duplicate key on the TARGET side is not an error -- it is the signal
    # that the value changed WITHIN that file (a mid-file reclassification,
    # e.g. effective-dated only from a certain month).  Report it as such;
    # this is invisible to a plain A-vs-B compare and is exactly the shape
    # that makes "the numbers look wrong" while every total still ties.
    cut -f1 "$tb" | uniq -d > "$tb.dup" || true

    # A key may hold SEVERAL values on a side (guard 1 forbids that for A, but
    # it is legal and meaningful for B).  Group to a LIST per key rather than
    # INDEX()ing to one: INDEX keeps the LAST duplicate, so with values sorted
    # alphabetically it silently returned "OEM-04" over "NA-01" for one
    # customer and that real reclassification vanished from the diff.  A
    # single-valued key is just a one-element list, so nothing else changes.
    jq -c -n --rawfile a "$ta" --rawfile b "$tb" '
      def bykey($t): $t | split("\n") | map(select(length>0) | split("\t"))
                        | group_by(.[0])
                        | map({key: .[0][0], vs: (map(.[1]) | unique)})
                        | INDEX(.key);
      bykey($a) as $A | bykey($b) as $B
      | ( ($A|keys_unsorted) + ($B|keys_unsorted) | unique )[]
      | . as $k
      | ($A[$k].vs) as $fv | ($B[$k].vs) as $tv
      | {key: ($k | split("\u001d")),
         from: ($fv // null), to: ($tv // null)}
      | . + {status: (if   .from == null then "only_b"
                      elif .to   == null then "only_a"
                      elif (.to - .from) != [] then "changed"
                      else "same" end),
             # true when the key carries >1 value INSIDE the target file --
             # a mid-file (effective-dated) change, not a clean A->B move.
             split_in_b: (($tv // []) | length > 1)}
      | select(.status != "same")' | emit
    rm -f "$tb.dup"
    ;;

  render)
    # PIXELS IN, PNG PAGES OUT.  The ONLY job here is to put something on
    # disk that a VISION-CAPABLE MODEL CAN LOOK AT.  It deliberately does
    # NOT transcribe: see the OCR ruling in the header.  Model-free, like
    # every prg tool except prg-llm.sh -- rendering is pdftoppm, and the
    # LOOKING is the caller's (the agent already has an image-capable eye).
    F="${1:-}"; [ -n "$F" ] || { echo "prg-case: render needs a FILE" >&2; exit 2; }
    [ -f "$F" ] || { [ -f "$DIR/$F" ] && F="$DIR/$F"; } || \
      { [ -n "$CASEROOT" ] && [ -f "$CASEROOT/$F" ] && F="$CASEROOT/$F"; }
    [ -f "$F" ] || { echo "prg-case: '$F' absent" >&2; exit 4; }
    command -v pdftoppm >/dev/null || { echo "prg-case: pdftoppm required" >&2; exit 2; }

    # CAP THE PAGE COUNT.  Corpus max is 63 pages; rendering all of them at
    # 300dpi is ~1.4MB each and every one costs a vision call.  Render a
    # bounded prefix by default and SAY how many were withheld, so a caller
    # never mistakes a truncated render for the whole document.
    RMAX="${PRG_RENDER_MAX:-8}"
    RDPI="${PRG_RENDER_DPI:-200}"
    out="$(mktemp -d "${TMPDIR:-/tmp}/prg-render.XXXXXX")"
    base="$(basename -- "$F")"
    case "${base,,}" in
      *.pdf)
        pages="$(pdfinfo -- "$F" 2>/dev/null | awk '/^Pages:/{print $2}')"
        pages="${pages:-0}"
        pdftoppm -r "$RDPI" -png -f 1 -l "$RMAX" -- "$F" "$out/pg" 2>/dev/null \
          || { echo "prg-case: pdftoppm failed on '$base'" >&2; exit 5; }
        ;;
      *) echo "prg-case: render only handles pdf (got '$base')" >&2; exit 3 ;;
    esac
    # One JSON record: the pages written, and what was NOT written.
    find "$out" -name 'pg*.png' -print0 | sort -z \
      | jq -Rs --arg d "$out" --argjson tot "${pages:-0}" --argjson cap "$RMAX" '
          (. | split("\u0000") | map(select(length>0))) as $f
          | {dir:$d, pages:($f|length), total_pages:$tot,
             withheld: (if $tot > $cap then ($tot - $cap) else 0 end),
             files:$f,
             note:"READ these png files yourself (vision). Do NOT OCR them: OCR silently drops non-ASCII glyphs (checkboxes, math, accents) and returns confident, incomplete text."}'
    ;;

  read)
    F="${1:-}"; [ -n "$F" ] || { echo "prg-case: read needs a FILE" >&2; exit 2; }
    # Accept a bare name or a path; the caller has the name from `ls`.
    # files/ first, then the case ROOT: the two start-point sources
    # (summary.md, transcript.json) `ls` reports live at the root, so `read`
    # must find them there too -- a name `ls` shows that `read` cannot open is
    # an inconsistent tool.
    [ -f "$F" ] || { [ -f "$DIR/$F" ] && F="$DIR/$F"; } || \
      { [ -n "$CASEROOT" ] && [ -f "$CASEROOT/$F" ] && F="$CASEROOT/$F"; }
    [ -f "$F" ] || { echo "prg-case: '$F' absent" >&2; exit 4; }
    prg_resolve "$F"
    case "$PRG_SRC" in
      index)
        case "$PRG_SIDECAR" in
          # cell rows are the ones WITHOUT .k; meta rows carry it.
          *.prg.jsonl) jq -c 'select(has("k")|not)' "$PRG_SIDECAR" ;;
          # bin2md sidecar: line 1 is provenance JSON, text starts line 2.
          *.prg.md)    tail -n +2 "$PRG_SIDECAR" ;;
        esac
        ;;
      binary)
        "$HERE/prg-silo.sh" cells "$F" \
          || { echo "prg-case: cannot read binary '$F'" >&2; exit 5; }
        ;;
      # !! NEVER return "" FOR PIXELS.  Text extraction already failed on this
      # file; emitting empty output with exit 0 is the silent-empty bug that
      # reads as "this file says nothing" instead of "I cannot read this way".
      # Exit 6 is distinct from 5 (unreadable) because this file IS readable --
      # just not as text.  The caller is told the verb that works.
      vision)
        echo "prg-case: '$(basename -- "$F")' has no text layer ($(prg_degraded "$F"))." >&2
        echo "prg-case: it is PIXELS -- run: prg-case.sh render \"$DIR\" \"$(basename -- "$F")\"" >&2
        echo "prg-case: then READ the png pages yourself (vision).  Do NOT OCR." >&2
        exit 6
        ;;
      text) cat -- "$F" ;;
    esac
    ;;
esac
