#!/usr/bin/env bash
# fleet-ssh.sh -- fan a probe across the fleet, render one clean table.
#
# Column 1 is always the BOX.  Every other column is one thing you asked
# for.  That layout is the whole point: a fleet answer is a MATRIX, and a
# matrix read as prose hides the one box that differs.
#
# Usage:
#   fleet-ssh.sh [-t TIER] [-j N] [-b BOXES] COL=CMD [COL=CMD ...]
#
#   -t TIER    wsl (default) | u | ctr | e | eu     -- appended to the box name
#              NO `ctr` TIER EXISTS -- the CONTAINER IS THE BARE NAME.
#              2200 = WSL (cNNwsl / cNNu), 2222 = the
#              container (cNN, like helix/devcontainer).  User ruling
#              2026-09-13; bin/fleet.py implements it.  `-t ctr` resolves
#              to the literal `cNNctr:22` -> (unreachable) on every box.
#              2224 is DEAD: it was the container port only while the
#              distro held 2222; the distro moved to 2200 and vacated it.
#              A stale ~/.ssh/config may still say 2224 -- REGENERATE it
#              with `python3 bin/fleet.py sshconfig`, do not read it.
#   -j N       parallel width (default 8)
#   -b BOXES   comma OR space separated list (default: discover from ssh config)
#   -R         RAW: emit the raw `box<TAB>col<TAB>value` records and SKIP the
#              pivot/pad.  For callers that MERGE two runs (e.g. `ghcp` joins
#              the wsl and `-t ctr` tiers): a rendered table can only be
#              re-joined by re-splitting its padded columns on runs of spaces,
#              which is the positional-collapse failure this wrapper exists to
#              prevent.  The raw records are keyed on the box and carry the
#              value as a single TAB-delimited field, so a merge joins on
#              `(box,col)` with nothing to re-split.  Same records the pivot
#              consumes -- `(unreachable)` boxes emit NO rows (as with the
#              table, absence is the unreachable signal).
#
# Example:
#   fleet-ssh.sh node='node -v' docker='docker --version'
#   fleet-ssh.sh -t u lserver='tmux capture-pane -t lserver -p | grep -vc "^$"'
#
# WHY A WRAPPER AND NOT THE ONE-LINER: the one-liner is easy to get
# subtly wrong, and every way of getting it wrong produces a CONFIDENT
# WRONG TABLE rather than an error.  Measured in this repo:
#   - two printfs per job shred rows across boxes under `xargs -P`
#   - a quoting bug returned the same empty value on 4/4 and looked like a
#     real fleet-wide failure (it was the probe, not the fleet)
#   - positional field reads collapsed when one command printed nothing,
#     so "no container" was reported as "container up, port dark"
# This script fixes the shape once: `parallel --tag` for atomic,
# self-labelled rows; NAMED fields so a missing value cannot shift a
# column; and a literal "-" for empty so a blank cell is visible.

# 41 A.1: fleet facts in ${FLEET_HOME:-~/.fleet}, else the committed bin/ seed.
FH="${FLEET_HOME:-$HOME/.fleet}"
FLEET_IPS_DEFAULT="$FH/fleet-ips.json"
[ -r "$FLEET_IPS_DEFAULT" ] || FLEET_IPS_DEFAULT="$(dirname "$0")/../../../bin/fleet-ips.json"
set -u
# Resolve our own directory so we can point at the sibling recipes.sh.
# Needed because `set -u` is on: an undefined $HERE would abort with a
# bare "unbound variable" instead of the helpful message below.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TIER=wsl
JOBS=8
BOXES=""      # empty => DISCOVER from ~/.ssh/config
RAW_ONLY=0    # -R => emit raw `box<TAB>col<TAB>value` records, skip the pivot

# THE SWEEP MUST FINISH EVEN IF A BOX NEVER ANSWERS.  This is the whole
# survive-a-lost-host contract, and `ConnectTimeout` DOES NOT PROVIDE IT:
# it bounds only the TCP/handshake phase.  A box that ACCEPTS the
# connection and then stops -- a hung sshd, a wedged WSL distro, a remote
# command blocked on a credential prompt, a half-open NAT/VPN path -- sits
# in an established session forever, and `ssh` will wait forever with it.
# recipes.sh:1637 already recorded this failure ("ConnectTimeout does not
# cover it -- the connection succeeded; the remote COMMAND stalled") and
# bounded ITS OWN calls with an outer `timeout`; fleet-ssh.sh, which every
# recipe funnels through, never got the same guard.
#
# :*** WHY AN UNBOUNDED SWEEP IS NOT MERELY SLOW -- IT KILLS THE SESSION. ***
# MEASURED 2026-09-23 (see REPL/fix.archive/survive_lost_host.md): a tool
# call that blocks past ~120s makes the CLI runtime emit a
# `tool.execution_partial_result` event, and the session host has a FIXED
# 120s budget to acknowledge it.  A TUI host pinned by a long-running
# foreground call does not ack in time, and the session then dies with
#   "session host did not acknowledge the ... event within 120s"
# -- which is UNRECOVERABLE BY RESUMING, because the resumed session
# replays the same state and stalls the same way.  357 such failures were
# logged across two sessions.  So a hung box does not cost you one cell in
# a table; it costs you the whole session.  Bounding the hang is therefore
# a CORRECTNESS requirement of this wrapper, not a nicety.
#
# Three layers, because each covers what the other cannot:
#   ConnectTimeout  -- the box is dark (no SYN/ACK)          -> ~15s
#   ServerAliveN    -- the path dies MID-SESSION (half-open) -> ~3x10s
#   timeout (outer) -- the box answered but the COMMAND hangs-> hard cap
# The outer `timeout` is the only one that is unconditional, so it is the
# one that makes the guarantee.  Keep all three.
FLEET_SSH_CONNECT_TIMEOUT="${FLEET_SSH_CONNECT_TIMEOUT:-15}"
FLEET_SSH_CMD_TIMEOUT="${FLEET_SSH_CMD_TIMEOUT:-60}"

# `timeout -k`: SIGTERM first, then SIGKILL 5s later.  ssh holding a wedged
# pty can ignore TERM, and a surviving ssh would keep the `parallel` job
# slot -- and with it the whole sweep -- alive past the cap it was given.
# :*** MULTIPLEXING IS OPT-IN, AND THE DEFAULT IS UNCHANGED. ***  Plan 28
# item 3.1.  MEASURED 2026-09-24 helix->cj00: a fresh dial costs 653ms and
# a reused one 111ms -- 6x, flat at 1/5/10 dials, because the 541ms saved
# IS the handshake.  `ssh -vvv` says where it goes: 244ms of it is AUTH,
# only 66ms is the banner, and IdentitiesOnly/GSSAPI/faster-KEX all
# measure as noise (657/668/646ms).  The only lever is not connecting
# again.
# :trap: A CACHED MUX SESSION PREDATES WHAT YOU ARE TESTING.  This file
# has always set ControlPath=none for a measured reason -- after
# `usermod -aG docker`, a probe through a live mux showed 0 images while
# a fresh session showed 7.  That is a WRONG ANSWER, not slowness, so
# reuse stays opt-in and the window stays short: persist=5s gives
# 298ms/dial, 10s gives 222ms, a held master 111ms.  Ten seconds takes
# most of the win while bounding staleness to under one human turn.
# :trap: THE SOCKET MUST KEY ON THE HOST.  `%h` is why -- this file also
# records that ControlMaster keys on %n, so a literal address collapses
# every box onto ONE socket and one box answers for all of them.  A sweep
# that reports one box's answer under every row looks perfect.
if [ "${FLEET_SSH_MUX:-0}" = "1" ]; then
    SSH_MUX="-o ControlMaster=auto -o ControlPath=/tmp/fleet-%r@%h:%p \
-o ControlPersist=${FLEET_SSH_MUX_PERSIST:-10}s"
else
    SSH_MUX="-o ControlPath=none"
fi
SSH_OPTS="-o BatchMode=yes $SSH_MUX \
-o ConnectTimeout=$FLEET_SSH_CONNECT_TIMEOUT \
-o ServerAliveInterval=10 -o ServerAliveCountMax=3"
SSH_BOUND="timeout -k 5 $FLEET_SSH_CMD_TIMEOUT"

# FLEET_SSH_CONFIG MUST REACH `ssh`, NOT JUST DISCOVERY.  It already chose
# which boxes the sweep would visit (discover_boxes) and resolved the ctr
# tier, but the distro-tier `ssh` never received it -- so it silently fell
# back to ~/.ssh/config and DIALLED DIFFERENT HOSTS THAN THE ONES IT HAD
# JUST ENUMERATED.  Two costs: the timeout guard above could not be
# exercised against a fake fleet (the test hosts resolved to nothing and
# every row read `(unreachable)` in ~1s, which LOOKS like a pass), and a
# caller pointing at an alternate config got a confident table built from
# the wrong file.  Unset => omit `-F` entirely, so the default path is
# byte-for-byte what it was.
[ -n "${FLEET_SSH_CONFIG:-}" ] && SSH_OPTS="-F $FLEET_SSH_CONFIG $SSH_OPTS"

# DISCOVER THE FLEET, NEVER HARDCODE IT.  ~/.ssh/config is the only thing
# that already knows which boxes exist and how to reach them, and it is
# regenerated by `fleet.py sshconfig` as the fleet grows.  A baked-in list
# is wrong the day box 5 arrives -- and wrong SILENTLY, because the sweep
# still returns a full, confident table for the boxes it does know.
# Match `Host c01 ...` / `Host c01wsl ...` and reduce to the STEM, so the
# box list is tier-independent.
# FLEET_SSH_BOXES pins the default scope.  WHY IT EXISTS: fleet.py
# generates a Host block for every box in the SCHEME, not every box that
# EXISTS -- after a `fleet.py sshconfig` regen, ~/.ssh/config carried 16
# cNN stems while only 4 answered (measured 2026-09-13: c01..c04 alive,
# c05..c16 (unreachable)).  Discovery then padded every default sweep
# with 12 dead rows.
# :trap: do NOT filter on the `# CNN: UNVERIFIED` comment fleet.py emits.
# It is a PROVISIONING note, not a liveness fact, and it is stale for
# c03/c04 -- both are flagged UNVERIFIED and both answer every probe.
# Filtering on it would silently DROP two working boxes, which is the
# same class of wrong answer this wrapper exists to prevent.
# :*** DEFAULT SCOPE IS THIS BOX'S REGION; `-b all` CROSSES REGIONS. ***
# The fleet is no longer one /17.  MEASURED 2026-09-24 from helix:
# `^[cC][0-9]+` returned 16 boxes and ZERO japan east -- `cj00` cannot
# match a regex that demands a digit straight after `c`, so a whole
# region was invisible to every default sweep while the table looked
# complete.  And the other direction is just as wrong: ~/.ssh/config
# carries 47 wsl aliases while bin/fleet-ips.json knows 31 real boxes,
# so an unfiltered sweep pads with 19 GHOSTS (ci01..ci14, m09..m13)
# that render `(unreachable)` forever.
# :trap: A CROSS-REGION DEFAULT WOULD BE SLOWER *AND* WRONG.  The
# region edges are FILTERED, not routed -- helix sends 10.12 and 10.30
# through the same next hop (10.18.0.1) and only 10.12 answers.  So a
# default `all` sweep would spend the full ConnectTimeout per
# out-of-region box to print a cell that says nothing about that box's
# health.  In-region by default; `-b all` when you mean it.
_fleet_region_boxes() {
    # Emit the boxes of THIS box's region, else every box, from the
    # registry -- never from the ssh config, which carries the naming
    # SCHEME rather than the fleet.
    local want="$1" ips="${FLEET_SSH_IPS:-$FLEET_IPS_DEFAULT}"
    [ -r "$ips" ] || return 1
    python3 - "$ips" "$want" <<'PYEOF' 2>/dev/null
import json, subprocess, sys
d = json.load(open(sys.argv[1])); want = sys.argv[2]
regions = d.get("regions") or {}
if not regions:                       # schema 1 -- flat, no region info
    print(",".join(sorted(d.get("boxes", d))));  raise SystemExit
me = ""
for a in subprocess.run(["hostname","-I"], capture_output=True,
                        text=True).stdout.split():
    if a.startswith("10.") and not a.startswith(("10.42.","10.43.")):
        me = a; break
blk = ".".join(me.split(".")[:2]) if me else ""
out = []
for name, r in regions.items():
    inb = r.get("block","").startswith(blk + ".") if blk else False
    if want == "all" or inb:
        out += list(r.get("boxes", {}))
# Fall back to every box when this driver sits outside every known block
print(",".join(sorted(out) if out else sorted(d.get("boxes", {}))))
PYEOF
}

discover_boxes() {
    if [ -n "${FLEET_SSH_BOXES:-}" ]; then
        printf '%s' "$FLEET_SSH_BOXES"; return 0
    fi
    local r; r=$(_fleet_region_boxes "${FLEET_SSH_SCOPE:-region}")
    if [ -n "$r" ]; then printf '%s' "$r"; return 0; fi
    # Registry unreadable -- fall back to the config scan.  Widened stem:
    # `[a-z]+[0-9]+` so cj00/ci01 are seen at all.
    local cfg="${FLEET_SSH_CONFIG:-$HOME/.ssh/config}"
    [ -r "$cfg" ] || return 1
    awk '$1 == "Host" { for (i = 2; i <= NF; i++) print $i }' "$cfg" \
        | grep -oE '^[a-zA-Z]+[0-9]+' \
        | tr 'A-Z' 'a-z' \
        | sort -u \
        | paste -sd,
}

while getopts "t:j:b:R" o; do
    case "$o" in
        t) TIER=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        # `-b all` is the CROSS-REGION opt-in (see _fleet_region_boxes).
        # It is a word, not a box list, because "every box everywhere"
        # is a decision about cost -- out-of-region cells burn the full
        # ConnectTimeout on a filtered edge.
        # `-b up` is the MEASURED scope: only boxes a real TCP dial
        # reached from THIS host, newest sweep, via bin/fleet-route.sh.
        # It is not a synonym for `all` minus the broken ones -- an edge
        # is an observation with a timestamp, so this can be STALE and
        # fleet-route.sh warns on stderr when it is.  Falls back to the
        # region scope (never to `all`) if the graph has not been built,
        # because silently widening scope is how a cheap sweep becomes a
        # 28-box one that burns ConnectTimeout on filtered edges.
        b) if [ "$OPTARG" = all ]; then BOXES=$(_fleet_region_boxes all)
           elif [ "$OPTARG" = up ]; then
               _rt="$(dirname "${BASH_SOURCE[0]}")/../../../bin/fleet-route.sh"
               if [ -x "$_rt" ] && _up=$("$_rt" broadcast 2>/dev/null) && [ -n "$_up" ]; then
                   BOXES=$(echo "$_up" | tr ' ' ',')
               else
                   echo "# -b up: no reachability graph; falling back to region scope" >&2
                   BOXES=$(_fleet_region_boxes region)
               fi
           else BOXES=$OPTARG; fi ;;
        R) RAW_ONLY=1 ;;
        *) echo "usage: $0 [-t tier] [-j N] [-b boxes|all|up] [-R] COL=CMD ..." >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "usage: $0 [-t tier] [-j N] [-b boxes|all|up] [-R] COL=CMD ..." >&2; exit 2; }

# Accept comma OR whitespace separated box lists.  A user who types
# `-b "c01 c02"` (the way they SAY it) otherwise gets one bogus host named
# "c01 c02" and a single (unreachable) row -- a silent wrong answer.
BOXES=$(printf '%s' "$BOXES" | tr ', \t' '\n\n\n' | sed '/^$/d' | paste -sd,)

if [ -z "$BOXES" ]; then
    BOXES=$(discover_boxes)
    [ -n "$BOXES" ] || { echo "fleet-ssh: no fleet hosts in ~/.ssh/config (expected 'Host cNN...')" >&2; exit 2; }
fi

command -v parallel >/dev/null 2>&1 || { echo "fleet-ssh: GNU parallel required" >&2; exit 2; }

# Build ONE remote script from the COL=CMD pairs.  It is piped over stdin
# (`bash -s`), never interpolated into an ssh argument -- that is what
# keeps quoting out of the picture entirely: the remote shell sees the
# script verbatim and no layer gets to reinterpret it.
REMOTE=$(mktemp); trap 'rm -f "$REMOTE"' EXIT
HDRS=""
for pair in "$@"; do
    col=${pair%%=*}; cmd=${pair#*=}
    if [ "$col" = "$pair" ]; then
      # A bare word is almost always someone reaching for a RECIPE, which
      # lives in the sibling script.  Say so instead of just refusing --
      # the error is the only documentation a caller reads at that moment.
      if "$HERE/recipes.sh" list 2>/dev/null | grep -qw -- "$pair"; then
        echo "fleet-ssh: '$pair' is a RECIPE -- run it with:" >&2
        echo "    $HERE/recipes.sh $pair" >&2
      else
        echo "fleet-ssh: expected COL=CMD, got '$pair'" >&2
        echo "    named sweeps live in recipes.sh -- try: $HERE/recipes.sh list" >&2
      fi
      exit 2
    fi
    HDRS="$HDRS $col"
    # Emit KEY<TAB>VALUE.  Named, so a command that prints nothing leaves
    # an EMPTY value rather than shifting every later column left.
    {
        # `</dev/null` IS LOAD-BEARING, not defensive noise.  The probe
        # arrives on the remote shell's STDIN (`bash -s`), so any command
        # that reads stdin EATS THE REST OF THE SCRIPT.  Measured on the
        # win tier: `v=$(cmd.exe /c "node -v")` returned EMPTY through
        # `bash -s` while the identical command worked interactively --
        # cmd.exe had swallowed the remaining lines.  The whole table read
        # `(unreachable)` and looked like an ssh problem.
        # `tr -d '\r'` is also load-bearing on the WINDOWS tier: cmd.exe
        # emits CRLF, and a bare CR makes the terminal overwrite the row
        # from column 0 -- the table printed "v24.14.0c01" with the BOX
        # name on top of its own value.  Strip it at the source.
        # :trap: `</dev/null` MUST WRAP THE WHOLE PIPELINE, not trail it.
        # Shell binds a trailing redirect to the LAST command, so
        #     tmux capture-pane | grep -vc '^$' </dev/null
        # starves GREP of its input and always yields 0.  Measured: the
        # service table went from lserver=23 to lserver=0 fleet-wide, and
        # it looked like every service had died.
        # `{ ...; } </dev/null` redirects the group, so only commands that
        # actually read stdin (cmd.exe) are fed /dev/null.
        # On the win tier the command is HOISTED INTO WINDOWS.  Without
        # this it runs in WSL's bash (see the trap above) and reports the
        # distro's answer under a "Windows" header.  A probe that already
        # names powershell.exe/cmd.exe is left alone -- it is explicit.
        if [ "$TIER" = win ]; then
            # :*** THE WIN TIER IS POWERSHELL, END TO END. ***
            # It used to pipe `bash -s` here and wrap each command in
            # powershell.exe.  That BROKE COMPLETELY once the nx-owned WSL
            # distros were deleted (2026-09-16): `bash` on the Windows PATH
            # IS `wsl.exe`'s bash, nx now owns no distro, so the login shell
            # died with "no installed distributions" before reading a single
            # probe -- and EVERY win row rendered `(unreachable)` while
            # `ssh cNNwin hostname` answered perfectly.
            # A tier whose transport depends on a distro cannot be used to
            # DIAGNOSE that distro, which is precisely what it is for.
            # So: emit a PowerShell body and hand it to powershell -Command -.
            # Same stdin transport, same one-line-per-field contract.
            printf '$v = try { @(%s) 2>$null | Select-Object -First 1 } catch { $null }\n' "$cmd"
            # :trap: STRIP THE CR IN POWERSHELL, NOT DOWNSTREAM.  Write-Output
            # terminates every line with CRLF, and `parallel --tag` prefixes
            # the box name -- so a surviving CR makes the terminal return to
            # column 0 and overprint the row, rendering "Windows_NTc01" with
            # the BOX name on top of its own value.  It reads like a parsing
            # bug in the pivot; it is a bare carriage return.
            # :trap: THE CR MUST DIE *INSIDE* THE parallel JOB, and this
            # took four wrong attempts to see.  MEASURED bytes of one job:
            #     c03 \t os \t Windows_NT \r c03 \t \n
            # `parallel --tag` re-emits the tag AT EVERY NEWLINE, and the
            # remote's CRLF puts \r BEFORE \n -- so the tag lands after the
            # CR and the row renders "Windows_NTc03".  The value was never
            # corrupted; that is a SECOND tag on the phantom line the CR
            # opens.  So stripping downstream (on $RAW) is too late: the
            # damage is done while parallel is still writing.  The `tr -d`
            # belongs in the job, before --tag ever sees the bytes.
            # Failed first: `-replace "[\r\n]"` (backslashes eaten by
            # printf->bash->PowerShell, every row `(unreachable)`) and
            # `.Trim([char]13,[char]10)` (ran, but the transport re-adds it).
            printf 'Write-Output ("%s`t" + $(if ($null -ne $v -and "$v" -ne "") { "$v" } else { "-" }))\n' "$col"
        else
            printf 'v=$({ %s ; } </dev/null 2>/dev/null | head -1 | tr -d "\\r")\n' "$cmd"
            printf 'printf "%%s\\t%%s\\n" "%s" "${v:--}"\n' "$col"
        fi
    } >> "$REMOTE"
done

# :*** THE CAP CAN CUT A PROBE IN HALF, AND WITHOUT THIS SENTINEL THAT
# RENDERS AS A HEALTHY ROW. ***  The outer `timeout` above guarantees the
# sweep ENDS; it does not guarantee the box FINISHED.  Fields are emitted
# one line at a time as the remote script walks them, so a box killed
# mid-probe has already delivered the EARLY columns and simply stops.  The
# pivot then fills the rest from "no record" -- which is the same state a
# box that answered `-` produces.
# MEASURED 2026-09-23, 3 x 25s fields against a 60s cap:
#     BOX  A  B  C
#     c90  A  B            <- C is not "empty", it NEVER RAN
# A and B are real, C is a LIE OF OMISSION, and the row carries no hint
# that anything was cut.  That is the confident-wrong-table failure this
# whole wrapper exists to prevent, reintroduced by its own timeout.
# So the remote states, as its LAST act, that it reached the end.  The
# marker is emitted only after every field has printed, which makes the
# implication exact:
#     marker present            -> every column ran
#     marker absent, rows seen  -> CUT mid-probe  (render `(cut)`)
#     marker absent, no rows    -> never answered (render `(unreachable)`)
# It is a field like any other on the wire, so it needs no new transport
# and costs one line; it is NOT added to $HDRS, so it never prints as a
# column.  `-R` consumers see it too, keyed on the box, and may ignore it
# safely -- it is not in any recipe's fixed header list.
# :*** `-t win` IS REJECTED, NOT SILENTLY BROKEN. ***
# It dialled `cNNwin` on :22 -- a Windows sshd, which R-NORELAY BANS
# (a written commitment to Cyber Defense Investigations, 2026-09-21).
# MEASURED 2026-09-25: :22 is dark on every box BY DESIGN.
# Leaving the code path in place would render `(unreachable)` on every
# row, which is a fact about the BAN reported as a fact about the FLEET
# -- exactly the probe-vs-world confusion this wrapper exists to stop.
# Fail loudly and name the sanctioned replacement instead.
if [ "$TIER" = win ]; then
    echo "fleet-ssh: -t win is REMOVED.  cNNwin needs a Windows sshd and" >&2
    echo "  R-NORELAY bans one (:22 measured dark fleet-wide, by design)." >&2
    echo "  For a WINDOWS-tier fact use WinRM :5985 from a peer in the" >&2
    echo "  SAME project -- see SKILL.md '-t win IS GONE'." >&2
    exit 2
fi

if [ "$TIER" = win ]; then
    printf 'Write-Output ("__done__`t1")\n' >> "$REMOTE"
else
    printf 'printf "%%s\\t%%s\\n" "__done__" "1"\n' >> "$REMOTE"
fi

# :trap: ON THE `win` TIER, `bash` IS WSL's BASH -- NOT WINDOWS.
# MEASURED 2026-09-13: `-t win os='uname -s'` returned **Linux** on every
# box, and `-t win node='node -v'` returned the WSL node (v24.21.0) while
# the real Windows node is v18.20.6.  sshd on Windows hands `bash -s` to
# whatever `bash` resolves to on the Windows PATH, which here is WSL's --
# so the probe silently HOPS BACK into Linux and answers as the distro.
# Every "Windows tier" table produced that way was measuring WSL.
#
# The fix is to keep piping the probe on stdin (quoting-death protection
# is still wanted) but hand it to the WINDOWS shell.  `powershell -Command -`
# reads a script from stdin, so the transport is unchanged; only the
# interpreter differs.
# The probe body is BASH (printf, $(), ${v:--}), so the interpreter must
# stay bash -- swapping it for powershell would break every existing
# probe.  Instead, on the win tier each COMMAND is wrapped so it runs in
# Windows: `powershell.exe -NoProfile -Command "<cmd>"`.  The transport,
# the stdin trick and the CRLF strip are all unchanged.

# THE INTERPRETER IS A PROPERTY OF THE TIER.  `bash -s` on a Windows host
# resolves to WSL's bash (see the trap above) -- correct for the distro
# tiers, fatal for `win`.  `powershell -Command -` reads a script from
# stdin exactly like `bash -s`, so the transport and the quoting-death
# protection are unchanged; only the language differs.
if [ "$TIER" = win ]; then
    SHELL_CMD='powershell.exe -NoProfile -NonInteractive -Command -'
else
    SHELL_CMD='bash -s'
fi

# THE CONTAINER TIER IS A PORT, NOT A SUFFIX -- so it cannot be `{}$TIER`.
#
# :*** `-t ctr` NOW EXISTS, AND THE OLD "NO ctr TIER" NOTE WAS HALF RIGHT. ***
# It was correct that no `cNNctr` STEM exists in ~/.ssh/config, and correct
# that the container is reachable on 2222.  What it concluded from that --
# "so use the BARE alias" -- only works on a driver whose config HAS a bare
# `Host cNN` block.  MEASURED 2026-09-18: this driver's config carries ONLY
# `mNNwsl` and `mNNwin`, so the bare name resolves to nothing and every
# container probe had to be written as `docker exec` over the wsl tier.
#
# :trap: A BARE `ssh -p 2222 root@<ip>` IS REJECTED, AND NOT FOR THE REASON
# IT LOOKS LIKE.  Measured: `Permission denied (publickey,...)` on 3/3 even
# though our key IS in the container's authorized_keys (grep -c = 2),
# PermitRootLogin=yes, PubkeyAuthentication=yes and the perms are right.
# `ssh -v` names the real cause: with no `Host` block matching the IP, ssh
# never OFFERS ~/.ssh/nx.rsa -- it tries id_rsa/id_ecdsa/id_ed25519, none of
# which exist, and gives up.  The fix is to pass the identity and the port
# explicitly, which is what this branch does.  Reading the rejection as "the
# container does not trust us" sends you to fix authorized_keys, which was
# never broken.
#
# HostName + IdentityFile are read from the box's OWN wsl block, so this
# inherits whatever `fleet.py sshconfig` generated instead of duplicating
# it -- one source of truth, and a regen keeps working.
if [ "$TIER" = ctr ]; then
    CTR_PORT="${FLEET_SSH_CTR_PORT:-2222}"
    cfg="${FLEET_SSH_CONFIG:-$HOME/.ssh/config}"
    # `ssh -G` resolves the block the way ssh itself would -- never re-parse
    # the file by hand, or an Include/wildcard silently yields a wrong host.
    # :*** `ssh -G` DOES NOT ALWAYS YIELD AN ADDRESS, AND THE FALLBACK WAS
    # SILENT. ***  MEASURED 2026-09-19 on this driver:
    #     ssh -G c02wsl  ->  hostname c02wsl        <- the ALIAS, unresolved
    #                        proxycommand ssh -q -W 127.0.0.1:2200 C02win
    # The real address lives in the ProxyCommand, not in HostName, so
    # `-t ctr` dialled `c02wsl:2222` -- which ssh resolved straight back
    # through the RELAY to the DISTRO.  Every container probe then answered
    # as the distro, with no error:
    #     -t ctr  hn=CPC-bazho-PMBMN   os=Ubuntu 26.04
    #     -t wsl  hn=CPC-bazho-PMBMN   os=Ubuntu 26.04      <- IDENTICAL
    # That is the EXACT failure this file already records for `-t win`, and
    # the assertion it prescribes (ctr and wsl must DISAGREE) is what caught
    # it.  A correct container answer carries the `ctr` hostname suffix:
    #     CPC-bazho-PMBMNctr
    # Prefer the INVENTORY ip, which is an address by construction, and only
    # fall back to `ssh -G` when the inventory is absent.
    ips="${FLEET_IPS:-$FLEET_IPS_DEFAULT}"
    export ips
    RAW=$(printf '%s\n' "${BOXES//,/$'\n'}" \
          | parallel --tag -j"$JOBS" \
              "hn=\$(python3 -c \"import json,sys;print(json.load(open('\$ips'))[sys.argv[1]].split()[0])\" {} 2>/dev/null);
               [ -n \"\$hn\" ] || hn=\$(ssh -F '$cfg' -G {}wsl 2>/dev/null | awk '/^hostname /{print \$2; exit}');
               idf=\$(ssh -F '$cfg' -G {}wsl 2>/dev/null | awk '/^identityfile /{print \$2; exit}');
               [ -n \"\$hn\" ] || exit 0;
               $SSH_BOUND ssh $SSH_OPTS \
                   -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   \${idf:+-i \"\$idf\"} -p '$CTR_PORT' \"root@\$hn\" \
                   '$SHELL_CMD' < $REMOTE 2>/dev/null | tr -d '\\r'" \
          2>/dev/null)
else
# Paths the fallback needs, resolved ONCE on the driver rather than per
# job: `ssh -G` must read the SAME config the sweep dials with (the
# FLEET_SSH_CONFIG trap above), and the inventory is the address source.
CFG_FOR_G="${FLEET_SSH_CONFIG:-$HOME/.ssh/config}"
IPS_FOR_G="${FLEET_IPS:-$FLEET_IPS_DEFAULT}"
# A bare address matches no `Host` block, so ssh never OFFERS our key --
# the same trap `-t ctr` records above.  Carry identity + port explicitly.
# :trap: ONLY ON THE IP FALLBACK.  A command-line `-p` OVERRIDES the
# alias's own `Port`, so applying these to every dial broke any alias not
# on :2200.  MEASURED 2026-09-26 from helix: c16wsl is `127.0.0.1:22203`
# via the sea relay; `-p 2200` sent it to 127.0.0.1:2200 and c16 rendered
# `(unreachable)` while `ssh c16wsl` answered -- and c14/c15, which JUMP
# through c16, answered in the same table.
: "${FLEET_SSH_IP_OPTS:=-i $HOME/.ssh/nx.rsa -p 2200 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes}"
export FLEET_SSH_IP_OPTS FLEET_SSH_NO_IP_FALLBACK

# Collect: one tagged line per box per field, then pivot to a row.
# A box killed by $SSH_BOUND emits NO rows, so it renders `(unreachable)`
# -- the SAME cell a dark box produces.  That is deliberate: both mean
# "this box did not answer THIS sweep", and the table's job is to make the
# box that differs visible, not to diagnose why.  Absence stays the single
# unreachable signal (the pivot draws that row from $BOXES).
#
# :*** AN ALIAS THAT RESOLVES TO ITSELF IS NOT A DEAD BOX. ***
# MEASURED 2026-09-25 on helix: c09-c13 rendered `(unreachable)` on every
# sweep while all five answered a real TCP dial on :2200 in 32-42ms.
#     ssh -G c09wsl  ->  hostname c09wsl   port 22    <- UNRESOLVED
# ssh prints exactly that for a name matching NO `Host` block (a nonsense
# string yields the identical output), so the alias was never a route: the
# `c09` block is a relay-era `127.0.0.1:2222 ProxyJump C09wsl`, and
# `C09wsl` has no block either -- a chain whose jump host does not exist.
#
# The table then reported five HEALTHY boxes as unreachable, which is the
# worst class of wrong answer here: a fact about the CONFIG rendered as a
# fact about the FLEET.  Widening the config is a separate fix; the sweep
# must not depend on it, because `-b up` already proved those boxes
# reachable from MEASURED dials.
#
# So: resolve the box to its INVENTORY address when the alias does not
# resolve to one. This is the same precedence `-t ctr` above already uses
# ("prefer the INVENTORY ip, which is an address by construction") --
# applied to the default tier rather than duplicated for it.
#
# ALIAS FIRST, ALWAYS.  A resolvable alias may carry a ProxyJump, a
# non-default port or an IdentityFile that the bare address cannot, so the
# fallback fires ONLY when `ssh -G` hands back a non-address.  Set
# FLEET_SSH_NO_IP_FALLBACK=1 to disable it and see the raw config truth.
RAW=$(printf '%s\n' "${BOXES//,/$'\n'}" \
      | parallel --tag -j"$JOBS" \
          "tgt={}$TIER; ipo=;
           if [ -z \"\${FLEET_SSH_NO_IP_FALLBACK:-}\" ]; then
             hn=\$(ssh -F '$CFG_FOR_G' -G {}$TIER 2>/dev/null | awk '/^hostname /{print \$2; exit}');
             case \"\$hn\" in
               *[0-9].[0-9]*) : ;;                      # already an address
               *) ip=\$(python3 -c \"import json,sys
d=json.load(open(sys.argv[1]))
f=d.get('boxes') if isinstance(d.get('boxes'),dict) else {}
v=(f or {}).get(sys.argv[2],'')
print(v.split()[0] if v else '')\" '$IPS_FOR_G' {} 2>/dev/null);
                  [ -n \"\$ip\" ] && { tgt=\"root@\$ip\"; ipo=\"\${FLEET_SSH_IP_OPTS:-}\"; } ;;
             esac;
           fi;
           $SSH_BOUND ssh $SSH_OPTS \$ipo \"\$tgt\" '$SHELL_CMD' < $REMOTE 2>/dev/null | tr -d '\\r'" \
      2>/dev/null)
fi

# -R: emit the raw records and stop.  `parallel --tag` already prepends
# `<box>\t` and each remote line is `<col>\t<value>`, so a line is exactly
# `<box>\t<col>\t<value>` -- the value was TAB/newline-stripped at the source
# (see the remote printf above), so the third field is the whole value and
# nothing downstream needs to re-split it.  This is the pivot's INPUT,
# handed out verbatim for a caller that wants to merge tiers by key.
if [ "$RAW_ONLY" = 1 ]; then
    # First a scope line, so a caller merging tiers knows the FULL box set
    # -- a box unreachable on every tier emits no records, and without this
    # it would silently vanish from the merge (the pivot below draws its
    # `(unreachable)` row from $BOXES for exactly this reason).  Then the
    # raw `box<TAB>col<TAB>value` records.
    printf '#BOXES\t%s\n' "$BOXES"
    printf '%s\n' "$RAW" | grep -e $'\t' || true
    exit 0
fi

# Render.  awk pivots and pads; the header names the query so the table is
# readable without the command that produced it.
printf '%s\n' "$RAW" | awk -v hdrs="$HDRS" -v boxes="$BOXES" '
BEGIN {
    n = split(hdrs, H, " ");
    nb = split(boxes, B, ",");
}
# ONE function, used by BOTH the width pass and the print pass.  They must
# agree exactly: a value measured in one and rendered differently in the
# other overflows its column and shifts every column after it -- the
# positional collapse this table exists to prevent.  Duplicating the
# ternary is how that drifts, so it is written once.
function cellval(b, i,    val) {
    if (!seen[b])                  return (i == 1 ? UNREACH : "");
    if ((b SUBSEP H[i]) in v)      return v[b, H[i]];
    if (!done[b])                  return CUT;   # cap cut it before this field
    return "";
}
# parallel --tag emits: <box>\t<key>\t<value>
NF >= 3 { v[$1, $2] = $3; for (i = 4; i <= NF; i++) v[$1, $2] = v[$1, $2] " " $i }
END {
    # widths first, so columns line up regardless of value length
    wb = 3; for (b = 1; b <= nb; b++) if (length(B[b]) > wb) wb = length(B[b]);
    # Compute widths from what will actually be PRINTED, including the
    # unreachable placeholder -- otherwise a long placeholder overflows a
    # narrow column and every later column shifts, which is exactly the
    # misalignment this table exists to prevent.
    UNREACH = "(unreachable)";
    # A box that emitted rows but no `__done__` was CUT BY THE CAP.  It is
    # a THIRD state, and collapsing it into either neighbour is a wrong
    # answer: calling it `(unreachable)` discards columns that really did
    # answer, and leaving it blank presents a truncated probe as a
    # complete one.  Name it, so the cut is visible in the table itself.
    CUT = "(cut)";
    for (b = 1; b <= nb; b++) {
        seen[B[b]] = 0;
        for (i = 1; i <= n; i++) if ((B[b], H[i]) in v) seen[B[b]] = 1;
        # the marker is proof of completion, never a displayed column
        if ((B[b], "__done__") in v) { done[B[b]] = 1; seen[B[b]] = 1 }
    }
    for (i = 1; i <= n; i++) {
        w[i] = length(H[i]);
        for (b = 1; b <= nb; b++) {
            val = cellval(B[b], i);
            if (length(val) > w[i]) w[i] = length(val);
        }
    }
    printf "%-*s", wb + 2, "BOX";
    for (i = 1; i <= n; i++) printf "%-*s", w[i] + 2, toupper(H[i]);
    printf "\n";
    for (b = 1; b <= nb; b++) {
        printf "%-*s", wb + 2, B[b];
        for (i = 1; i <= n; i++) {
            # A box that never answered has NO rows at all.  Say so ONCE,
            # in the first column, instead of repeating a placeholder in
            # every cell: "unreachable" is a fact about the BOX, not about
            # each field, and repeating it reads like N separate failures.
            # It is also distinct from "-", which means the box answered
            # and the command produced nothing -- different facts, so they
            # must never share a cell value.  `(cut)` is a THIRD fact
            # again: the box answered, this column never ran because the
            # cap killed the probe first.
            val = cellval(B[b], i);
            printf "%-*s", w[i] + 2, val;
        }
        printf "\n";
    }
}'
