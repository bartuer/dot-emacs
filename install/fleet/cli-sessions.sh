#!/usr/bin/env bash
# cli-sessions.sh -- keep ~/.copilot/sessions true, and attach by name.
#
# The registry (box|session|plan|model|launched_utc|group) is WRITTEN at launch by
# bin/plan-route.sh, but launch-time rows go stale: sessions die, humans
# start CLIs by hand.  --refresh rebuilds it from the fleet itself: every
# tmux session whose pane runs `copilot` on any reachable box.
#
# Usage:
#   cli-sessions.sh --refresh        # rescan fleet, rewrite registry, print it
#   cli-sessions.sh --list           # print registry as-is (no network)
#   cli-sessions.sh                  # htop view (39 H): ACT column, sorted, counts
#                                    #   header; `watch -c -n 2 cli`.  Starts
#                                    #   the --feed (fleet-top --stream ->
#                                    #   $REG.top) lazily; it exits 300s after
#                                    #   the last read (CLI_FEED_IDLE)
#   cli-sessions.sh --all            # + finished (EXIT, last CLI_ALL_DAYS=2)
#                                    #   and non-tmux live rows -> $REG.all
#                                    #   (+GROUP: vterm members show here)
#   cli-sessions.sh --enlist [CHAN] [-n]  # 41 G.3: join every IDLE session in no
#                                    #   room to CHAN (default: busiest dispatched)
#   cli-sessions.sh --version|-V     # print CLI_VERSION (bump it on EVERY change)
#   cli-sessions.sh -V all           # version on every box: spots boxes not yet pulled
#   cli-sessions.sh <T>              # attach: ssh <box> -t tmux a -t <session>
#   cli-sessions.sh all | <T>,<T>    # ONE local window, a tiled pane per session
#   cli-sessions.sh <T> <message..>  # TYPE <message> into the CLI + Enter
#   cli-sessions.sh all <message..>  # ... into every session
#     <T> = full session name, a unique prefix (36 -> 36-agent-room), a
#           BOX name (cj06 -> every session on cj06), or a room GROUP (chan:
#           room_implment -> every session joined to it).  Lists: a,b or "a, b".
#   Registry field 6 = GROUP (chans joined, from room.sh rooms; ROOM_SH=...).
#   CLI_W=n caps the SESSION column (default 28, middle cut a~z).
#     `/exec_plan [words]` with no plan path -> `/exec_plan <own plan> [words]`.
# Grid = LOCAL tmux session "cli-grid"; each pane ssh-attaches one remote
# session, 6 panes per page (window; CLI_PAGE=n to change).  Prefix is C-a
# so C-b still reaches the remote tmux.  Keys (after C-a):
#   z        toggle tiled <-> full screen (zoom) for the current pane
#   Tab/S-Tab next/prev pane, STAYING zoomed -> full-screen carousel (repeatable)
#   o  q N   next pane / show numbers then press N to jump   (or mouse click)
#   n  p  w  next / prev page / pick page from a tree      d  detach
# The ~/.bashrc `cli` function is a thin wrapper around this script.
set -uo pipefail
CLI_VERSION=2026.09.28.3 # YYYY.MM.DD.N -- bump on every edit of this file

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)   # via /usr/local/bin/cli symlink too
REG="${PLAN_REGISTRY:-$HOME/.copilot/sessions}"
# Box list: CLI_IPS (fleet-ips.json) if readable, else the Host aliases in
# ~/.ssh/config (wildcards dropped) -- so a copy outside the repo still works
# (dot-emacs vendors this as install/cli -> /root/local/bin/cli).
FH="${FLEET_HOME:-$HOME/.fleet}"   # 41 A.1: fleet facts live here; bin/ is the committed seed
IPS="${CLI_IPS:-$FH/fleet-ips.json}"; [ -r "$IPS" ] || IPS="$HERE/fleet-ips.json"

boxes() {
    if [ -r "$IPS" ]; then
        jq -r '.regions[].boxes|to_entries[]|select(.value!=null and .value!="")|.key' "$IPS"
    else
        awk '/^Host /{for(i=2;i<=NF;i++) if($i !~ /[*?]/) print $i}' "$HOME/.ssh/config" 2>/dev/null
    fi | sort -uV
}

# planof <name> <args>: the plan file for a session, else its name-derived stem.
# shellcheck disable=SC2016
PLANOF='
planof() {
  local s=$1 a=$2 p n f w
  p=$(printf "%s" "$a" | grep -oE "/exec_plan [^ ]+" | cut -d" " -f2)
  # room/--resume launches carry no /exec_plan arg: take the plan number from
  # the session name (box+repo+39,fleet,top+task | c02_32-firewall) and map it
  # to the one plan file with that number, else show the name-derived stem.
  if [ -z "$p" ]; then
    n=$(printf "%s" "$s" | sed -nE "s/^[^+]+\+[^+]+\+([^+]+).*/\1/p" | tr , .)
    [ -n "$n" ] || n=$(printf "%s" "$s" | sed -nE "s/^[a-z]+[0-9]+[_.]([0-9]+[-.].*)/\1/p")
    f=$(ls /workspace/*/.github/REPL/"${n%%[-.]*}".*.org.txt 2>/dev/null)
    for w in $(printf "%s" "${n#*[-.]}" | tr -- "-." "  "); do   # 2 repos share 32.*: narrow by words
      [ "$(printf "%s\n" "$f" | grep -c .)" -gt 1 ] && f=$(printf "%s\n" "$f" | grep -F -- "$w")
    done
    [ -n "$n" ] && { [ "$(printf "%s\n" "$f" | grep -c .)" = 1 ] && p=$f || p=$n; }
  fi
  printf "%s" "${p:--}"
}
'

# Runs ON the box; prints box|session|plan|model|created for copilot panes.
# shellcheck disable=SC2016
PROBE="$PLANOF"'
b=$1
tmux list-panes -a -F "#{session_name}|#{pane_pid}|#{session_created}" 2>/dev/null |
while IFS="|" read -r s pid c; do
  # the pane process itself may be copilot (tmux new -s X "copilot ...", alias t),
  # else its child (a shell pane that ran copilot)
  a=$(ps -ww -p "$pid" -o args= 2>/dev/null | grep -m1 "copilot") && k=$pid ||
  { a=$(ps -ww --ppid "$pid" -o args= 2>/dev/null | grep -m1 "copilot") || continue; k=; }
  m=$(printf "%s" "$a" | grep -oE -- "--model [^ ]+" | cut -d" " -f2)
  # STATE from the last event of this CLI events.jsonl (inuse.<pid>.lock of
  # the pane child or its child: `node copilot` wraps the native binary).
  st=- ; l= ; for q in ${k:-$(ps --ppid "$pid" -o pid= | grep -m1 .)} ; do
    for q2 in $q $(ps --ppid "$q" -o pid=); do
      l=$(ls "$HOME"/.copilot/session-state/*/inuse."$q2".lock 2>/dev/null | head -1)
      [ -n "$l" ] && break 2; done; done
  e=${l%/*}/events.jsonl
  if [ -n "${l:-}" ] && [ -f "$e" ]; then
    # 41 G.1: session.* bookkeeping after a turn_end (compaction, context,
    # model, mode, info, task_complete) is not work: skip it (41-F10)
    z=$(tail -c 65536 "$e" | grep -vE "\"type\":\"session\.(compaction_start|compaction_complete|context_changed|permissions_changed|model_change|mode_changed|info|task_complete|truncation)\"" | tail -n 3)
    idle=$(( $(date +%s) - $(stat -c %Y "$e") ))
    case $(printf "%s" "$z" | tail -n1 | grep -oE "\"type\":\"[^\"]+" | cut -d\" -f4) in
      assistant.turn_end) st=WAIT ;;
      session.error) st=ERR ;;
      permission.requested) st=PERM ;;
      tool.execution_start) printf "%s" "$z" | tail -n1 | grep -q "\"toolName\":\"ask_user\"" && st=ASK || st=BUSY ;;
      *) st=BUSY ;;
    esac
    [ $st = BUSY ] && [ $idle -gt ${CLI_STALL_S:-600} ] && st=STALL
    st="$st $( [ $idle -ge 3600 ] && echo $((idle/3600))h || { [ $idle -ge 60 ] && echo $((idle/60))m || echo ${idle}s; } )"
  fi
  pd=${l##*/inuse.}; pd=${pd%.lock}   # copilot pid = the lock pid (39 G2.1 join key with orch-collect)
  printf "%s|%s|%s|%s|%s|%s|%s\n" "$b" "$s" "$(planof "$s" "$a")" "${m:--}" "$(date -u -d @"$c" +%FT%TZ)" "$st" "${pd:--}"
done | sort -u -t"|" -k2,2'

# Runs ON the box (cli --all): session-state dirs that PROBE cannot see, as
# box|session|plan|model|launched|group|exit (39-D8).  A dir whose inuse lock
# pid is alive and has no tmux ancestor is a non-tmux live row, exit "-"
# (vterm, 39-F8).  A named dir with no live lock, written in the last
# CLI_ALL_DAYS, is finished: exit = events.jsonl mtime (39-F7).
# shellcheck disable=SC2016
STATE="$PLANOF"'
b=$1; d=${CLI_STATE_DIR:-$HOME/.copilot/session-state}; days=${CLI_ALL_DAYS:-2}
intmux() { local q=$1; while [ "${q:-1}" -gt 1 ]; do
  case $(cat /proc/"$q"/comm 2>/dev/null) in tmux*) return 0;; esac
  q=$(awk "/^PPid:/{print \$2}" /proc/"$q"/status 2>/dev/null); done; return 1; }
for w in "$d"/*/workspace.yaml; do
  [ -f "$w" ] || continue; sd=${w%/workspace.yaml}; e=$sd/events.jsonl
  s=$(sed -nE "s/^name: *//p" "$w" | head -1 | tr -d "\"|" | cut -c1-80)
  x=; live=
  for l in "$sd"/inuse.*.lock; do
    pid=${l##*/inuse.}; pid=${pid%.lock}
    { tr "\0" " " < /proc/"$pid"/cmdline; } 2>/dev/null | grep -q copilot \
      && { live=1; intmux "$pid" || x=-; }   # a reused pid is not live
  done
  if [ -n "$live" ]; then [ "$x" = - ] || continue; s=${s:-${sd##*/}}
  else [ -n "$s" ] && [ -f "$e" ] && [ -n "$(find "$e" -mmin -$((days*1440)))" ] || continue
       x=$(date -u -r "$e" +%FT%TZ); fi
  m=$(tail -c 200000 "$e" 2>/dev/null | grep -oE "\"(currentModel|model)\":\"[^\"]+\"" | tail -1 | cut -d\" -f4)
  t=$(sed -nE "s/^created_at: *//p" "$w" | head -1)
  t=$(date -u -d "$t" +%FT%TZ 2>/dev/null || date -u -r "$w" +%FT%TZ)
  printf "%s|%s|%s|%s|%s|-|%s\n" "$b" "$s" "$(planof "$s" "$s")" "${m:--}" "$t" "$x"
done'

# cli -V all: runs ON the box.  READ the installed file, never run it: a
# pre-version cli would take -V as a session target.
# shellcheck disable=SC2016
VERPROBE='f=$(readlink -f "$(command -v cli)") || { echo "(no cli)"; exit; }
v=$(sed -n "s/^CLI_VERSION=\([^ ]*\).*/\1/p" "$f")
echo "cli ${v:-old@$(git -C "$(dirname "$f")" log -1 --format=%h --abbrev=7 -- "$f" 2>/dev/null)}"'

probe_one() {   # <box> [SCRIPT var name, default PROBE]
    local b="$1" v="${2:-PROBE}"; local P="${!v}"
    if [ "$b" = "${PLAN_SELF:-}" ] || [ "$(hostname -I 2>/dev/null | awk '{print $1}')" = \
         "$(jq -r --arg b "$b" '.regions[].boxes[$b]//empty' "$IPS" 2>/dev/null)" ]; then
        bash -c "$P" _ "$b"
        [ "$v" = PROBE ] && python3 "$HERE/orch-collect.py" --rows "$b" 2>/dev/null
    else
        # ControlMaster: first probe pays the handshake (10s for c14/c15 via
        # ProxyJump c16), `watch cli -r` frames reuse the socket for 10 min.
        # PROBE also ships orch-collect on stdin in the SAME ssh (39-D12, G2.1):
        # its `@box|pid|hitl|question|last_msg` lines give WI/LAST their pid join.
        local OC=/dev/null C="CLI_ALL_DAYS=${CLI_ALL_DAYS:-2} bash -c $(printf %q "$P") _ $b"
        [ "$v" = PROBE ] && { OC=$HERE/orch-collect.py; C="$C </dev/null; python3 - --rows $b 2>/dev/null"; }
        timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR \
            -o ControlMaster=auto -o ControlPersist=600 -o "ControlPath=/tmp/cli-mux-%C" "$b" \
            "$C" < "$OC" 2>/dev/null
    fi
    return 0   # unreachable box must not abort xargs (255 = stop)
}
export -f probe_one; export PROBE STATE IPS VERPROBE HERE

refresh() {
    mkdir -p "$(dirname "$REG")"; [ -e "$REG" ] || : > "$REG"   # first run: the f6 carry-over awk reads $REG
    # field 6 (STATE) goes to $REG.state, never $REG: 5-field readers (plan-route) stay intact
    # $REG f6 = the OLD GROUP until regroup rewrites it: a frame drawn during the
    # background sweep (caf4741) showed GROUP `-` on every row (39-F28)
    # per-run temp files: two `watch cli -r` loops must not rm each other's raw
    local raw t1 t2 t3 oc rl; raw=$(mktemp "$REG.raw.XXXX"); t1=$(mktemp "$REG.tmp.XXXX"); t2=$(mktemp "$REG.st.XXXX")
    t3=$(mktemp "$REG.top.XXXX"); oc=$(mktemp "$REG.oc.XXXX"); rl=$(mktemp "$REG.rl.XXXX")
    { [ -x "$ROOM_SH" ] && "$ROOM_SH" last > "$rl" 2>/dev/null; } &   # WI source, in parallel with the sweep
    boxes | xargs -P 16 -I{} bash -c 'probe_one {}' > "$oc"
    grep -v '^@' "$oc" | sort -t'|' -k1,1V -k2,2 > "$raw" \
        && awk -F'|' -v OFS='|' 'FILENAME != "-" { g[$1 "|" $2] = $6; next }
               { k = $1 "|" $2; print $1, $2, $3, $4, $5, (k in g && g[k] != "") ? g[k] : "-" }' \
               "$REG" - < <(cut -d'|' -f1-5 "$raw") > "$t1" 2>/dev/null && mv "$t1" "$REG" \
        && awk -F'|' -v OFS='|' '{print $1,$2,$6,$7}' "$raw" > "$t2" && mv "$t2" "$REG.state"
    wait
    toprows "$raw" <(grep '^@' "$oc") "$rl" > "$t3" && mv "$t3" "$REG.top"
    rm -f "$raw" "$t1" "$t2" "$t3" "$oc" "$rl"
    regroup
}

# $REG.top (39-D12): box|session|wi|last, a separate file so 5-field readers stay
# intact.  <raw> PROBE rows (field 7 = copilot pid), <oc> orch-collect `@box|pid|
# kind|question|msg`, <rl> `room.sh last` JSON keyed by from = tmux session name.
# WI = `<kind> <wi>` of that session's latest room line (progress -> prog).
# LAST = `?<question>` while a hitl is pending, else last_msg, else the room body.
toprows() {
    # no --wi on the post: take `NN/X` or "plan NN [Phase X]" from its body, so a
    # session that switched plan mid-work shows it (cj06 "taking plan 40 Phase C").
    { jq -r '(.wi // ((.body // "") | (capture("(?<![0-9])(?<w>[0-9]{2}/[A-Z][A-Za-z0-9.]*)").w
                // (capture("[Pp]lan (?<n>[0-9]{2})(?: [Pp]hase (?<p>[A-Z]))?") | .n + (if .p then "/" + .p else "" end))
                // null))) as $w |
              [.from, ((.kind | sub("^progress$"; "prog")) + (if $w then " " + $w else "" end)),
              (.body // "" | gsub("[|\\s]+"; " "))] | "R|" + join("|")' "$3" 2>/dev/null
      sed 's/^@/O|/' "$2"; sed 's/^/P|/' "$1"; } |
    awk -F'|' -v OFS='|' '
        $1 == "R" { wi[$2] = $3; rb[$2] = $4; next }
        $1 == "O" { k = $2 "|" $3; q[k] = ($4 != "-") ? "?" $5 : ""; ms[k] = $6; next }
        $1 == "P" { k = $2 "|" $8; l = q[k]; if (l == "") l = ms[k]; if (l == "") l = rb[$3]
                    print $2, $3, (($3 in wi) ? wi[$3] : "-"), (l == "" ? "-" : l) }'
}

# cli --all: live rows padded to 7 fields (39-D8) + STATE rows -> $REG.all,
# live first, then finished by EXIT desc.
refresh_all() {
    refresh
    { awk -F'|' -v OFS='|' '{g=(NF>=6&&$6!="")?$6:"-"; print $1,$2,$3,$4,$5,g,"-"}' "$REG"
      boxes | xargs -P 16 -I{} bash -c 'probe_one {} STATE'
    } | sort -s -t'|' -k7,7r | awk -F'|' '$7=="-"{print;next}{f[++n]=$0}END{for(i=1;i<=n;i++)print f[i]}' \
      > "$REG.all.tmp" && mv "$REG.all.tmp" "$REG.all"
    regroup "$REG.all"   # vterm rows (session_stub) have a GROUP too (39 F.1)
}
list_all() {
    [ -s "$REG.all" ] || { echo "(no copilot sessions in $REG.all)"; return 0; }
    printf '%-6s %-28s %-16s %-21s %-21s %-13s %s\n' BOX SESSION MODEL LAUNCHED EXIT GROUP PLAN
    while IFS='|' read -r b s p m t g x _; do
        printf '%-6s %-28s %-16s %-21s %-21s %-13s %s\n' "$b" "$s" "$m" "$t" "$x" "$(mid "${g:--}" 13)" "${p##*/}"
    done < "$REG.all"
}

# Field 6 = GROUP (39-D8): the room chans each session has joined, comma list,
# from ONE `room.sh rooms` (one JSON per chan, .joined = session names).  No
# room.sh (vendored copy) or hubs down -> every group is `-`; never fails.
ROOM_SH="${ROOM_SH:-$HERE/room.sh}"
regroup() {   # [file, default $REG]
    local F=${1:-$REG}
    [ -s "$F" ] || return 0
    local t; t=$(mktemp "$F.tmp.XXXX")
    { [ -x "$ROOM_SH" ] && "$ROOM_SH" rooms 2>/dev/null |
        jq -r '.chan as $c | (.joined // [])[] | "\(.)\t\($c)"' 2>/dev/null; true; } |
    awk -F'\t' 'ph == 1 { g[$1] = ($1 in g) ? g[$1] "," $2 : $2; next }
        { n = split($0, f, "|"); if (n < 5) n = 5; f[6] = ($2 in g) ? g[$2] : "-"; if (n < 6) n = 6
          o = f[1]; for (i = 2; i <= n; i++) o = o "|" f[i];  print o }' ph=1 - ph=2 FS='|' "$F" > "$t" \
        && mv "$t" "$F"
    rm -f "$t"; return 0
}

# middle cut to <= w chars: dot-emacs-3~cli-bundle.  ASCII `~`, not `…`: bash
# printf and mawk pad by BYTES, a 3-byte glyph would skew the columns.
mid() { local s=$1 w=$2 h; if [ ${#s} -gt "$w" ]; then h=$(((w - 1) / 2)); s="${s:0:h}~${s: -$((w - 1 - h))}"; fi; printf '%s' "$s"; }

# `watch -c cli`: stdout is watch's pipe, not a tty (MEASURED procps 4.0.4: no
# WATCH_* env, -t 1 false).  Parent or grandparent comm = watch -> colour.
# /proc reads only: `cli` itself must not fork per frame (H.3 <50 ms).
under_watch() {
    local p=$PPID n c
    for n in 1 2; do
        read -r c < "/proc/$p/comm" 2>/dev/null || return 1; [ "$c" = watch ] && return 0
        read -r _ _ _ p _ < "/proc/$p/stat" 2>/dev/null || return 1
    done; return 1
}

# The htop view (39-D15/D16): ONE awk over $REG, $REG.state, $REG.top -- no
# network, no fork per row.  ACT from the feeder's raw state (top f5) + since
# (f6, epoch; aged HERE so STALL/IDLE flip with no feeder write) + owes (f7),
# else PROBE's $REG.state.  Sorted ASK<HITL<PERM<ERR<STALL<IDLE<DEAD<GONE<-, then
# registry order.  POSIX awk only: mawk boxes run this too.
acts() {   # <session width> <last width> <colour 0|1> <feed age> <work width>; stdin box|session|WORK
    awk -F'|' -v w="$1" -v c="$2" -v col="$3" -v fa="$4" -v ww="$5" -v now="$EPOCHSECONDS" \
        -v fed="${CLI_FED:-1}" -v stall="${CLI_STALL_S:-600}" -v owe="${CLI_IDLE_OWE_S:-120}" -v free="${CLI_FREE_S:-600}" -v raw="${ACTS_RAW:-0}" '
    function mid(s, n,  h) { if (length(s) <= n) return s; h = int((n - 1) / 2)
        return substr(s, 1, h) "~" substr(s, length(s) - (n - 1 - h) + 1) }
    function secs(x) { return x ~ /h$/ ? x * 3600 : x ~ /m$/ ? x * 60 : x + 0 }
    function ago(x) { return x >= 3600 ? int(x / 3600) "h" : x >= 60 ? int(x / 60) "m" : x "s" }
    FILENAME == "-" { wk[$1 "|" $2] = $3; next }
    FILENAME == ARGV[2] { st[$1 "|" $2] = $3; next }
    FILENAME == ARGV[3] { k = $1 "|" $2; wi[k] = $3; la[k] = $4; fs[k] = $5; si[k] = $6; ow[k] = $7; next }
    { k = $1 "|" $2; s0 = fed ? fs[k] : ""; a = "-"
      if (s0 != "") {
          age = (si[k] ~ /^[0-9]+$/) ? now - si[k] : -1; if (age < 0) age = -1
          if (s0 == "ASK" || s0 == "PERM" || s0 == "ERR" || s0 == "DEAD" || s0 == "GONE") a = s0
          else if (s0 == "BUSY" && age > stall) a = "STALL"   # STATE keeps "BUSY 15m": 8 cols
          else if (s0 == "WAIT" && ow[k] == "1" && age > owe) a = "IDLE"
          else if (s0 == "WAIT" && ow[k] != "1" && $6 == "-" && age > free) a = "IDLE"   # 41 G.2: free, in no room
          sv = (age >= 0 && s0 != "DEAD" && s0 != "GONE") ? s0 " " ago(age) : s0
      } else {
          sv = (k in st && st[k] != "") ? st[k] : "-"; split(sv, q, " ")
          if (q[1] == "ASK" || q[1] == "PERM" || q[1] == "ERR" || q[1] == "STALL") a = q[1]
          else if (q[1] == "WAIT" && $6 == "-" && secs(q[2]) > free) a = "IDLE"   # 41 G.2 (no feed)
      }
      # 39 I.6: WAIT whose latest room post is a hitl = waits on a human IN THE ROOM,
      # not the terminal (ASK); before this it read IDLE (c05 41acb3, 2026-09-27)
      if ((a == "-" || a == "IDLE") && wi[k] ~ /^hitl/ && (s0 == "WAIT" || (s0 == "" && sv ~ /^WAIT/))) a = "HITL"
      r = index("ASK HITL PERM ERR STALL IDLE DEAD GONE -", a); n[r]++; if (a != "DEAD" && a != "GONE") live++
      if (!($1 in bx)) { bx[$1]; nb++ }
      l = (k in la && la[k] != "") ? la[k] : "-"; if (length(l) > c) l = substr(l, 1, c - 1) "~"
      g = ($6 == "") ? "-" : $6; v = (k in wk && wk[k] != "") ? wk[k] : "-"
      row[++m] = sprintf("%-5s %-5s %-" w "s %-8s %-13s %-" ww "s %s", a, mid($1, 5), mid($2, w),
                         mid(sv, 8), mid(g, 13), mid(v, ww), l)
      rk[m] = r; ac[m] = a; rw[m] = a "|" $1 "|" $2 "|" g }
    END {
      if (raw) { for (j = 1; j <= m; j++) print rw[j]; exit }   # 41 G.3: full names for --enlist
      R = col ? "\033[1;31m" : ""; Y = col ? "\033[33m" : ""; D = col ? "\033[2m" : ""; Z = col ? "\033[0m" : ""
      printf "ASK %d HITL %d PERM %d ERR %d STALL %d IDLE %d DEAD %d GONE %d|%d live/%d box|feed %s\n",
          n[1], n[5], n[10], n[15], n[19], n[25], n[30], n[35], live, nb, fa   # <= 80 cols (HITL added: box, no pipe pad)
      printf "%-5s %-5s %-" w "s %-8s %-13s %-" ww "s %s\n", "ACT", "BOX", "SESSION", "STATE", "GROUP", "WORK", "LAST"
      split("1 5 10 15 19 25 30 35 40", o, " ")
      for (i = 1; i <= 9; i++) for (j = 1; j <= m; j++) if (rk[j] == o[i]) {
          p = (ac[j] ~ /^(ASK|HITL|PERM|ERR)$/) ? R : (ac[j] ~ /^(STALL|IDLE)$/) ? Y : (ac[j] ~ /^(DEAD|GONE)$/) ? D : ""
          print p row[j] (p == "" ? "" : Z) }
    }' - "$REG.state" "$REG.top" "$REG" 2>/dev/null
}

# One line per row on 80 cols (39 D.3b): BOX 5, SESSION CLI_W (28), STATE 8
# ($REG.state, 39-F17), GROUP 13, MODEL 8 (claude- dropped), LAUNCHED DD HH:MM
# (UTC), PLAN = the rest of $COLUMNS (head cut, keeps the number).  Names in attach and
# targets stay full; only the display is cut.
# WORK (39 G3): `<plan stem>/<item> <kind>` from WI `<kind> [NN/item]` and the
# session plan <p>.  The plan is the wi's own NN (cj07 in 36.agent.room.u2 works
# 39/H), else the session's plan; the stem is looked up once per NN.
declare -A STEM=()
work() {   # <wi> <session plan path> -> $W (a variable: no fork per row, H.3)
    local wi=$1 p=$2 k w nn f st d
    d=${p%/*}; [ "$d" != "$p" ] || d=$HERE/../.github/REPL
    p=${p##*/}; p=${p%.org.txt}; [ -n "$p" ] || p=-
    [ "$wi" = - ] && { W=$p; return; }
    k=${wi%% *}; w=; [ "$wi" = "$k" ] || w=${wi#* }
    if [[ $w == [0-9]*/* ]]; then
        nn=${w%%/*}
        if [ -z "${STEM[$nn]+x}" ]; then
            # same repo first: 39 is 39.fleet.top in cluster but 39.mount.research elsewhere
            f=; for f in "$d"/"$nn".*.org.txt "$HERE"/../.github/REPL/"$nn".*.org.txt /workspace/*/.github/REPL/"$nn".*.org.txt; do
                [ -e "$f" ] && break; f=; done   # a loop, not ls: ls re-sorts (OfficeAgent < cluster)
            st=${f##*/}; STEM[$nn]=${st%.org.txt}; [ -n "${STEM[$nn]}" ] || STEM[$nn]=$nn
        fi
        W="${STEM[$nn]}/${w#*/} $k"
    else
        [ "$p" = - ] && { W=$k; return; }
        if [ -n "$w" ]; then W="$p/$w $k"; else W="$p $k"; fi
    fi
}

list() {   # [-v]: 39-D11 default BOX SESSION STATE GROUP WORK LAST (WI -> WORK, 39 G3); -v = MODEL LAUNCHED PLAN view
    [ -s "$REG" ] || { echo "(no copilot sessions in $REG)"; return 0; }
    local w=${CLI_W:-28} b s p m t g _ l st wi la c ww
    if [ "${1:-}" != -v ]; then
        c=${COLUMNS:-$( [ -t 1 ] && tput cols 2>/dev/null || echo 120)}
        # 80 cols with ACT (39 H, +6): SESSION 13, WORK 10, LAST 20.  No CLI_W: SESSION
        # takes what LAST's 20 + WORK's 10 leave, within [13, 28]
        [ -n "${CLI_W:-}" ] || { w=$((c - 37 - 10 - 20)); [ $w -le 28 ] || w=28; [ $w -ge 13 ] || w=13; }
        # WORK (39 G3) = the rest minus LAST's 20, within [10, 24]
        ww=$((c - 6 - 5 - w - 8 - 13 - 5 - 20)); [ $ww -le 24 ] || ww=24; [ $ww -ge 10 ] || ww=10
        c=$((c - 6 - 5 - w - 8 - 13 - ww - 5)); [ "$c" -ge 4 ] || c=4   # LAST = the rest, cut with `~`
        local col=0 fa=-; { [ -t 1 ] || [ -n "${CLI_COLOR:-}" ] || under_watch; } && [ "${CLI_COLOR:-}" != 0 ] && col=1
        [ -f "$REG.top" ] && fa=$(( EPOCHSECONDS - $(stat -c %Y "$REG.top") ))s
        # 41-F7: f5/f6 are the feeder's LAST word; once it exits (CLI_FEED_IDLE) a BUSY
        # row froze and aged into a false STALL (MEASURED c03: idle on turn_end, shown
        # STALL).  Trust them only if a live feeder wrote $REG.top since it started.
        local fd=0 fp=; [ "${CLI_FEED:-1}" = 0 ] && fd=1   # no feeder by design (tests): f5 as given
        { read -r fp < "$REG.feed.pid"; } 2>/dev/null
        [ -n "$fp" ] && kill -0 "$fp" 2>/dev/null && [ "$REG.top" -nt "$REG.feed.pid" ] && fd=1
        [ -e "$REG.top" ] || : > "$REG.top"   # 41-F6: first run, `<` fails before 2>/dev/null applies
        # WORK per row in bash (work() -> $W, no subshell), handed to acts on fd 3
        declare -A WI=(); while IFS='|' read -r b s wi _; do WI[$b\|$s]=$wi; done < "$REG.top" 2>/dev/null
        while IFS='|' read -r b s p _; do work "${WI[$b\|$s]:--}" "$p"; printf '%s|%s|%s\n' "$b" "$s" "$W"; done < "$REG" \
            | CLI_FED=$fd acts "$w" "$c" "$col" "$fa" "$ww"
        return 0
    fi
    printf "%-5s %-${w}s %-8s %-13s %-8s %-8s %s\n" BOX SESSION STATE GROUP MODEL LAUNCHED PLAN
    while IFS='|' read -r b s p m t g _; do
        st=$(awk -F'|' -v b="$b" -v s="$s" '$1==b&&$2==s{print $3;exit}' "$REG.state" 2>/dev/null)
        l=${t#*-*-}; l=${l%:*}; l=${l/T/ }; p=${p##*/}; p=${p%.org.txt}
        printf "%-5s %-${w}s %-8s %-13s %-8s %-8s %s\n" "$(mid "$b" 5)" "$(mid "$s" "$w")" \
            "$(mid "${st:--}" 8)" "$(mid "${g:--}" 13)" "$(mid "${m#claude-}" 8)" "$(mid "$l" 8)" "$p"   # PLAN is last: full stem, never cut
    done < "$REG"
}

# field 2 of the registry row for <T>: exact name, else UNIQUE prefix.
row() {
    local r
    r=$(awk -F'|' -v s="$1" '$2==s' "$REG" 2>/dev/null)
    [ -n "$r" ] || r=$(awk -F'|' -v s="$1" 'index($2,s)==1' "$REG" 2>/dev/null)
    [ -n "$r" ] || r=$(awk -F'|' -v s="$1" '$7=="-" && index($2,s)==1' "$REG.all" 2>/dev/null)  # vterm
    # a~z = the list's middle-cut display name: head prefix + tail suffix (paste-back)
    case $1 in *'~'*) [ -n "$r" ] || r=$(awk -F'|' -v h="${1%%\~*}" -v t="${1#*\~}" \
        'index($2,h)==1 && length($2)>=length(h)+length(t) && substr($2,length($2)-length(t)+1)==t' "$REG" 2>/dev/null);; esac
    [ "$(printf '%s' "$r" | grep -c .)" = 1 ] && printf '%s\n' "$r"
}
resolve() {   # <T> -> row, refreshing once on a miss
    local r; r=$(row "$1")
    [ -n "$r" ] || { refresh; r=$(row "$1"); }
    [ -n "$r" ] || { echo "cli: no unique session '$1'" >&2; list >&2; return 1; }
    printf '%s\n' "$r"
}
lookup() { resolve "$1" 2>/dev/null | cut -d'|' -f1; }
boxrows() {   # <box> -> every session row on that box (a box name is a target)
    awk -F'|' -v b="$1" '$1==b' "$REG" 2>/dev/null
}
grouprows() {   # <group> -> every session row that joined room chan <group>
    awk -F'|' -v g="$1" '{ n = split($6, a, ","); for (i = 1; i <= n; i++) if (a[i] == g) { print; next } }' "$REG" 2>/dev/null
}
didyoumean() {   # <T> -> " (did you mean 'X'?)" for group/box/session within edit distance 2; never auto-sends
    { cut -d'|' -f6 "$REG" | tr ',' '\n'; cut -d'|' -f1,2 "$REG" | tr '|' '\n'; } 2>/dev/null | grep -v '^-\?$' | sort -u \
    | awk -v t="$1" 'function lev(a,b,  i,j,la,lb,d,c){la=length(a);lb=length(b)
        for(i=0;i<=la;i++)d[i,0]=i; for(j=0;j<=lb;j++)d[0,j]=j
        for(i=1;i<=la;i++)for(j=1;j<=lb;j++){c=(substr(a,i,1)!=substr(b,j,1))
          d[i,j]=d[i-1,j]+1; if(d[i,j-1]+1<d[i,j])d[i,j]=d[i,j-1]+1; if(d[i-1,j-1]+c<d[i,j])d[i,j]=d[i-1,j-1]+c}
        return d[la,lb]}
      {k=lev(t,$0); if(k<=2 && (best=="" || k<bk)){best=$0; bk=k}}
      END{if(best!="") printf " (did you mean %c%s%c?)", 39, best, 39}'
}
targets() {   # all | T[,T...] -> session names; T = session, prefix, BOX, or GROUP (39-D9)
    # `all` means the fleet NOW: a stale registry silently drops a CLI launched
    # since the last refresh (5 panes for 6 live sessions).  Rescan ~1.4s.
    if [ "$1" = all ]; then refresh >/dev/null; cut -d'|' -f2 "$REG"; return; fi
    local t r
    for t in ${1//,/ }; do
        r=$(row "$t")
        [ -n "$r" ] || r=$(boxrows "$t")
        # a group is live membership: always rescan before trusting it
        [ -n "$r" ] || { refresh; r=$(row "$t"); [ -n "$r" ] || r=$(boxrows "$t"); [ -n "$r" ] || r=$(grouprows "$t"); }
        [ -n "$r" ] || { echo "cli: no session, box or group '$t'$(didyoumean "$t")" >&2; list >&2; return 1; }
        printf '%s\n' "$r" | cut -d'|' -f2
    done
}

# Type a line into the CLI's input box.  -l = literal (no key-name parsing:
# a message containing "Enter" or "C-c" stays text).  Enter sent separately.
# A BUSY autopilot queues it; an idle one runs it.
send() {   # send <session> <message>
    local r b s p m msg="$2"
    r=$(resolve "$1") || return 1
    IFS='|' read -r b s p _ <<<"$r"
    # /exec_plan with no plan path: insert the session's own plan, keep the rest
    # as the instruction ("/exec_plan push finish X" -> "/exec_plan <plan> push finish X")
    if [ "$p" != - ] && { [ "$msg" = /exec_plan ] || { [ "${msg#/exec_plan }" != "$msg" ] &&
        ! printf '%s' "${msg#/exec_plan }" | grep -qE '^[^ ]*(\.org\.txt|/)|^[0-9]+([ .]|$)'; }; }; then
        msg="/exec_plan $p${msg#/exec_plan}"
    fi
    m=$(printf '%q' "$msg")
    if timeout 20 ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR "$b" \
        "tmux send-keys -t '$s' -l -- $m && sleep 0.3 && tmux send-keys -t '$s' Enter"; then
        printf '%-6s %-24s sent: %s\n' "$b" "$s" "$msg"
    else
        printf '%-6s %-24s FAILED\n' "$b" "$s" >&2; return 1
    fi
}

grid() {   # grid <session>...  -- pages of CLI_PAGE panes (default 6), tiled
    local g=cli-grid s box n=0 page=${CLI_PAGE:-6} cmd
    command -v tmux >/dev/null || { echo "cli: tmux missing" >&2; exit 2; }
    tmux has-session -t "$g" 2>/dev/null && tmux kill-session -t "$g"
    for s in "$@"; do
        box=$(lookup "$s")
        [ -n "$box" ] || { echo "cli: skip unknown '$s'" >&2; continue; }
        cmd="ssh -t $box tmux attach -t $s; echo '[$box/$s detached]'; read"
        if [ $n = 0 ]; then
            tmux new-session -d -s "$g" -x 240 -y 60 -n p1 "$cmd"
            tmux set -t "$g" prefix C-a
            tmux set -t "$g" mouse on
            tmux set -t "$g" pane-border-status top
            tmux set -t "$g" pane-border-format ' #{pane_index} #{pane_title} '
            tmux set -t "$g" allow-rename off
            tmux set -t "$g" set-titles off
            # Tab / S-Tab: next / previous pane in this page, KEEPING zoom (-Z),
            # so zoomed = full-screen carousel.  -r: repeat without re-prefix.
            tmux bind -r Tab   select-pane -Z -t :.+
            tmux bind -r BTab  select-pane -Z -t :.-
        elif [ $((n % page)) = 0 ]; then
            tmux new-window -t "$g" -n "p$((n / page + 1))" "$cmd"
        else
            tmux split-window -t "$g" "$cmd"
        fi
        tmux select-pane -t "$g" -T "$box/$s"
        tmux set -p -t "$g" allow-set-title off 2>/dev/null
        tmux select-layout -t "$g" tiled >/dev/null
        n=$((n + 1))
    done
    [ $n -gt 0 ] || { echo "cli: nothing to attach" >&2; exit 1; }
    tmux select-window -t "$g:p1"
    [ -n "${CLI_NOATTACH:-}" ] && exit 0
    if [ -n "${TMUX:-}" ]; then exec tmux switch-client -t "$g"
    else exec tmux attach -t "$g"; fi
}

# main() + `exit` on the same line: bash reads the WHOLE body before running it,
# so a `git pull` / edit of this file under a running `watch cli -r` cannot make
# bash resume at a shifted offset (seen: "S[0]: unbound variable" mid-watch).
# CLI_LOG: list-mode stderr is also appended there with a UTC stamp, so errors
# that flash by inside `watch -n 10 cli -r` are kept (tail -f ~/.copilot/cli.log).
CLI_LOG="${CLI_LOG:-$HOME/.copilot/cli.log}"
logerr() { exec 2> >(while IFS= read -r l; do printf '%s %s[%s] %s\n' "$(date -u +%FT%TZ)" "${HOSTNAME%%.*}" "$*" "$l" >> "$CLI_LOG"; printf '%s\n' "$l" >&2; done); }

# 39-D14: plain `cli` = one read of local files.  It marks the read (mtime of
# $REG.feed.read; the feeder exits CLI_FEED_IDLE after the last one) and starts
# the feeder if $REG.feed.pid is dead.  Builtins only on the hot path: the fork
# happens once per feeder life.  CLI_FEED=0 disables (tests, boxes without ssh).
feed_kick() {
    [ "${CLI_FEED:-1}" != 0 ] || return 0
    : > "$REG.feed.read"
    # 41: the feed only streams boxes already in $REG -- a session on a NEW box stays
    # invisible until a sweep; so a stale $REG (> CLI_REG_TTL s) gets one background sweep
    # CLI_REG_TTL default: 10 s under `watch` (a frame every 2 s wants new boxes fast; was the
    # `cps` alias's CLI_REG_TTL=10), 120 s for a one-shot `cli`.  under_watch: /proc reads only.
    local ttl=${CLI_REG_TTL:-}; [ -n "$ttl" ] || { under_watch && ttl=10 || ttl=120; }
    if [ -z "$(find "$REG" -newermt "-$ttl seconds" 2>/dev/null)" ]; then
        ( flock -n 9 || exit 0; refresh >/dev/null 2>&1 ) 9> "$REG.sweep.lock" &
    fi
    local p=; { read -r p < "$REG.feed.pid"; } 2>/dev/null
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && return 0
    setsid python3 "$HERE/cli-feed.py" < /dev/null >> "$REG.feed.log" 2>&1 &
}

# 41 G.3: every IDLE session in no room (GROUP -) gets a join prompt for CHAN,
# default the dispatched room with the most open tasks, then the most joined,
# then the latest line.  -n: print targets + chan, send nothing.
enlist() {   # [CHAN] [-n]
    local chan= dry= a b s g c n t
    for a in "$@"; do if [ "$a" = -n ]; then dry=1; else chan=$a; fi; done
    [ -s "$REG" ] || refresh
    if [ -z "$chan" ]; then
        chan=$("$ROOM_SH" rooms 2>/dev/null | jq -r 'select((.dispatched // []) | length > 0)
                   | [.chan, (.joined // [] | length), (.last_ts // "")] | @tsv' |
            while IFS=$'\t' read -r c n t; do
                printf '%s\t%s\t%s\t%s\n' "$("$ROOM_SH" -c "$c" tasks 2>/dev/null | awk -F'\t' '$2=="open"' | grep -c .)" "$n" "$t" "$c"
            done | sort -t$'\t' -k1,1nr -k2,2nr -k3,3r | head -1 | cut -f4)
    fi
    [ -n "$chan" ] || { echo "cli: no dispatched room to enlist into" >&2; return 1; }
    local msg="room -c $chan post join 'enlisted: idle, in no room (cli --enlist)' ; room -c $chan next -- it prints the task JSON you won (or none). Run a won task with /exec_plan on its ref plan, scoped to its title; when done_when passes post done --reply-to <task id> --ref <sha>, then room -c $chan next again. On none, stop: the dispatcher wakes you."
    echo "enlist -> $chan"
    [ -e "$REG.top" ] || : > "$REG.top"
    while IFS='|' read -r a b s g; do
        [ "$a" = IDLE ] && [ "$g" = - ] || continue
        if [ -n "$dry" ]; then printf '%-6s %s\n' "$b" "$s"; else send "$s" "$msg"; fi
    done < <(while IFS='|' read -r b s _; do printf '%s|%s|-\n' "$b" "$s"; done < "$REG" | ACTS_RAW=1 acts 28 20 0 - 10)
}

main() {
case "${1:-}" in
    --enlist)     logerr "$@"; shift; enlist "$@" ;;
    --refresh|-r) logerr "$@"; refresh; list "${2:-}" ;;
    --list|-l|'') logerr "$@"; [ -s "$REG" ] || refresh; [ -z "${1:-}" ] && feed_kick; list "${2:-}" ;;
    --feed)       exec python3 "$HERE/cli-feed.py" ;;   # foreground; `cli` starts it lazily (39-D14)
    -v)           logerr "$@"; [ -s "$REG" ] || refresh; list -v ;;   # wide: MODEL LAUNCHED PLAN   # no registry yet: build it once
    --all|-a)     logerr "$@"; refresh_all; list_all ;;
    -V|--version)
        if [ "${2:-}" != all ]; then echo "cli $CLI_VERSION"; exit 0; fi
        boxes | xargs -P 16 -I{} bash -c 'v=$(probe_one {} VERPROBE); echo "{} ${v:-(unreachable)}"' |
            sort -V | awk -v me="cli $CLI_VERSION" '{v=$2" "$3; print (v==me?"  ":"! ") $0; if(v!=me) d++}
                END{printf "%d box(es) differ from local %s\n", d, me > "/dev/stderr"}' ;;
    -h|--help)    sed -n '2,/^# The ~\/.bashrc/p' "$0" ;;
    *)
        # "cli cj06, cj07, cj01 msg": a target token ending in ',' continues the list
        T=$1; shift
        while [ "${T%,}" != "$T" ] && [ $# -gt 0 ]; do T="$T$1"; shift; done
        T=${T%,}; set -- "$T" "$@"
        mapfile -t S < <(targets "$1") || exit 1
        [ ${#S[@]} -gt 0 ] || exit 1
        if [ $# -gt 1 ]; then          # message mode
            shift; rc=0
            for s in "${S[@]}"; do send "$s" "$*" || rc=1; done; exit $rc
        fi
        if [ ${#S[@]} -gt 1 ] || [ "$1" = all ] || [ "${1#*,}" != "$1" ]; then grid "${S[@]}"; fi
        b=$(lookup "${S[0]}")
        awk -F'|' -v s="${S[0]}" '$2==s{f=1}END{exit !f}' "$REG" \
            || { echo "(no tmux) $b ${S[0]}"; exit 0; }   # vterm row from --all (39-F8)
        exec ssh -t "$b" tmux attach -t "${S[0]}"
        ;;
esac
}
main "$@"; exit
