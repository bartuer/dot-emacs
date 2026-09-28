#!/usr/bin/env bash
# prg-when.sh — the ONE time normalizer shared by every prg source that queries
# a time-sensitive corpus (telemetry lenses, git log, session_state events).
# It turns a HUMAN / RELATIVE time expression into canonical ISO-8601 Z so the
# lenses stay a dumb lexicographic string compare (no per-script date parsing).
#
# Accepts (verified against GNU coreutils `date`):
#   · anything `date -u -d` already parses: "1 hour ago", "today", "yesterday",
#     "last hour", "2 days ago", a bare clock "08:00", a full ISO stamp, "now".
#   · colloquialisms `date` REJECTS (verified: "noon", "this morning") via a
#     tiny alias table applied BEFORE date.
#   · a git-relative ref ("HEAD", "HEAD~2", "abc1234", "@^") -> resolved to the
#     commit time with `git -C <repo> log -1 <ref> --format=%cI` (needs --repo).
#
# Usage:
#   prg-when.sh <expr> [--repo DIR]         # -> one ISO-8601 Z line
#   prg-when.sh --span "FROM..TO" [--repo]  # -> "FROM_ISO<TAB>TO_ISO"
#   source prg-when.sh                      # -> prg_when / prg_span functions
#
# Exit: 0 ok · 2 bad args / unresolvable expression.
set -euo pipefail

WHEN_REPO="${PRG_WHEN_REPO:-}"

# canonical output form: ISO-8601 with milliseconds and a Z suffix, matching the
# telemetry lenses (which compare on `.timestamp` / `.ts` strings of this form).
_iso() { date -u -d "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null; }

# alias table: words `date` cannot parse -> a clock time it can.  Applied to the
# WHOLE lowercased expression so "this morning" and "morning" both resolve.
_dealias() {
  local e; e="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$e" in
    noon)                 echo "12:00" ;;
    midnight)             echo "00:00" ;;
    "this morning"|morning)     echo "09:00" ;;
    "this afternoon"|afternoon) echo "15:00" ;;
    "this evening"|evening)     echo "18:00" ;;
    tonight|night)        echo "21:00" ;;
    *) return 1 ;;
  esac
}

# a git ref: HEAD (optionally with ~N / ^N), "@", or a 7-40 char hex sha.
_looks_like_gitref() {
  case "$1" in
    HEAD|HEAD[~^]*|@|@[~^]*) return 0 ;;
    *) printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{7,40}$' ;;
  esac
}

# prg_when <expr> -> ISO-8601 Z on stdout (exit 2 if unresolvable).
prg_when() {
  local expr="${1:-}"
  [ -n "$expr" ] || { echo "prg-when: empty time expression" >&2; return 2; }
  local out

  # 1) git-relative ref: resolve to its commit time (needs a repo).
  if _looks_like_gitref "$expr"; then
    local repo="${WHEN_REPO:-.}"
    local ct
    ct="$(git -C "$repo" log -1 "$expr" --format=%cI 2>/dev/null || true)"
    if [ -n "$ct" ]; then
      out="$(_iso "$ct")" && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
    echo "prg-when: cannot resolve git ref '$expr' in repo '${repo}'" >&2
    return 2
  fi

  # 2) plain: let `date` try first (covers most human/relative forms).
  out="$(_iso "$expr")" && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }

  # 3) colloquialism: map through the alias table, then date again.
  local aliased
  if aliased="$(_dealias "$expr")"; then
    out="$(_iso "$aliased")" && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  fi

  echo "prg-when: unrecognized time expression '$expr'" >&2
  return 2
}

# prg_span "FROM..TO" -> "FROM_ISO<TAB>TO_ISO" (both normalized).
prg_span() {
  local span="${1:-}"
  case "$span" in
    *..*) : ;;
    *) echo "prg-when: bad span '$span' (want FROM..TO)" >&2; return 2 ;;
  esac
  local from="${span%%..*}" to="${span##*..}"
  local fi ti
  fi="$(prg_when "$from")" || return 2
  ti="$(prg_when "$to")"   || return 2
  printf '%s\t%s\n' "$fi" "$ti"
}

# ---- CLI (skipped when sourced) ---------------------------------------------
# `return` succeeds only in a sourced context; if it does, stop here so the
# functions above are all the caller gets.
(return 0 2>/dev/null) && return 0

MODE="when"; ARG=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) WHEN_REPO="$2"; shift 2 ;;
  --span) MODE="span"; ARG="$2"; shift 2 ;;
  -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) ARG="$1"; shift ;;
esac; done

[ -n "$ARG" ] || { echo "prg-when: need a time expression (or --span FROM..TO)" >&2; exit 2; }
case "$MODE" in
  when) prg_when "$ARG" ;;
  span) prg_span "$ARG" ;;
esac
