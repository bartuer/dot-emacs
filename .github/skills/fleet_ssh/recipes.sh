#!/usr/bin/env bash
# recipes.sh -- named fleet sweeps, so a common question is one word.
#
# Two kinds of question cover nearly every fan-out we actually run:
#   DEPS    is the software there, and is it the same version everywhere?
#   PROCS   is the thing running, and is it supervised rather than orphaned?
# Each recipe below is one of those, pre-written so the quoting, the tier
# and the right probe (dpkg -s, not `command -v`) are already correct.
#
# Usage:  recipes.sh <recipe> [-b boxes] [-j N]
#         recipes.sh list
#
# Add a recipe when you run the same sweep twice.  That is the whole bar.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 41 A.4: fleet facts from ~/.fleet (FLEET_HOME) first, the committed seed second
FIPS=${FLEET_HOME:-$HOME/.fleet}/fleet-ips.json; [ -r "$FIPS" ] || FIPS=$HERE/../../../bin/fleet-ips.json
FS="$HERE/fleet-ssh.sh"

# ---- WINDOWS-TIER PROBE, OVER WinRM --------------------------------------
# :*** `-t win` IS GONE.  R-NORELAY BANS WINDOWS sshd, SO `cNNwin` CANNOT
# EXIST. ***  MEASURED 2026-09-25: :22 is dark on every box BY DESIGN.
# The QUESTIONS those recipes asked are still valid -- Excel's path, the
# physical RAM, a scheduled task's state are Windows-tier facts.  Only the
# TRANSPORT was forbidden.  WinRM (:5985) is the sanctioned one and leaves
# nothing behind: no account, no task, no service, no tunnel; it
# authenticates as the signed-in human and the session dies with the call.
#
# :trap: PORT-OPEN IS NOT REMOTING-PERMITTED.  Three failure modes hide
# behind "WinRM didn't work" -- same project WORKS; CROSS-PROJECT returns
# "Access is denied" with the port wide open; japaneast is DARK FLEET-WIDE
# on :5985.  So the hop must be a peer in the TARGET's project, and a
# failure is `n/a(nowinrm)`, never a red cell: a red for an unaskable
# question is a fact about the probe.
#
# :trap: IT OUTLIVES THE DISTRO IT INSPECTS, which is why it is right on a
# sick box.  Reading .wslconfig through a dying box's own distro returned
# EMPTY (the shell vanished mid-command) and pointed at a fix; over WinRM
# the same file was LEN=53 and correct.
#   (fix.archive/winrm-vs-devcenter-api-pick-by-power-state.md)
#
# Usage: win_probe <ip> <powershell>   -- stdout, empty on failure
WINRM_HOP="${WINRM_HOP:-m08wsl}"
win_probe() {
    _wip="$1"; _wps="$2"
    timeout 120 ssh -o BatchMode=yes -o ConnectTimeout=20 "$WINRM_HOP" \
      "cd /mnt/c && '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' \
       -NoProfile -NonInteractive -Command \
       \"Invoke-Command -ComputerName $_wip -ScriptBlock { $_wps } -EA Stop\"" \
      2>/dev/null | tr -d '\r'
}

recipe=${1:-list}; shift || true

case "$recipe" in

name)
    # WHO AM I in fleet terms: `hostname` says CPC-bazho-RP0DF, the fleet says c01.
    # Local only (no ssh): fleet-connection.json edges (host/ip/island/region/
    # project), merged across observers first-non-null, then fleet-ips.json
    # fills any gap.  Default = this box, matched by hostname or a local ip.
    # Arg: all | a box (c01) | a hostname | an ip.  Session = the tmux session.
    FCONN=${FLEET_HOME:-$HOME/.fleet}/fleet-connection.json
    [ -r "$FCONN" ] || FCONN=$HERE/../../../bin/fleet-connection.json
    q=${1:-}; me=0
    if [ -z "$q" ]; then me=1; q="$(hostname) $(hostname -I 2>/dev/null)"; fi
    sess=$(tmux display -p '#S' 2>/dev/null || echo -)
    jq -rn --slurpfile c "$FCONN" --slurpfile i "$FIPS" --arg q "$q" --arg s "$sess" --argjson me $me '
      ([$c[0].observers[].edges | to_entries[]] | group_by(.key)
        | map({key: .[0].key, value: (reduce .[].value as $e ({};
              . + ($e | with_entries(select(.value != null and .value != "")))
                  + with_entries(select(.value != null and .value != ""))))})
        | from_entries) as $e
      | ([$i[0].regions | to_entries[] | .key as $r | .value as $v | $v.boxes | keys[]
          | {key: ., value: {ip: $v.boxes[.], host: ($v.hostnames[.] // null),
                             island: ($v.islands[.] // null), project: ($v.projects[.] // null), region: $r}}]
         | from_entries) as $f
      | [($f + $e | keys[]) | . as $b
         | ($f[$b] // {}) + (($e[$b] // {}) | with_entries(select(.value != null)))
         | {box: $b, host, ip, island, region, project}] as $rows
      | ($q | ascii_downcase | split(" ") | map(select(. != ""))) as $ws
      | $rows[] | select(($q | ascii_downcase) == "all" or
          ([.box, .host, .ip] | map(ascii_downcase) | any(. as $x | $ws | index($x))))
      | [.box, .host, .ip, (.island // "-"), .region, (.project // "-")]
        + (if $me == 1 then [$s] else [] end) | @tsv' > "${TMPDIR:-/tmp}/name.$$"
    if [ ! -s "${TMPDIR:-/tmp}/name.$$" ]; then
        rm -f "${TMPDIR:-/tmp}/name.$$"; echo "recipes.sh name: no fleet box matches '$q' (try: name all)" >&2; exit 1
    fi
    cat "${TMPDIR:-/tmp}/name.$$" | { if [ $me = 1 ]; then printf 'box\thost\tip\tisland\tregion\tproject\tsession\n'
        else printf 'box\thost\tip\tisland\tregion\tproject\n'; fi; cat; } \
    | column -t -s $'\t'; rm -f "${TMPDIR:-/tmp}/name.$$"
    ;;

list)
    cat <<'LIST'
WHO AM I:
  name [all|BOX|HOST|IP]  this box's fleet name + host/ip/island/region/project
              + tmux session (default = here; local files, no ssh)

THE THREE STAGES — each one is a checkpoint, run them in order:
  stages      ALL THREE in one pass, labelled  <- start here
  base        STAGE 1  bootstrap: rg, jq, parallel, git, git-lfs, tmux
  service     STAGE 2  THREE services: lserver pane + :11434, mcp sock +
                       :47390, fleet-token :11435 (systemd, not tmux)
  harness     STAGE 3  H1 image, H2 api, H3 emacs
  winbuild    STAGE 3 WINDOWS tier: node/yarn/Excel/WebView2 versions
              over WinRM :5985 (NOT ssh -- R-NORELAY bans cNNwin)
  pilot       DEPTH-FIRST: how far has the ONE pilot box got?
              (PILOT_BOX=c02 default -- this is the score during stage 3)

  Stage 1 has a FOURTH member that needs no probe: if the sweep
  answered at all, ssh works -- and ssh IS the bootstrap.  An
  `(unreachable)` row is the stage-0 failure; every other row has
  already passed it.

DEPS  — is the software there, same version everywhere?
  runtime     node / docker / dotnet / python versions
  copilot     GHCP CLI version per box
  images      the Arcadia base images + officeagent

PROCS — is it running, and is it supervised?
  ghcp        WHO IS DRIVING: live copilot sessions per box --
              session name, ip, hostname, STATE (wait/busy/err +
              age), lserver age, last query.  (`copilot` above asks
              whether the CLI is INSTALLED; this asks whether an
              agent is RUNNING, and what it was told.)
  sessions    ONE ROW PER SESSION (plan 35): state incl. HITL/DEAD, age,
              idle, turns, lserver requests + tokens in/out, model,
              commits+diff since session start (REPO-scoped), lserver
              up/errors, pending HITL question.  Reads each box's
              /run/orch/sessions.json (orch-collect.timer, 30s) -- no
              live probe; `/STALE` when the file is >90s old.
  clean       REAP WHAT `ghcp` LISTS: remove session state nothing is
              running, and optionally kill agents parked past a
              threshold.  <- the ONLY recipe that DESTROYS, so it
              REPORTS by default and needs --apply to act.
              `recipes.sh clean`                      (report)
              `recipes.sh clean --apply`              (remove dead state)
              `recipes.sh clean --apply --idle 86400` (also kill parked)
              Killing is opt-in SEPARATELY from deleting: a dead dir
              cannot lose work, a parked agent can.  One pid may hold
              SEVERAL sessions, so a pid with any live session is
              VETOED rather than killed.
  tmux        which tmux sessions exist, per tier
  listeners   every listening TCP port
  disk        free space and docker's footprint
  reduce      MERGE every box's repo commits into ONE tip, SERIALLY
              <- the THIRD pattern: N->1, ordered by ANCESTRY not time.
              A merge cannot be parallel (two merges on one base make two
              tips; one must be redone).  Stops on conflict, never takes
              a side.  Idempotent -- safe to re-run after resolving.
              `recipes.sh reduce`          (cluster repo)
              `recipes.sh reduce OfficeAgent`
  harness-ctr the container tier asked DIRECTLY over :2222 (not docker
              exec) <- FAST PATH.  Use `harness` when a container may be
              BROKEN: this one reports (unreachable) and loses the columns
              that say why.  bench/ctr-bench.sh measures the difference.
  disperse    the 1->N HALF of reduce: fast-forward every box TO the tip
              <- reduce answers only about the driver.  MEASURED: reduce
              said `contained` on 5/5 while the boxes held 5 DIFFERENT
              heads.  --ff-only, so a box with its own commits REFUSES
              (feed it back through reduce) instead of growing a 2nd tip.
              `recipes.sh disperse`
  broadcast   COPY one dir OR one DOCKER IMAGE from one box to every
              peer, over the MESH  <- the ONLY recipe that WRITES;
              every other one reads
              `recipes.sh broadcast c02 OfficeAgent`        (dir, rsync)
              `recipes.sh broadcast c02 officeagent:devlatest` (image,
                                                        save|load)
              The arm is chosen by ASKING the source's docker daemon,
              not by looking for a `:` -- a tag typo then fails closed
              instead of falling through to rsync's --delete.
  defend      WSL-CRASH DEFENCE: is every guard armed AND enabled?
              (5 layers, 2 tiers -- NOT the same question as `service`:
               that asks "up now", this asks "does it come BACK")
  capacity    RAM + disk across all three tiers (windows / wsl / container)
  svcmem      RSS of lserver / wwwrootsdx / api-server (pass -t "" + full aliases)
  mesh        FULL N x N ssh :2200 LATENCY SQUARE, every box -> every box
              (31 boxes = 930 dials, self excluded).  Cell = connect ms,
              `*` = self, `X` = dark, `?` = source row never answered.
              Dialled FROM each source box, never from this driver.
              ALWAYS also written to /tmp/fleet_latency.md (MESH_MD=).
  meshcfg     mNN peer blocks in ~/.ssh/config.  THE SHAPE IS 10: five
              each of mNN (:2222 container) and mNNwsl (:2200).  mNNwin
              is GONE -- R-NORELAY bans the Windows sshd it needs.
              Reads the config -- does the ALIAS EXIST?
  harness-mesh  does each box REACH its peers' harness containers on 2222,
              and is devbase (rg/jq/parallel) + api-server there?  Dials
              peer->peer, so it grades the mesh, not this driver's star.
  matrix      THE FULL N-BY-N SQUARE -- every ordered pair, real ssh.
              `matrix` = container tier (:2222), `matrix wsl` = distro
              (:2200).  o=reached X=dark .=diagonal.  A dark ROW cannot
              dial out; a dark COLUMN cannot be reached; one dark CELL is
              a broken pair.  Scales N^2 (5x5=25, 16x16=256, 30x30=900),
              fanned one job per row so wall time is one ROW.

Usage: recipes.sh <name> [-b c01,c02] [-j N]
LIST
    ;;

# ---- ALL THREE STAGES ---------------------------------------------------
stages)
    # The question "is this box ready?" is really three questions, and
    # asking them one at a time is how a half-provisioned box gets called
    # ready.  Run all three, labelled, in order.
    #
    # NOTE THE TIERS DIFFER: stage 1 is root's (packages are machine
    # state), stage 2 is the HUMAN's (the services and their tmux socket
    # belong to them).  That is why this dispatches to the recipes rather
    # than merging their probes -- each already carries its own corrected
    # tier, and flattening them would silently ask stage 2 as root and
    # report a false red on every box.
    for st in base service harness; do
        printf '== STAGE %s: %s ==\n' \
            "$(case $st in base) echo 1;; service) echo 2;; harness) echo 3;; esac)" "$st"
        "$0" "$st" "$@"
        printf '\n'
    done
    ;;

# ---- DEPS ---------------------------------------------------------------
base)
    # dpkg -s, NEVER `command -v`: a package name is not a binary name
    # (ripgrep ships `rg`; ca-certificates ships no binary at all), so
    # testing the binary reports a package missing forever.
    "$FS" "$@" \
        rg='dpkg -s ripgrep >/dev/null 2>&1 && echo y || echo NO' \
        jq='dpkg -s jq >/dev/null 2>&1 && echo y || echo NO' \
        parallel='dpkg -s parallel >/dev/null 2>&1 && echo y || echo NO' \
        git='dpkg -s git >/dev/null 2>&1 && echo y || echo NO' \
        gitlfs='dpkg -s git-lfs >/dev/null 2>&1 && echo y || echo NO' \
        tmux='dpkg -s tmux >/dev/null 2>&1 && echo y || echo NO'
    ;;

runtime)
    "$FS" "$@" \
        node='node -v' \
        docker='docker --version | awk "{print \$3}" | tr -d ,' \
        dotnet='dotnet --version || echo -' \
        python='python3 -V | awk "{print \$2}"'
    ;;

copilot)
    "$FS" "$@" copilot='copilot --version | head -1'
    ;;

ghcp)
    # WHO IS DRIVING WHICH BOX RIGHT NOW?  `copilot` above is a DEPS
    # question (is the CLI installed, same version everywhere); this is a
    # PROCS one -- which boxes have a LIVE agent session, what is it
    # called, and what was it last asked.  Added 2026-09-17 on user
    # request: "list each box running copilot with the session name, ip,
    # hostname, latest query (from events.jsonl in session_state)".
    #
    # LIVENESS IS THE LOCK FILE, NOT THE PROCESS LIST.  ~/.copilot/
    # session-state/<uuid>/ holds every session the box has EVER run (6
    # dirs on this host, 1 of them live), so globbing the directories
    # answers "has copilot ever run here" -- a question nobody asked, and
    # one that names a stale session as the current driver.  The CLI
    # writes `inuse.<pid>.lock` into the dir it is ATTACHED to and removes
    # it on exit, so the lock is the only on-box fact that distinguishes
    # the two.  MEASURED: 6 session dirs, 1 inuse lock, pid 28063.
    #
    # BUT A LOCK OUTLIVES A CRASH, so the pid is re-checked against
    # /proc/<pid>/cmdline.  `kill -0` alone is not enough -- pids are
    # recycled, and a lock left by a killed agent whose number now belongs
    # to some unrelated daemon would report a phantom session.  Matching
    # `copilot` in the cmdline is what makes the row mean "an agent is
    # running", which is the whole claim of the table.
    #
    # ROOT AND THE HUMAN BOTH, because `cNNwsl` lands you as root while a
    # human-run `copilot` writes under /home/<user>.  Globbing only root's
    # state dir is the same false negative that made the `tmux` recipe
    # print "-" fleet-wide for a day.
    #
    # THE QUERY IS THE LAST user.message IN events.jsonl -- the same
    # recovery SKILL.md documents for reading back the utterance.  It is
    # jq'd rather than sed'd because the content is a JSON string with
    # escapes, then newlines and tabs are flattened: a raw newline would
    # end the field mid-value and a TAB would fake a column break in
    # `parallel --tag` output, shifting every cell right.  Truncated to 60
    # chars so one chatty box cannot stretch the table past a terminal.
    #
    # MULTIPLE SESSIONS PER BOX IS THE NORMAL CASE, NOT THE EDGE.  User,
    # 2026-09-17: "not forget lots of box has multiple ghcp running
    # sessions".  MEASURED the same day: m01 ran 2 live sessions, and a
    # `head -1` anywhere in these columns would have reported ONE and
    # looked entirely correct doing it.  So every per-session column emits
    # one field per session and joins them.
    #
    # EACH FIELD IS NUMBERED `1:`, `2:` ... AND THE NUMBER IS THE JOIN.
    # The columns are read POSITIONALLY -- session 2's STATE means nothing
    # unless it lines up with session 2's NAME -- and position alone is
    # too fragile to carry that.  MEASURED on m01: an unnamed session
    # printed an empty field, so SESSION held one entry while STATE held
    # two ("NOLOG;WAIT/542s"); the eye pairs the FIRST state with the ONLY
    # name and reports the HEALTHY session as NOLOG.  An index makes the
    # pairing explicit, so a dropped or empty field is visible as a gap in
    # the numbering rather than silently shifting every later cell.
    #
    # :trap: `paste -sd"; "` DOES NOT JOIN ON "; " -- IT ALTERNATES.
    # The -d argument is a LIST of delimiters used in rotation, so with
    # three or more sessions the separators cycle `;`, ` `, `;`, ` `.
    # MEASURED on a 4-session fixture:
    #     session n;session n session n;session n
    # Sessions 2 and 3 are divided by a BARE SPACE -- indistinguishable
    # from a space inside a session name, so two sessions read as one.
    # Invisible at N=2 (the only case the fleet had when this was
    # written), which is exactly why it needed a fixture to find.
    # Join on a single character and expand it afterwards.
    #
    # :trap: `${c:-...}` DOES NOT CATCH A WHITESPACE-ONLY MESSAGE.  A
    # message of one space is non-empty to the shell, so the default never
    # fires and the cell renders as blank -- indistinguishable from the
    # `-` that means "no session".  MEASURED on m01: the last user.message
    # was `" "`.  So the value is TRIMMED first, then defaulted, and the
    # three empties get three DIFFERENT words: `(nolog)` no readable log,
    # `(blank)` the user really did send whitespace, `-` no live session.
    #
    # IP EXCLUDES DOCKER/WSL-NAT SPACE.  `hostname -I` returns three
    # addresses on these boxes -- 10.30.x is the mesh one, 172.17/172.25
    # are docker0 and the NAT bridge, and neither is reachable from a
    # peer.  The route lookup asks "which source address leaves this box",
    # which is the one that answers "where do I reach this session".
    # :trap: AN EMPTY QUERY IS NOT "WAITING FOR INPUT".  User asked
    # 2026-09-17: "if query is -, means the GHCP is waiting user input?"
    # It does not, and the three causes are indistinguishable in that one
    # cell -- which is why STATE was added rather than the `-` reinterpreted:
    #   1. NO LIVE SESSION       m03: no lock at all, box is idle
    #   2. UNREADABLE events.jsonl  m01: MEASURED two live locks, one dir
    #      with events.jsonl MISSING (7ba4caa0) beside a healthy 3.8M one.
    #      A session dir exists before its log does, so the blank was a
    #      RACE, not a state -- and read as "idle" it is a false negative.
    #   3. GENUINELY WAITING     m05: turn ended, agent idle at the prompt.
    # Only the third is the user's reading, and it was 1 of 5 boxes.
    #
    # STATE IS THE LAST EVENT TYPE, because that is what distinguishes
    # them.  `assistant.turn_end` = the agent stopped and the prompt is
    # the user's -> WAIT.  `tool.execution_start` / `assistant.message`
    # = mid-turn -> BUSY.  `session.error` -> ERR (MEASURED on m02; it
    # would otherwise read as WAIT, which is exactly backwards -- nobody
    # is waiting, it fell over).  The AGE beside it is what makes WAIT
    # legible: WAIT/3s is a human typing, WAIT/2898s is an abandoned box.
    #
    # :trap: ERR DOES NOT MEAN THE WORK FAILED, AND THE COLUMN CANNOT SAY
    # WHICH.  MEASURED 2026-09-17 on c01 session d92d5830 (`ERR/384s`):
    # the tail order was
    #     session.task_complete -> assistant.turn_end -> session.error x2
    # i.e. the agent FINISHED, then the run died delivering telemetry --
    #     "session event delivery failed: session host did not
    #      acknowledge the session.usage_info event within 120s"
    # A crashed mid-turn agent and a completed one whose usage_info
    # timed out both print ERR.  Before treating an ERR row as lost work,
    # read the tail: a `session.task_complete` BEFORE the error means the
    # task landed and only the telemetry hop failed.
    #     grep -ao '"type":"[a-z._]*"' events.jsonl | tail -4
    # Deliberately NOT split into a second state here: the distinction
    # needs the event ORDER, not the last event, and this column is
    # defined as the last event type.  Widening it would hide that.
    #
    # LSAGE IS THE CORROBORATION, and it is a SEPARATE FACT, not a
    # verdict.  The user asked to "confirm by same box lserver activity":
    # lserver is the model proxy, so a BUSY agent must be making requests
    # and a truly idle one must not.  MEASURED 2026-09-17:
    #     m04  BUSY/0s     lsage 0s      <- agent mid-turn, proxy hot
    #     m05  WAIT/2898s  lsage 2898s   <- IDENTICAL, genuinely parked
    #     m02  ERR/282s    lsage 7532s   <- proxy cold 2h before the error
    # The two ages agreeing is the confirmation; a BUSY beside a stale
    # LSAGE is the disagreement worth looking at.  They are printed as two
    # columns rather than merged into one "confirmed" flag because
    # collapsing them would hide exactly that disagreement -- and a fleet
    # verdict is what R-FLEET forbids.
    #
    # :trap: LSAGE IS PER *BOX*, NOT PER SESSION, SO ON A MULTI-SESSION
    # BOX IT CANNOT CONFIRM ANY SINGLE ONE.  One proxy serves every agent
    # on the machine, so its mtime is the MOST RECENT request from ANY of
    # them: with 2 live sessions a hot LSAGE proves only that at least one
    # is working, and pairing it with `1:WAIT` would be a fabricated
    # confirmation.  It is deliberately NOT numbered -- the missing index
    # is the signal that it belongs to the row, not to a session.  Read it
    # against the BUSIEST session in STATE; it can refute "everything is
    # parked" (stale LSAGE, no BUSY) but cannot single out a culprit.
    #
    # :trap: LSERVER IS ON THE **HUMAN'S** SOCKET, NOT ROOT'S.  A bare
    # `tmux capture-pane -t lserver` as root returned 0 lines on 5/5 --
    # a clean, uniform, entirely false "every proxy is dead".  (SKILL.md
    # says lserver moved to root with the bundle's supervisor; MEASURED
    # here it answers on uid 1000 and root's socket does not exist at
    # all.)  Rather than `su -l` per box, LSAGE reads the LOG DIRECTORY
    # mtime -- it needs no socket, no tier and no user, so it cannot
    # produce that false negative.
    #
    # TWO LAYERS NOW DRIVE AGENTS ON ONE BOX, NOT ONE.  User 2026-09-19:
    # "our box not only the wsl one, but also the container ... ghcp should
    # list more running CLI sessions".  MEASURED the same day: copilot is
    # installed inside the harness container (/usr/local/bin/copilot on 5/5)
    # and runs LIVE sessions the old wsl-only sweep never saw -- c01 had 1
    # inuse lock in the container, c02 had 2, c05 had 1.  A driver box is a
    # STACK: the WSL distro AND the officeagent container each keep their
    # own ~/.copilot/session-state, so `ghcp` must read both.
    #
    # TWO ssh CALLS, ONE PER TIER -- AND `-t ctr`, NOT `docker exec`.
    # This was `docker exec` from inside a single wsl probe.  User asked
    # 2026-09-19 to rework it after the commit-history claim was verified:
    # MEASURED by bench/ctr-bench.sh (commit dcedc2f), dialling the
    # container's :2222 DIRECTLY on the box's mesh ip is ~10x faster than
    # `docker exec` over the wsl relay -- 582ms vs 5627ms at 1 field, and
    # FLAT in field count (9.7x / 9.9x / 9.3x at 1/4/8 fields) because the
    # gap is the RELAY HOP (ProxyCommand -> Windows -> WSL) that must land
    # BEFORE `docker exec` can fork, not the fork itself.  `-t ctr` is one
    # hop on the fast subnet.  It ALSO deletes the three-shell quoting
    # sandwich (`docker exec "$C" cat`, nested `"`/`\$`), which is the
    # quoting-death class SKILL.md documents -- inside the container the
    # session-state files are read DIRECTLY (`cat`, `stat`), not through a
    # nested shell, and /proc/<pid> is the container's own namespace so the
    # pid re-check needs no `docker exec` at all.
    #
    # THE TWO-CALL MERGE IS SAFE BECAUSE IT JOINS ON RAW KEYED RECORDS, NOT
    # ON A RE-SPLIT PADDED ROW.  Merging two RENDERED tables by re-splitting
    # their columns on runs of spaces was rejected before (positional
    # collapse -- the exact failure fleet-ssh.sh exists to prevent).  This
    # does NOT do that: BOTH tiers run with `fleet-ssh.sh -R`, which SKIPS
    # the pivot and emits one `box<TAB>col<TAB>value` record per cell (plus a
    # leading `#BOXES<TAB>...` scope line).  The merge awk reads with FS=TAB,
    # so the value is a SINGLE field -- any spaces inside it (the " | "
    # session join) are structural data, never a column boundary.  The join
    # key is `(box, toupper(col))`.  So `-t ctr` being a separate `$FS`
    # invocation (a different tier cannot share one call) costs nothing in
    # fidelity, and a box dark on BOTH tiers still gets an `(unreachable)`
    # row because `#BOXES` carries the full scope independently of records.
    #
    # THE TAG IS THE LAYER LETTER, `w`=WSL `c`=container, PREFIXED TO THE
    # INDEX: `w1:`, `c2:`.  The index alone was already the join WITHIN a
    # layer (session 2's STATE is meaningless unless it pairs with session
    # 2's NAME); with both layers in one cell the same reasoning demands the
    # layer be visible, or the container's `c1:BUSY` pairs with the distro's
    # `w1:WAIT` name.  The letter answers the user's actual question -- which
    # LAYER is this agent on -- straight from the cell.
    #
    # :trap: PROVE `-t ctr` LANDED.  A container probe that silently answers
    # from the DISTRO is the documented `-t ctr` failure (unresolved wsl
    # alias routes back through the relay).  The control is CHOST: the
    # container's /etc/hostname carries the `...ctr` suffix, the box's does
    # not.  This recipe does not render CHOST, but the assertion is the same
    # one bench/ctr-bench.sh gates on -- if a c-cell ever shows the box's
    # bare hostname where a container answer was expected, the tier did not
    # land.  (The container has NO `hostname` BINARY, so /etc/hostname is
    # the only source -- irrelevant to the columns here, which keep the
    # BOX's wsl identity for HOST/IP since the physical box is one machine
    # whichever layer the agent runs in.)
    #
    # :trap: A DARK CONTAINER TIER CONTRIBUTES NO `c*` FIELDS, and the wsl
    # row renders unchanged.  A box whose container sshd is down returns
    # (unreachable) from the `-t ctr` call -- `_merge` then simply finds no
    # c-cell for it and prints the w-cell alone.  The wsl half is NEVER lost
    # to a container-side failure because the two calls are independent.
    # (This is the tradeoff dcedc2f names: `-t ctr` cannot DIAGNOSE a
    # down-sshd box the way `docker exec` can -- but `ghcp` is a liveness
    # read, not an sshd-down diagnosis, so the fast path is the right one.
    # `harness` keeps `docker exec` precisely because it must answer on a
    # box whose container sshd is down.)
    _live='for l in /root/.copilot/session-state/*/inuse.*.lock /home/*/.copilot/session-state/*/inuse.*.lock; do [ -e "$l" ] || continue; q=${l##*/inuse.}; q=${q%.lock}; grep -aqs copilot /proc/$q/cmdline || continue; printf "%s\n" "${l%/*}"; done | sort -u'
    # Per-session field renderers, parameterised only by the TAG letter now.
    # BOTH tiers read the session-dir files DIRECTLY (cat/stat): the wsl
    # call runs in the distro, the `-t ctr` call runs INSIDE the container,
    # so neither needs `docker exec`.  Same numbered+tagged records; the two
    # tiers are joined by `_merge`, not concatenated in one probe.
    _sess='{ i=0; while read -r d; do i=$((i+1)); n=$(cat "$d/workspace.yaml" 2>/dev/null | sed -n "s/^name: //p" | head -1 | cut -c1-36); printf "TAG%s:%s\n" "$i" "${n:-(unnamed)}"; done; }'
    _stat='{ i=0; while read -r d; do i=$((i+1)); if ! cat "$d/events.jsonl" >/dev/null 2>&1; then printf "TAG%s:NOLOG\n" "$i"; continue; fi; e=$(cat "$d/events.jsonl" 2>/dev/null | tail -1 | jq -r .type 2>/dev/null); a=$(( $(date +%s) - $(stat -c %Y "$d/events.jsonl") )); case "$e" in assistant.turn_end) s=WAIT;; session.error) s=ERR;; "") s=NOLOG;; *) s=BUSY;; esac; printf "TAG%s:%s/%ss\n" "$i" "$s" "$a"; done; }'
    _qry='{ i=0; while read -r d; do i=$((i+1)); if ! cat "$d/events.jsonl" >/dev/null 2>&1; then printf "TAG%s:(nolog)\n" "$i"; continue; fi; c=$(cat "$d/events.jsonl" 2>/dev/null | grep -a "\"type\":\"user.message\"" | tail -1 | jq -r ".data.content // empty" 2>/dev/null | tr "\n\t" "  " | sed "s/^ *//; s/ *$//" | cut -c1-44); printf "TAG%s:%s\n" "$i" "${c:-(blank)}"; done; }'
    w_sess=${_sess//TAG/w}; w_stat=${_stat//TAG/w}; w_qry=${_qry//TAG/w}
    c_sess=${_sess//TAG/c}; c_stat=${_stat//TAG/c}; c_qry=${_qry//TAG/c}
    # Join the numbered records for one tier+column into a single " | "
    # field.  (paste -sd"|" then expand; NOT paste -sd"; " -- that -d is a
    # delimiter LIST and ALTERNATES at N>=3, splitting two sessions on a
    # bare space.)  Empty stays "-".
    _join='{ paste -sd"|" | sed "s/|/ | /g"; } | grep . || echo -'

    # THE MERGE JOINS ON RAW KEYED RECORDS, NOT ON PADDED COLUMNS.  Both
    # tiers are run with `-R`, which emits `box<TAB>col<TAB>value` and skips
    # the pivot -- so the value is one TAB-delimited field and the join key
    # is `(box,col)`.  Re-splitting two RENDERED tables on runs of spaces
    # (the earlier draft) is the positional-collapse failure fleet-ssh.sh
    # exists to prevent: a QUERY like `git  clone` (two spaces) would
    # mis-split.  With `-R` there is nothing after the value to re-split.
    #
    # --- WSL tier (-R): box identity (ip/host/lsage) + w-tagged session cols
    wsl=$("$FS" -R "$@" \
        session="{ $_live | $w_sess; } | $_join" \
        ip='ip -4 route get 1.1.1.1 2>/dev/null | sed -n "s/.*src \([0-9.]*\).*/\1/p" | head -1' \
        host='hostname' \
        state="{ $_live | $w_stat; } | $_join" \
        lsage='f=$(find /workspace/L-server -type f -name "*.json" -printf "%T@\n" 2>/dev/null | sort -rn | head -1); [ -n "$f" ] && echo $(( $(date +%s) - ${f%.*} ))s || echo -' \
        query="{ $_live | $w_qry; } | $_join")

    # --- CONTAINER tier (-R, -t ctr): c-tagged session cols over the FAST
    # path.  Same probes, read natively inside the container.
    ctr=$("$FS" -R -t ctr "$@" \
        session="{ $_live | $c_sess; } | $_join" \
        state="{ $_live | $c_stat; } | $_join" \
        query="{ $_live | $c_qry; } | $_join")

    # --- MERGE + PIVOT.  Both inputs are `box<TAB>col<TAB>value`.  We key
    # every value on (box,col), pair the w- and c-cells for the three shared
    # session columns into `w… | c…`, keep ip/host/lsage from wsl, and pivot
    # to one padded row per box.  The box set and column order are fixed
    # here (this recipe owns them), so a box that answered on neither tier
    # still prints one `(unreachable)` row -- the same contract the wrapper
    # keeps.
    # ROW ORDER + THE UNREACHABLE ROW.  awk cannot invent a row for a box it
    # never saw, so a box dark on BOTH tiers would silently vanish.  The wsl
    # tier is the box's own distro: if IT is unreachable the box is dark to
    # this driver entirely (the same stage-0 fact the wrapper reports as
    # `(unreachable)`), so its ABSENCE here is that same signal -- there is
    # no live agent to list because the box is not answering at all.  A box
    # reachable on wsl but dark on ctr DOES appear (wsl records exist); its
    # c-cells are simply empty, which is the down-container case.
    { printf '%s\n' "$wsl"; printf '%s\n' "$ctr" | sed "s/^/CTR\t/"; } | awk -F'\t' '
    function join2(w,c){
        if (w=="-") w=""; if (c=="-") c="";
        if (w!="" && c!="") return w " | " c;
        if (w!="") return w;
        if (c!="") return c;
        return "-";
    }
    BEGIN {
        nH=split("SESSION IP HOST STATE LSAGE QUERY", H, " ");
        PAIR["SESSION"]=1; PAIR["STATE"]=1; PAIR["QUERY"]=1;
    }
    # With FS=TAB the value is a SINGLE field ($NF) -- spaces inside it (the
    # " | " session join) are preserved, never re-split.  ctr records carry
    # a leading CTR field: box=$2 col=$3 value=$4; wsl: box=$1 col=$2 value=$3.
    # Each `-R` stream starts with `#BOXES<TAB>c01,c02,...` -- the FULL scope,
    # so a box dark on BOTH tiers still gets an `(unreachable)` row.
    /^#BOXES\t/ || /^CTR\t#BOXES\t/ { s=$0; sub(/^(CTR\t)?#BOXES\t/,"",s);
        m=split(s, SB, ","); for(x=1;x<=m;x++) if(SB[x]!="" && !(SB[x] in ord)) ord[SB[x]]=1; next }
    $1=="CTR" { b=$2; k=$3; v=$4;
                c[b, toupper(k)]=v; seenc[b]=1; if(!(b in ord))ord[b]=1; next }
    { b=$1; k=$2; v=$3;
      w[b, toupper(k)]=v; seenw[b]=1; if(!(b in ord))ord[b]=1 }
    END {
        # order the boxes: every box in scope (from #BOXES), sorted (c01..c0N)
        n=asorti(ord, KEYS);          # KEYS[1..n] = sorted box names
        wbox=3;
        for (i=1;i<=n;i++){ b=KEYS[i]; if(length(b)>wbox) wbox=length(b) }
        for (j=1;j<=nH;j++) wid[j]=length(H[j]);
        for (i=1;i<=n;i++){
            b=KEYS[i]; reach=(seenw[b]||seenc[b]);
            for (j=1;j<=nH;j++){
                h=H[j];
                if (!reach) cell[i,j]=(j==1?"(unreachable)":"");
                else if (h in PAIR) cell[i,j]=join2((w[b,h]==""?"-":w[b,h]),(c[b,h]==""?"-":c[b,h]));
                else cell[i,j]=(w[b,h]==""?"-":w[b,h]);
                if (length(cell[i,j])>wid[j]) wid[j]=length(cell[i,j]);
            }
        }
        printf "%-*s", wbox+2, "BOX";
        for (j=1;j<=nH;j++) printf "%-*s", wid[j]+2, H[j];
        printf "\n";
        for (i=1;i<=n;i++){
            printf "%-*s", wbox+2, KEYS[i];
            for (j=1;j<=nH;j++) printf "%-*s", wid[j]+2, cell[i,j];
            printf "\n";
        }
    }'
    ;;

sessions)
    # Plan 35 2.2.  The collector did the work on each box; this only
    # fetches the file and hands the -R records to the renderer.  ONE tier:
    # the container has no session-state (MEASURED 0 dirs on cj00/01/06/08/10),
    # so SPLIT BY TIER has nothing to split.  PRIVATE data -- authenticated
    # ssh only, never the banner (33-D3).
    "$FS" -R "$@" j='cat /run/orch/sessions.json 2>/dev/null || echo -' |
        python3 "$(dirname "$0")/../../../bin/orch-collect.py" --render
    ;;

clean)
    # THE REAPER FOR `ghcp`.  That recipe ANSWERS "who is driving"; this one
    # ACTS on the answer -- remove the session state nothing is running, and
    # optionally stop agents that have been parked past a threshold.
    #
    #   recipes.sh clean                 # REPORT: what WOULD go.  The default.
    #   recipes.sh clean --apply         # remove STALE dirs only
    #   recipes.sh clean --apply --idle 86400   # ALSO kill sessions parked >24h
    #   recipes.sh clean -b c03          # one box
    #
    # :*** THIS IS THE ONLY RECIPE THAT DESTROYS. *** `broadcast` writes;
    # this one deletes directories and signals processes.  Two consequences
    # follow and both are deliberate:
    #
    #   1. IT DEFAULTS TO REPORT.  A bare `recipes.sh clean` changes nothing
    #      on any box; `--apply` is required.  A destructive default would
    #      make a typo'd box list irreversible, which is exactly the trap
    #      `broadcast`'s `--delete` arm documents.
    #   2. IT IS A SCRIPT FANNED OUT, NOT A PROBE STRING.  SKILL.md's "When
    #      NOT to use it" says a state change goes in a script (R-REPEATABLE)
    #      -- so the logic lives in ghcp-clean.sh, is graded by
    #      bench/clean-bench.sh against a FIXTURE, and rides to the box on
    #      stdin.  Building this as a quoted one-liner per box would put
    #      `rm -rf` through the quoting layers that SKILL.md records as the
    #      "quoting death" failure class.
    #
    # KILLING IS OPT-IN SEPARATELY FROM DELETING, because they are different
    # claims.  Removing a STALE dir reclaims disk from a session that already
    # ended -- it cannot lose work.  Killing an IDLE session ENDS A LIVE
    # AGENT, and "parked 24h" is a heuristic, not a fact about whether its
    # human is done.  MEASURED 2026-09-21: c04's only session was
    # WAIT/213007s -- 2.5 days parked, and still the box's sole driver.  So
    # `--idle` must be typed, with its threshold, every time.
    #
    # :trap: NEVER REAP ON THE LOG STATE ALONE.  `ghcp` shows NOLOG for both
    # a corpse and a session whose events.jsonl has not been created yet.
    # The lock+pid is what separates them, and ghcp-clean.sh classes
    # NOLOG-with-a-live-pid as LIVE for that reason.
    #
    # :trap: THE DRIVER IS ONE OF THE BOXES.  MEASURED here: this driver is
    # a container on c01, so an unguarded sweep deletes the state of the
    # session running it.  $COPILOT_AGENT_SESSION_ID is passed as PROTECT so
    # the reaper skips its own caller by id, on every box (the id is unique,
    # so naming it fleet-wide is safe and needs no box match).
    #
    # See ghcp-clean.sh's header for the three measured hazards -- one pid
    # holding several sessions, the second registry, and this driver being
    # inside the fleet.
    mode=report; kill_idle=0; idle_age=86400; pass=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --apply)  mode=apply; shift;;
            --idle)   kill_idle=1; idle_age=${2:?--idle needs seconds}; shift 2;;
            --dry-run|--report) mode=report; shift;;
            *)        pass+=("$1"); shift;;
        esac
    done
    # SCOPE comes from -b, or the discovered box list -- same source the
    # wrapper uses, never a hardcoded one.
    boxes=${FLEET_SSH_BOXES:-}
    i=0; while [ $i -lt ${#pass[@]} ]; do
        [ "${pass[$i]}" = "-b" ] && boxes=${pass[$((i+1))]}
        i=$((i+1))
    done
    # DISCOVERY IS THE WRAPPER'S, NOT A SECOND COPY OF IT.  A hand-rolled
    # `sed '/^Host cNNwsl/'` was written here first and returned NOTHING on
    # this driver -- it missed the `Host cNN cNNwsl` multi-name form that
    # fleet.py emits, so a full-fleet `clean` reported "no boxes in scope"
    # while `fleet-ssh.sh` found all six.  Two discoveries means two answers;
    # ask the one that already works (`-R` prints its scope as #BOXES).
    if [ -z "$boxes" ]; then
        boxes=$("$FS" -R -b '' true=true 2>/dev/null | sed -n 's/^#BOXES\t//p' | head -1)
        [ -n "$boxes" ] || boxes=$(awk '$1=="Host"{for(i=2;i<=NF;i++)print $i}' \
            "${FLEET_SSH_CONFIG:-$HOME/.ssh/config}" \
            | grep -oE '^[cC][0-9]+' | tr 'A-Z' 'a-z' | sort -u | paste -sd,)
    fi
    [ -n "$boxes" ] || { echo "clean: no boxes in scope" >&2; exit 2; }

    printf '== clean %s  MODE=%s' "$boxes" "$mode"
    [ "$kill_idle" = 1 ] && printf '  --idle %ss' "$idle_age"
    printf ' ==\n'
    [ "$mode" = apply ] || printf '== REPORT ONLY -- nothing is removed.  Add --apply to act. ==\n'
    [ "$kill_idle" = 1 ] && [ "$mode" = apply ] && \
        printf '== PARKED SESSIONS WILL BE KILLED (lone pids only; shared pids are vetoed) ==\n'

    # NOT THROUGH THE TABLE WRAPPER, and for the same reason `broadcast` is
    # not: fleet-ssh.sh takes only the FIRST LINE of each box's output
    # (SKILL.md "built for reading"), so a table would print the counts line
    # and silently discard every RM/KILL/VETO record beneath it -- the exact
    # detail that says WHICH session was destroyed.  A destructive recipe
    # must report per act, so this fans the script out with `parallel --tag`
    # and prints every line each box returns.
    #
    # The script is read ONCE and handed to every box on stdin, so all boxes
    # run byte-identical logic and nothing re-quotes `rm -rf` on the way.
    script=$HERE/ghcp-clean.sh

    # BOTH TIERS, BECAUSE `ghcp` READS BOTH.  A driver box is a STACK: the
    # WSL distro and the harness container each keep their own
    # ~/.copilot/session-state.  MEASURED 2026-09-21: the container tier held
    # 13 more dirs on c02 and 1 on c05 that a wsl-only sweep never sees -- so
    # cleaning one tier reports a tidy fleet while half of the garbage
    # remains, which is the "uniform column, wrong probe" failure this skill
    # keeps finding.
    #
    # THE DIAL IS RESOLVED THE WAY fleet-ssh.sh RESOLVES IT, not reinvented.
    # `ctr` is a PORT, not a suffix, so it cannot be written as `{}$TIER`;
    # and `ssh -G` does NOT always yield an address (MEASURED: it returns the
    # ALIAS, with the real host buried in the ProxyCommand, which sent every
    # container probe back through the relay to the DISTRO and answered with
    # no error).  So the inventory is preferred and `ssh -G` is the fallback
    # -- exactly the order fleet-ssh.sh uses, for exactly that reason.
    ips="${FLEET_IPS:-$FIPS}"
    cfg="${FLEET_SSH_CONFIG:-$HOME/.ssh/config}"
    for tier in wsl ctr; do
        # Build `box <TAB> ssh-args` up front, one line per box, so the
        # parallel body is a plain dial with nothing to re-resolve.
        spec=""
        for box in ${boxes//,/ }; do
            if [ "$tier" = wsl ]; then
                spec="$spec$box	-	-	${box}wsl
"
            else
                hn=$(python3 -c "import json,sys;print(json.load(open(sys.argv[2]))[sys.argv[1]].split()[0])" \
                       "$box" "$ips" 2>/dev/null)
                [ -n "$hn" ] || hn=$(ssh -F "$cfg" -G "${box}wsl" 2>/dev/null | awk '/^hostname /{print $2; exit}')
                case "$hn" in ""|*wsl) continue;; esac   # unresolved alias -> no ctr route
                idf=$(ssh -F "$cfg" -G "${box}wsl" 2>/dev/null | awk '/^identityfile /{print $2; exit}')
                spec="$spec$box	${FLEET_SSH_CTR_PORT:-2222}	${idf:--}	root@$hn
"
            fi
        done
        [ -n "$spec" ] || { printf -- '-- tier %s: no route --\n' "$tier"; continue; }
        printf -- '-- tier %s --\n' "$tier"
        # :trap: THE PARALLEL BODY IS DOUBLE-QUOTED, SO A BACKTICK IN A
        # COMMENT INSIDE IT IS STILL COMMAND SUBSTITUTION.  bash expands the
        # whole string before any shell sees a '#', so a prose comment written
        # as (backtick)unreachable(backtick) ran `unreachable` on the DRIVER
        # and printed "command not found" beside a correct table.  Comments
        # inside this body use plain words, never backticks.
        #
        # TAG EVERY LINE WITH {1}, AND DO NOT USE --tag.  Two separate
        # bugs, both MEASURED here:
        #   1. `--tag` prepends the WHOLE input line, which is
        #      `box<TAB>ssh-args` -- so every output line carried the private
        #      key path and the `root@<ip>` of the box being cleaned.
        #   2. Tagging only the FIRST line loses the box name on the RM/KILL
        #      records beneath it, which are the lines that say what was
        #      destroyed.  This recipe is multi-line per box by design (that
        #      is why it bypasses the table), so the tag is applied with
        #      `sed` to EVERY line.
        printf '%s' "$spec" \
          | parallel --colsep '\t' -j"${CLEAN_J:-5}" "
              out=\$(timeout ${CLEAN_TIMEOUT:-300} ssh -o BatchMode=yes -o ControlPath=none \
                      -o ConnectTimeout=15 -o StrictHostKeyChecking=no \
                      \$( [ '{2}' = - ] || echo -p '{2}' ) \
                      \$( [ '{3}' = - ] || echo -i '{3}' ) \
                      \$( [ '{2}' = - ] || echo -o UserKnownHostsFile=/dev/null ) \
                      {4} \
                      'MODE=$mode KILL_IDLE=$kill_idle IDLE_AGE=$idle_age PROTECT=\"${COPILOT_AGENT_SESSION_ID:-}\" bash -s' \
                      < '$script' 2>&1); rc=\$?
              # WHITELIST THE RECORD GRAMMAR, DO NOT BLACKLIST THE NOISE.
              # MEASURED: the container's login shell prints an MOTD banner
              # (\"Welcome to Microsoft Azure Linux 3.0\"), and the WSL shells
              # print setlocale warnings -- a blacklist grows one entry per
              # distro and silently passes whatever it has not met yet.  The
              # script emits exactly four record shapes, so anything else is
              # not output of ours and is dropped.
              recs=\$(echo \"\$out\" | grep -E '^(RM=|RM |KILL |VETO )')
              # EVERY BOX IN SCOPE GETS A ROW, INCLUDING A DEAD ONE.  The
              # whitelist above is what makes this necessary: a box that
              # never answered emits only ssh's error text, which the
              # whitelist correctly drops -- and then the box DISAPPEARS from
              # a report about what is being deleted.  MEASURED: c06 (down)
              # printed nothing at all, so a five-box report looked complete.
              # Silence and success must never render the same, so an empty
              # record set becomes an explicit cell -- the same contract the
              # table wrapper keeps with its (unreachable) cell.
              if [ -z \"\$recs\" ]; then
                if [ \$rc -eq 0 ]; then recs='(no sessions)'; else recs='(unreachable)'; fi
              fi
              printf '%s\\n' \"\$recs\" | sed 's/^/{1}\t/'" 2>/dev/null
    done
    ;;

images)
    "$FS" "$@" \
        officepy='docker image inspect mcr.microsoft.com/officepy/officepyjupyterbase4:16.0.20224.44901 >/dev/null 2>&1 && echo y || echo NO' \
        aspnet='docker image inspect mcr.microsoft.com/dotnet/aspnet:10.0-azurelinux3.0 >/dev/null 2>&1 && echo y || echo NO' \
        officeagent='docker image ls --format "{{.Repository}}:{{.Tag}}" | grep -c "^officeagent:"'
    ;;

# ---- PROCS --------------------------------------------------------------
service)
    # Runs on the HUMAN tier (-t u) deliberately: the services are the
    # human's and their tmux server lives on the human's socket.  Asking
    # as root finds no session and reports a false red.
    # The PANE LINE COUNT is the point -- a session routinely outlives the
    # process it was created for, so `has-session` passes on a corpse.
    #
    # :THE_WSL_TIER_RUNS_THREE_SERVICES, NOT TWO (plan 06 G7, user
    # 2026-09-17: "not in service stage, we have 3 serice").  They are
    # supervised THREE DIFFERENT WAYS, which is why one probe shape does
    # not fit all of them:
    #
    #   lserver         11434  tmux + wam-lserver-tmux   root's tmux socket
    #   wwwrootsdx-mcp  47390  tmux -S explicit sock      human's tmux socket
    #   fleet-token     11435  systemd Restart=always     NEITHER socket
    #
    # :trap: fleet-token IS NOT A TMUX SESSION, so do not look for one.
    # It is a systemd unit on the ROOT tier that answers over HTTP.  A
    # loopback curl works from either tier, so it rides this `-t u` sweep
    # unchanged -- no tier split needed.  Asked as a pane it would be a
    # permanent false red.
    #
    # :trap: A BOUND :11435 IS NOT A WORKING TOKEN SERVER.  When the WAM
    # broker fails, the port still answers -- with HTTP 500 and a JSON
    # `{"error": ...}` body.  So grade a REAL MINT (a non-empty
    # access_token), not the listener.  MEASURED 2026-09-17: warm 20-24ms,
    # cold 998-1251ms, so the stronger signal costs nothing.  This is the
    # same false-green that let :11434 and :47390 read green on 5/5 while
    # lserver was unreachable on 5/5.
    "$FS" -t u "$@" \
        lserver='tmux capture-pane -t lserver -p | grep -vc "^$"' \
        p11434='curl -s --max-time 3 http://127.0.0.1:11434/health >/dev/null && echo ok || echo DOWN' \
        mcp='test -S ~/.local/state/wwwrootsdx/mcp.sock && echo sock || echo NO' \
        p47390='ss -lnt | grep -qc 47390 && echo LISTEN || echo off' \
        token='curl -s --max-time 20 http://127.0.0.1:11435/token/ado | grep -c access_token | sed "s/^1$/mint/; s/^0$/DOWN/"'
    ;;

harness)
    # The three stage-3 checkpoints in one table: H1 image, H2 api,
    # H3 emacs -- PLUS four readiness columns added 2026-09-17: ENGINE,
    # REPO, EXCEL, WV2.  User: "update fleet_ssh recipe for harness
    # readiness include docker engine, excel, wv2, OfficeAgent repo".
    #
    # H1 asserts the LISTENER, not `docker ps`: docker-proxy answers at
    # the TCP layer whether or not sshd is behind it, and what starts that
    # sshd is /bin/entry -- which only exists once devbase is unbundled.
    # H2 NEEDS BOTH h2_state AND h2_pane.  A non-empty pane is necessary
    # and NOT sufficient: measured 2026-09-13, both boxes showed
    # h2_pane=9 while dev-loop had already EXITED -- the 9 lines were its
    # own crash output.  OfficeAgent's dev-loop-tmux.sh status is the
    # authority (HEALTHY vs BROKEN); the pane count only tells you the
    # session is not blank.  H2 passes on HEALTHY, never on lines alone.
    # H3 is last because emacs is the ONLY container-layer artifact
    # (measured: /bin/entry and /app/officepy are in the image, emacs is
    # not), so it is the only thing a re-create destroys.
    #
    # :trap: EVERY docker CALL IS NOW `timeout`-BOUNDED.  MEASURED
    # 2026-09-17: c03's dockerd sat in `activating` (systemd Job pending,
    # Main PID present, socket triggered but never came up) and a bare
    # `docker ps` against it blocked the ENTIRE fleet-wide sweep for
    # 10+ minutes with zero output -- one box's stuck daemon silently
    # starved the other four rows.  `parallel --tag` buffers per box, so
    # a hang on c03 does not corrupt c01/c02's rows, but it never RETURNS
    # them either: the whole recipe call blocks until the slowest box
    # gives up, and nothing here used to make it give up.  Every `docker`
    # invocation below is wrapped in `timeout N`, so a wedged engine now
    # reports through the ENGINE column (below) instead of hanging the
    # table.
    #
    # ENGINE is the new diagnostic: `systemctl is-active docker` distinguishes
    # active / activating / inactive / failed, which is exactly the fact a
    # timed-out h1_ctr cannot say on its own -- "-" alone does not tell you
    # WHY the container list came back empty.
    #
    # REPO checks the checkout used by H2/H3, not the container: OfficeAgent
    # is bind-mounted from the DISTRO (h2_state's `cd /workspace/OfficeAgent`
    # runs INSIDE the container, but the source of truth for "is stage 3 even
    # possible on this box" is whether the distro's clone exists at all).
    # :*** THE CONTAINER FIELDS COULD GO OVER `-t ctr` AND MOSTLY SHOULD
    # NOT BE REWRITTEN FOR SPEED. ***  MEASURED 2026-09-19 by
    # bench/ctr-bench.sh, 5 boxes:
    #     fields   wsl+docker exec   -t ctr     delta
    #          1   5.20-5.28s        5.00-5.23s  251ms   <- NOISE
    #          4   5.62s             5.43s       187ms
    #          8   6.27s             5.42s      1138ms
    # The win is PER FIELD, not per call (`docker exec` forks a container
    # process per field; `-t ctr` opens ONE ssh session for the whole
    # probe), and even at 8 fields it is ~1s on a ~6s sweep -- dwarfed by
    # one slow box.  Do NOT quote a ratio.
    #
    # The REAL reason `-t ctr` is better here is not the clock: the probes
    # below are a THREE-SHELL quoting sandwich (`sh -c` -> ssh -> `docker
    # exec sh -lc "..."` -> nested `"` and `\$`), which is precisely the
    # quoting-death class SKILL.md documents as returning a confident wrong
    # answer on 4/4.  A `-t ctr` probe is plain shell.
    #
    # It STAYS on docker exec anyway, deliberately: this arm must answer on
    # a box whose container sshd is DOWN -- `h1_2222` exists to detect
    # exactly that -- and a `-t ctr` sweep of that box returns
    # (unreachable) for every field, losing the ENGINE/REPO/H1 columns that
    # say WHY.  A gate that cannot report on a broken container is not a
    # gate.  See `harness-ctr` below for the fast path when :2222 is known
    # good.
    "$FS" "$@" \
        h1_ctr='timeout 5 docker ps --format "{{.Names}}" 2>/dev/null | head -1' \
        h1_2222='ss -lnt | grep -c ":2222 "' \
        engine='timeout 5 systemctl is-active docker 2>/dev/null || echo unknown' \
        repo='test -d /workspace/OfficeAgent/.git && echo y || echo NO' \
        h2_state='C=$(timeout 5 docker ps --format "{{.Names}}" 2>/dev/null | head -1); [ -n "$C" ] && timeout 8 docker exec "$C" sh -lc "cd /workspace/OfficeAgent && bash scripts/dev-loop-tmux.sh status 2>/dev/null | head -1 | sed \"s/ REASON=.*//;s/STATE=//\"" 2>/dev/null || echo NO_CTR' \
        h2_pane='C=$(timeout 5 docker ps --format "{{.Names}}" 2>/dev/null | head -1); [ -n "$C" ] && timeout 8 docker exec "$C" sh -lc "tmux capture-pane -t api-server -p 2>/dev/null | grep -vc \"^\$\"" 2>/dev/null || echo 0' \
        h3_emacs='C=$(timeout 5 docker ps --format "{{.Names}}" 2>/dev/null | head -1); [ -n "$C" ] && timeout 8 docker exec "$C" sh -lc "emacs --version >/dev/null 2>&1 && echo y || echo NO" 2>/dev/null || echo NO_CTR' \
        h3_ghcp='C=$(timeout 5 docker ps --format "{{.Names}}" 2>/dev/null | head -1); [ -n "$C" ] && timeout 8 docker exec "$C" sh -lc "command -v copilot >/dev/null && echo y || echo NO" 2>/dev/null || echo NO_CTR'
    # EXCEL/WV2 are WINDOWS-TIER build deps -- same class as winbuild's
    # node/yarn check above: the WSL tier cannot satisfy them and no
    # container probe will ever notice (H4's own harness runs Excel via
    # COM on the Windows host, never inside the distro).  A second "$FS"
    # call is required, not a fifth field on the first: TIER is a
    # property of the whole call (see fleet-ssh.sh), so a win-tier probe
    # cannot share a row with a wsl-tier one in a single invocation.
    #
    # WV2 is graded PINNED vs VIOLATION the same way pin-wv2-149.ps1
    # -CheckOnly does: compare the EdgeUpdate client's raw runtime version
    # against the BrowserExecutableFolder policy redirect for EXCEL.EXE.
    # R-WV2149 (copilot-instructions.md): 150+ strips
    # WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS and kills the CDP port, so the
    # POLICY value is what matters for Excel specifically -- the raw
    # runtime can (and does, fleet-wide) sit on 153 as long as Excel's
    # redirect points at the pinned 149 tree.
    # :trap: quote the PSObject.Properties INDEXER, not dotted access --
    # `$p.'EXCEL.EXE'` fails silently (empty) through the bash->stdin->
    # powershell relay because the embedded dot confuses the outer quoting;
    # `$p.PSObject.Properties["EXCEL.EXE"].Value` survives the same relay
    # (MEASURED against all five boxes 2026-09-17).
    # :*** THIS RECIPE ASKED THE WINDOWS TIER OVER ssh, WHICH R-NORELAY
    # BANS. ***  The QUESTION is still valid; only the transport was
    # forbidden.  It is not silently downgraded to a WSL answer -- that
    # is precisely the `-t win` silent-hop bug (uname -s returned Linux
    # on 4/4 and read as corroboration).  Use win_probe (WinRM :5985)
    # from a peer in the TARGET's project.
    echo "recipes: this sweep needs the WINDOWS tier, which no longer has ssh." >&2
    echo "  R-NORELAY bans cNNwin (:22 measured dark fleet-wide, by design)." >&2
    echo "  Use win_probe <ip> '<powershell>' -- WinRM :5985, same project." >&2
    exit 2
    ;;

pilot)
    # DEPTH-FIRST: the score is how far the PILOT box has got, not how
    # many boxes cleared checkpoint 1.  User ruling 2026-09-13: "we focus
    # on one box, push to tmux api-servr, then repeat the process for
    # others".  The 4-box table invites breadth -- which is what let the
    # node_modules blocker hide behind H1 for hours, because no box had
    # ever gone past H1.
    B="${PILOT_BOX:-c02}"
    "$FS" -b "$B" "$@" \
        h1_2222='ss -lnt | grep -c ":2222 "' \
        repo='test -d /workspace/OfficeAgent/.git && echo y || echo NO' \
        nm='test -d /workspace/OfficeAgent/node_modules && echo y || echo NO' \
        image='docker image inspect officeagent:devlatest >/dev/null 2>&1 && echo y || echo NO' \
        h2_state='docker exec officeagent-dev sh -lc "cd /workspace/OfficeAgent && bash scripts/dev-loop-tmux.sh status 2>/dev/null | head -1 | sed \"s/ REASON=.*//;s/STATE=//\"" 2>/dev/null' \
        h3_emacs='docker exec officeagent-dev sh -lc "emacs --version >/dev/null 2>&1 && echo y || echo NO" 2>/dev/null' \
        h3_ghcp='docker exec officeagent-dev sh -lc "command -v copilot >/dev/null && echo y || echo NO" 2>/dev/null'
    ;;

winbuild)
    # WINDOWS-TIER BUILD DEPENDENCIES -- same class as Excel and WebView2:
    # the WSL tier cannot satisfy them and no container check will ever
    # notice.  User 2026-09-13: "we need Windows node to build, add this
    # to bo harness, it is same dependency like Excel and wv2".
    # OfficeAgent/package.json:139 requires node >=24 and yarn 4.17.1.
    # :trap: `engines` is a WARNING, not a gate -- npm/yarn proceed on a
    # mismatch and fail later with an unrelated-looking error, so the
    # VERSION must be checked here rather than left to the tool.
    # :trap: `ssh c0Nwin 'bash -c ...'` DOES NOT RUN ON WINDOWS.  It lands
    # in WSL -- measured on c01: bash reports /usr/bin/node v24.20.0 while
    # cmd.exe reports v24.14.0.  TWO DIFFERENT NODES behind one alias.
    # fleet-ssh.sh pipes `bash -s`, so a bare `node -v` under `-t win`
    # would silently measure the LINUX side and report it as Windows.
    # Every probe here goes through cmd.exe so no bash resolves the name.
    # :*** THIS RECIPE ASKED THE WINDOWS TIER OVER ssh, WHICH R-NORELAY
    # BANS. ***  The QUESTION is still valid; only the transport was
    # forbidden.  It is not silently downgraded to a WSL answer -- that
    # is precisely the `-t win` silent-hop bug (uname -s returned Linux
    # on 4/4 and read as corroboration).  Use win_probe (WinRM :5985)
    # from a peer in the TARGET's project.
    echo "recipes: this sweep needs the WINDOWS tier, which no longer has ssh." >&2
    echo "  R-NORELAY bans cNNwin (:22 measured dark fleet-wide, by design)." >&2
    echo "  Use win_probe <ip> '<powershell>' -- WinRM :5985, same project." >&2
    exit 2
    ;;

service-deep)
    # THE SERVICE CHECKPOINT, STRENGTHENED.  User ruling 2026-09-13:
    # "only 11434 listen is not enough, we need call it's REST endpoint to
    # make sure the llm endpoint conected, also for wwwrootsdx, 47390
    # listen in tmux is not enough, we need test it will try to bring up
    # Excel".
    #
    # MEASURED, and the gap is total: /health returned ok on 4/4 while a
    # real completion returned TOKEN_WSL_WAM_BRIDGE_FAILED on 4/4.  So
    # the weak checkpoint was 100% green on a 100% broken fleet.
    #
    # WHY EACH COLUMN IS THE ONE IT IS:
    #   health      the OLD check -- kept only to SHOW the gap
    #   models      still passes when broken: the catalog is static
    #   completion  the first probe that touches the upstream token
    #   mcp_excel   start_session, not tools/list: framing JSON proves the
    #               transport, not that Excel can be driven
    # :trap: the method is `start_session`, NOT MCP's `tools/call` -- this
    # server dispatches the tool NAME directly and answers `tools/call`
    # with "unknown method".  My first probe used tools/call, got an
    # error, and I nearly read it as "the mcp is broken" when the mcp was
    # fine and the PROBE was wrong.
    # PASS looks like `workbookPath`: "start requires a workbookPath"
    # means the call reached Excel-session logic and got as far as
    # validating arguments -- which is exactly "it will TRY to bring up
    # Excel".  `unknown method` means the probe is wrong; `no-tcp` means
    # the transport is down.
    # :trap: assert the RESPONSE SHAPE, never exit 0 -- curl exits 0 on an
    # HTTP 200 carrying an error object, which is exactly this failure.
    "$FS" -t u "$@" \
        health='curl -s --max-time 8 http://127.0.0.1:11434/health | grep -o ok || echo DOWN' \
        models='curl -s --max-time 12 http://127.0.0.1:11434/v1/models | grep -c "\"id\"" || echo 0' \
        completion='curl -s --max-time 30 -X POST http://127.0.0.1:11434/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\":\"gpt-54-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":3}" | grep -oE "TOKEN_[A-Z_]+|\"content\"" | head -1 || echo no-answer' \
        mcp_excel='printf "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"start_session\",\"params\":{}}\n" | timeout 30 nc 127.0.0.1 47390 | grep -oE "workbookPath|unknown method|\"result\"" | head -1 || echo no-tcp'
    ;;

tmux)
    # BOTH TIERS, because the answer differs and only one of them is the
    # one anyone cares about.  MEASURED 2026-09-13 on c01/c02:
    #     root   -> "no server running on /tmp/tmux-0/default"
    #     human  -> "lserver: 1 windows (created ...)"
    # The previous form asked ROOT only and printed "-" on every box --
    # a FALSE NEGATIVE that says "no tmux anywhere" while lserver has
    # been running for a day.  The `service` recipe above already knew
    # this (it runs -t u for exactly this reason); this recipe did not,
    # which is the kind of drift a table makes obvious and prose hides.
    # Kept as ONE table rather than two runs: seeing both columns is what
    # tells you WHICH socket a session is on, and that is the actual
    # question when a service looks dead.
    # THE HUMAN IS RESOLVED BY UID 1000, NOT BY `logname`.  logname reads
    # the controlling terminal's owner, and an ssh probe has no tty, so
    # it returns "logname: no login name" -- MEASURED, and it silently
    # collapsed this whole probe to "-" on all four boxes.  A substitution
    # that fails inside a probe does not error, it just empties the
    # command, which is the false-negative class this skill exists to
    # avoid.  getent runs ON the box and needs no terminal.
    # FOUR SOCKETS, NOT TWO.  The two-column form was already stale when
    # the user asked "why on c02wsl tmux ls" -- it showed lserver and
    # nothing else, and the answer is that THREE tmux servers run on that
    # box and a bare `tmux ls` can only ever see one.  MEASURED on c02
    # 2026-09-14:
    #   root socket                        -> lserver
    #   bazhou default socket              -> NO SERVER
    #   bazhou wwwrootsdx PRIVATE socket   -> wwwrootsdx-mcp
    #   inside officeagent-dev             -> api-server
    #
    # Three separate reasons they cannot share a list, and each one has
    # burned this repo already:
    #  1. a tmux server is PER-USER (/tmp/tmux-<uid>/), so root cannot see
    #     the human's sessions -- and `cNNwsl` lands you as ROOT.
    #  2. lserver MOVED to root when we adopted the bundle's supervisor
    #     (install-tmux-service.sh renders SERVICE_USER=root).  That is
    #     why service-up's own check briefly called a HEALTHY lserver
    #     `not-attachable-or-empty`: it asked the human's socket.
    #  3. wwwrootsdx-mcp is not on a default socket AT ALL -- it uses an
    #     explicit -S under the human's state dir, so even as the human a
    #     bare `tmux ls` misses it.
    #
    # A column per socket is the only honest shape: "which socket is it
    # on" IS the question when a service looks dead.
    "$FS" "$@" \
        root='tmux ls 2>/dev/null | cut -d: -f1 | paste -sd, || echo -' \
        human='H=$(getent passwd 1000 | cut -d: -f1); su -l "$H" -c "tmux ls" 2>/dev/null | cut -d: -f1 | paste -sd, || echo -' \
        mcp_sock='H=$(getent passwd 1000 | cut -d: -f1); D=$(getent passwd 1000 | cut -d: -f6); su -l "$H" -c "tmux -S $D/.local/state/wwwrootsdx/tmux.sock ls" 2>/dev/null | cut -d: -f1 | paste -sd, || echo -' \
        container='docker exec officeagent-dev tmux ls 2>/dev/null | cut -d: -f1 | paste -sd, || echo -'
    ;;

listeners)
    "$FS" "$@" ports='ss -lnt | grep -oE ":[0-9]+ " | tr -d ": " | sort -un | paste -sd,'
    ;;

disk)
    "$FS" "$@" \
        free='df -h /workspace | awk "NR==2{print \$4}"' \
        docker='docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo -'
    ;;

svcmem)
    # What do the three services actually COST?  `capacity` says how much
    # room there is; this says who is spending it.
    #
    # Three corrections are baked into the probe, each one a wrong answer
    # this recipe produced first (MEASURED 2026-09-13, helix + c02):
    #
    # 1. SUM the process group -- do NOT read the port's owner.  lserver
    #    runs `tsx --watch`: a supervisor plus children.  The pid holding
    #    :11434 was 111 MB while the service really cost 228 MB.  Keying
    #    off the listener understates it by 2x.
    # 2. MATCH BOTH LAYOUTS.  lserver is /workspace/lserver on the fleet
    #    but /mnt/c/wam/L-server on helix.  A single-path grep printed a
    #    bare `-` for helix -- indistinguishable from "not running", on a
    #    box where it was serving :11434 the whole time.
    # 3. `grep -v grep` IS LOAD-BEARING.  Without it the probe matches its
    #    own `bash -c` and `grep` argv and reports a service that is not
    #    there.  That is how "helix runs 2 of them" was first measured;
    #    helix runs lserver only.
    #
    # 4. FALL BACK INTO THE CONTAINER.  "container processes are visible
    #    to the distro's ps" is TRUE ON c02 AND FALSE ON helix, so a
    #    host-only probe reported api_server=off on helix while it was
    #    running at 576 MB.  MEASURED: helix has NO local dockerd
    #    (pgrep dockerd = 0) yet `docker ps` works -- its containers live
    #    in a SEPARATE Docker Desktop VM with its own pid namespace and
    #    its own memory.  c02 runs dockerd inside the distro, so there the
    #    container shares both.  Hence: try the host, then `docker exec`.
    #    `ss` cannot rescue this either -- *:6010 is a published port and
    #    resolves to no pid at all, even as root.
    #
    # NOTE the tier is per-box here, so pass FULL aliases with -t "":
    #   recipes.sh svcmem -b helix,c02u
    #
    # A TRAILING `*` MARKS A VALUE FOUND ONLY INSIDE THE CONTAINER -- i.e.
    # memory that does NOT come out of this distro's budget when dockerd is
    # remote.  Do not add it into a distro total without checking the star.
    # `rsum` is the shared reducer so the host arm and the container arm
    # cannot drift apart -- they must agree on what "sum" means or the
    # fallback would silently change units.
    SM='rsum() { grep -iE "$1" | grep -v grep | awk "{s+=\$1} END{ if(s) printf \"%d\n\", s/1024; else print 0 }"; }
sm() {
  h=$(ps -eo rss=,args= | rsum "$1")
  if [ "$h" -gt 0 ]; then echo "$h MB"; return; fi
  c=$(docker exec officeagent-dev sh -c "ps -eo rss=,args=" 2>/dev/null | rsum "$1")
  if [ "$c" -gt 0 ]; then echo "$c MB*"; return; fi
  echo off
}'
    "$FS" "$@" \
        lserver="$SM; sm '(lserver|L-server)/(node_modules|src)'" \
        wwwrootsdx="$SM; sm 'wwwrootsdx/service'" \
        api_server="$SM; sm 'api/src/app\.js'"
    ;;

capacity)
    # "How much room is there?" spans THREE tiers, and asking only one
    # is how the 50%-of-host WSL default gets mistaken for the machine.
    #
    # MEASURED 2026-09-13: win=128G, wsl=62G, container=62G.  The
    # container is NOT a fourth budget -- it is a process inside the
    # distro, so it draws from the SAME 62G (cgroup memory.max = `max`,
    # i.e. no limit of its own).  Windows + WSL + container share one
    # ceiling, and only ~half the box is reachable from Linux at all.
    #
    # Raising it needs `memory=` in %USERPROFILE%\.wslconfig on the
    # Windows side plus `wsl --shutdown`, which drops every service on
    # the box -- so this recipe REPORTS, it does not fix.
    printf '== WINDOWS (physical) ==\n'
    # wmic is gone on current Windows builds and returns an EMPTY cell,
    # not an error -- which reads as "no RAM" rather than "wrong tool".
    # :*** THIS RECIPE ASKED THE WINDOWS TIER OVER ssh, WHICH R-NORELAY
    # BANS. ***  The QUESTION is still valid; only the transport was
    # forbidden.  It is not silently downgraded to a WSL answer -- that
    # is precisely the `-t win` silent-hop bug (uname -s returned Linux
    # on 4/4 and read as corroboration).  Use win_probe (WinRM :5985)
    # from a peer in the TARGET's project.
    echo "recipes: this sweep needs the WINDOWS tier, which no longer has ssh." >&2
    echo "  R-NORELAY bans cNNwin (:22 measured dark fleet-wide, by design)." >&2
    echo "  Use win_probe <ip> '<powershell>' -- WinRM :5985, same project." >&2
    exit 2
    printf '\n== WSL DISTRO ==\n'
    "$FS" "$@" \
        ram_gb='free -g | sed -n "2s/  */ /gp" | cut -d" " -f2' \
        ram_free='free -g | sed -n "2s/  */ /gp" | cut -d" " -f7' \
        disk='df -h / | tail -1 | tr -s " " | cut -d" " -f2' \
        disk_free='df -h / | tail -1 | tr -s " " | cut -d" " -f4' \
        disk_pct='df -h / | tail -1 | tr -s " " | cut -d" " -f5'
    printf '\n== CONTAINER ==\n'
    # Bare name, no suffix: the container IS the plain alias (port 2222).
    "$FS" -t "" "$@" \
        ram_gb='free -g | sed -n "2s/  */ /gp" | cut -d" " -f2' \
        ram_free='free -g | sed -n "2s/  */ /gp" | cut -d" " -f7' \
        cgroup_max='cat /sys/fs/cgroup/memory.max 2>/dev/null || echo none'
    ;;

defend)
    # "IS THE FLEET DEFENDED AGAINST THE WSL CRASH?" -- the sweep this
    # repo ran twice in one session (2026-09-17), which is the bar.
    #
    # It is NOT the same question as `service`.  `service` asks "is it up
    # RIGHT NOW"; this asks "when it dies, does it come BACK, with nobody
    # watching".  Those diverged for seven hours on 2026-09-16: every
    # port was green while the lserver session was unreachable on 5/5,
    # because the boot-time supervisor had refused to repair and NOTHING
    # re-ran it.  A green `service` table is not evidence of defence.
    #
    # THE DEFENCE IS FIVE LAYERS ON TWO TIERS.  Asking one tier answers
    # half the question, and the two halves fail differently:
    #
    #   WINDOWS   fleet-wsl-boot      STARTS the VM       (nothing else does)
    #   WSL       wsl-keepalive       keeps systemd busy  (cannot START one)
    #   WSL       [boot] command      runs the supervisor ONCE per VM boot
    #   WSL       lserver-supervise   RE-runs it every 5min when that fails
    #   WSL       wwwrootsdx-mcp      starts :47390 (lserver's hook has no
    #                                 equivalent -- MEASURED: after a real
    #                                 restart :47390 came back 0 and nothing
    #                                 on the box would ever start it)
    #
    # :trap: `is-active` IS NOT `is-enabled`.  A guard that is active now
    # but not enabled is armed until the next reboot and then silently
    # absent -- which is precisely the window this recipe exists to check.
    # Both columns are here deliberately; a `-`/`disabled` in ENABLED is
    # the finding even when ACTIVE is green.
    printf '== WSL: is the guard ARMED (active) and will it SURVIVE a reboot (enabled) ==\n'
    "$FS" "$@" \
        keepalive='systemctl is-active wsl-keepalive 2>&1 | head -1' \
        ka_en='systemctl is-enabled wsl-keepalive 2>&1 | head -1' \
        superv='systemctl is-active lserver-supervise.timer 2>&1 | head -1' \
        sv_en='systemctl is-enabled lserver-supervise.timer 2>&1 | head -1' \
        mcp_t='systemctl is-active wwwrootsdx-mcp.timer 2>&1 | head -1' \
        bootcmd='grep -c wam-lserver-tmux /etc/wsl.conf 2>/dev/null'
    printf '\n== WSL: does the supervisor carry the REPAIR, not just a timer ==\n'
    # A timer that calls a supervisor which still refuses to act is a
    # timer that does nothing.  MEASURED: BROKEN was a dead-end state
    # with no edge back until stale_socket_reclaim existed; and the
    # boot-time socket dir comes back ROOT-OWNED, which tmux refuses,
    # until ensure_socket_dir fixes it.  Both must be PRESENT.
    # :trap: KillMode -- the default (control-group) makes the timer
    # DESTRUCTIVE: systemd reaps the oneshot's cgroup on exit and kills
    # the tmux server it just created, exiting 0 with "READY HEALTHY" as
    # the last log line.  `process` is load-bearing, not tuning.
    "$FS" "$@" \
        reclaim='grep -c stale_socket_reclaim /usr/local/sbin/wam-lserver-tmux 2>/dev/null' \
        dirfix='grep -c ensure_socket_dir /usr/local/sbin/wam-lserver-tmux 2>/dev/null' \
        killmode='systemctl show lserver-supervise.service -p KillMode --value 2>/dev/null' \
        sockwatch='systemctl is-active tmux-sock-watch.service 2>&1 | head -1'
    printf '\n== WINDOWS: the only thing that STARTS the VM ==\n'
    # :trap: BOOT_RC 267009 (0x41301) = SCHED_S_TASK_RUNNING is HEALTHY,
    # not an error -- the action ends in `exec sleep infinity`, so the
    # task never finishes and never reports an exit code.  Its neighbours
    # mean the opposite:
    #     267011      (0x41303) task has not yet run -- owner logged off,
    #                 InteractiveToken had no session
    #     3221225786  (0xC000013A) STATUS_CONTROL_C_EXIT -- the action was
    #                 KILLED; VM alive, but nothing re-ran `systemctl
    #                 start ssh`.  State reads `Ready`, which looks fine.
    # :trap: BOOT_RC IS A PROXY FOR THE TASK, NOT THE VM.  MEASURED on
    # c05: VMWP=0 while the task reported Running.  That is why VMWP is
    # in the same table -- a task claiming Running beside VMWP=0 is the
    # false green, and /End-before-/Run is the fix (IgnoreNew silently
    # discards a bare /Run).
    # :*** THIS RECIPE ASKED THE WINDOWS TIER OVER ssh, WHICH R-NORELAY
    # BANS. ***  The QUESTION is still valid; only the transport was
    # forbidden.  It is not silently downgraded to a WSL answer -- that
    # is precisely the `-t win` silent-hop bug (uname -s returned Linux
    # on 4/4 and read as corroboration).  Use win_probe (WinRM :5985)
    # from a peer in the TARGET's project.
    echo "recipes: this sweep needs the WINDOWS tier, which no longer has ssh." >&2
    echo "  R-NORELAY bans cNNwin (:22 measured dark fleet-wide, by design)." >&2
    echo "  Use win_probe <ip> '<powershell>' -- WinRM :5985, same project." >&2
    exit 2
    ;;

mesh)
    # THE FULL SQUARE, IN MILLISECONDS (user ruling 2026-09-26: "a 31*31
    # matrix with 930 connection test point (exclude self connection),
    # just a ssh 2200 ping, self to self print *, other print the ssh
    # connect time in ms (only latency number not include ms)").
    #
    # `matrix wsl` answers o/X; this answers HOW LONG.  Same dial shape --
    # one job per SOURCE ROW, the probe runs ON the source and dials its
    # peers from there (a star from the driver measures the driver).
    #
    # A cell is the wall time of `ssh -n <peer>wsl true`: TCP + kex + auth
    # + a no-op.  That is the "ssh ping" -- the cost a real fleet hop pays,
    # not an ICMP rtt (ICMP is filtered across islands anyway).  A
    # cross-island cell rides the ProxyJump chain the box's own config
    # names, so a 4-digit cell is a relay path, not a slow box.
    #
    # :trap: ONLY THE FIRST ATTEMPT IS TIMED HONESTLY.  sea's MaxStartups
    # drops relay bursts at random, so a failed dial is retried (twice,
    # jittered) before it is called X -- and the cell reports the time of
    # the attempt that SUCCEEDED, never the sum, or one dropped SYN would
    # read as a 12-second link.  A retried cell is suffixed `r` so a
    # flaky edge stays visible instead of being laundered into a number.
    #
    # Four cell states, never collapsed: <ms> reached, `*` self (NOT
    # dialled -- the user excluded it), `X` dark after 3 tries, `?` the
    # source row itself never answered (a fact about the ROW's box).
    if [ -n "${FLEET_SSH_BOXES:-}" ]; then boxes=$FLEET_SSH_BOXES
    else boxes=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); r=d.get("regions") or {}
print(",".join(b for v in r.values() for b in v.get("boxes",{})) if r else ",".join(d.get("boxes",d)))' "$FIPS"); fi
    while [ $# -gt 0 ]; do case "$1" in -b) boxes=$2; shift 2 ;; *) shift ;; esac; done
    list=$(printf '%s' "$boxes" | tr ', ' '  ')
    n=$(printf '%s' "$list" | wc -w)
    # TWO LEVELS OF GNU parallel (user ruling 2026-09-26: "design the
    # recipe with help of parallel, each box return 30 result (still
    # parallel), and the emit box gather them").
    #   outer  this driver: `parallel -j0 --tag`, ONE job per source box
    #   inner  each box:    `parallel -k -j0`, ONE job per peer -- all 30
    #          dials in flight at once, -k returns them in column order
    # so wall time = one row's SLOWEST cell + the hop to reach that row,
    # not a sum.  `parallel` is on 31/31 (measured 2026-09-26).
    #
    # :trap: THE FLOOR IS THE SLOWEST PATH, NOT THE FAN-OUT.  An in-island
    # cell is ~310ms (one ssh handshake); a cross-island cell rides the
    # ProxyJump chain and is 2-5s.  No amount of parallelism makes a
    # 3-hop handshake sub-second, so a full 31-box square is bounded by
    # its worst cross-island pair; an in-island subset (-b c00,...,c08)
    # is the case that lands under 1s.
    #
    # :*** THE INNER FAN IS CAPPED AT 6 AND THE RETRY WAITS 1-4s -- BOTH
    # ARE LOAD-BEARING, BECAUSE EVERY CROSS-ISLAND CELL IS A LOGIN TO sea.
    # *** sea (43.106.59.17:21198) runs MaxStartups 10:30:100, shared by
    # the WHOLE fleet plus internet scanners.  MEASURED 2026-09-26 with an
    # uncapped inner fan (-j0) and 0.1-0.9s jitter: 496/930, and sea's
    # journal logged "232 connections dropped" then "338 connections
    # dropped" in a 7s + 20s throttle window.  c00 and c08 lost EVERY
    # sea-routed cell, because all three retries landed inside one window.
    # Same run with -j6 and 1-4s back-off: 925/930.  A single c00->cj01
    # dial was 1.3s rc=0 throughout -- the route was never broken.
    # MESH_J=0 is still there for an in-island -b where sea is not on
    # the path.
    probe=$(mktemp)
    cat > "$probe" <<'PROBEEOF'
dial() {
    p=$1
    [ "$p" = "$SELFBOX" ] && { echo '*'; return; }
    t="${p}wsl"
    ssh -G "$t" 2>/dev/null | grep -q "^hostname $t\$" && t="${p/#c/m}wsl"
    for a in 1 2 3; do
        s=$(date +%s%N)
        if timeout 20 ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o ControlPath=none \
             -o LogLevel=ERROR "$t" true >/dev/null 2>&1 </dev/null; then
            c=$(( ($(date +%s%N) - s) / 1000000 ))
            [ "$a" -gt 1 ] && c="${c}r"
            echo "$c"; return
        fi
        sleep "$((RANDOM % 4 + 1))"
    done
    echo X
}
export -f dial; export SELFBOX
echo "ROW $(SHELL=/bin/bash parallel -k -j "${MESH_J:-6}" dial ::: $LIST | tr '\n' ' ')"
PROBEEOF
    rowdir=$(mktemp -d)
    row() {   # $1 = source box; runs on THIS driver, one outer job each
        src=$1; al="${src}wsl"
        ssh -G "$al" 2>/dev/null | awk '/^hostname /{exit ($2=="'"$al"'")}' || al="${src/#c/m}wsl"
        # :trap: the ROW LOGIN rides sea too (every non-cj row from cj00),
        # and 31 simultaneous logins trip sea's MaxStartups 10:30:100 exactly
        # like the inner dials do.  MEASURED 2026-09-26: with no retry here
        # all 14 sea-routed rows came back `?` (491/930) while every row
        # that answered was 28-29/30.  So retry the login itself, jittered.
        for t in 1 2 3 4; do
            timeout 120 ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout=15 \
                -o LogLevel=ERROR "$al" "SELFBOX=$src LIST='$LIST' MESH_J=${MESH_J:-6} bash -s" \
                < "$PROBE" 2>/dev/null | grep '^ROW ' | tail -1 | sed 's/^ROW//' > "$ROWDIR/$src"
            [ -s "$ROWDIR/$src" ] && break
            sleep "$((1 + RANDOM % 4)).$((RANDOM % 10))"
        done
    }
    export -f row
    LIST=$list PROBE=$probe ROWDIR=$rowdir SHELL=/bin/bash \
        parallel -j "${MESH_ROWS_J:-0}" row ::: $list
    set -f
    # ALWAYS SAVED AS MARKDOWN (user ruling 2026-09-26: "always save the
    # latency in table in tmp folder markdown file /tmp/fleet_latency.md").
    # Same rows as the terminal square -- one render, two sinks, so the
    # file can never disagree with what was printed.  Overwritten each run;
    # the header carries the UTC time because an edge is an observation.
    md=${MESH_MD:-/tmp/fleet_latency.md}
    {
        printf '# fleet ssh :2200 latency (ms)\n\n'
        printf 'measured %s from `%s`, %s boxes, %s dials (self excluded).\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(uname -n)" "$n" "$((n*(n-1)))"
        printf 'Row = FROM, column = TO.  `*` self, `X` dark after 3 tries, `?` row never answered, `r` = succeeded on a retry.\n\n'
        printf '| FROM |'; for p in $list; do printf ' %s |' "$p"; done; printf ' OK |\n'
        printf '|---|'; for p in $list; do printf -- '---:|'; done; printf -- '---:|\n'
    } > "$md"
    tot=0
    printf '%-6s' FROM; for p in $list; do printf '%-6s' "$p"; done; printf '%s\n' OK
    for src in $list; do
        out=$(cat "$rowdir/$src" 2>/dev/null)
        [ -n "$out" ] || out=$(for p in $list; do [ "$p" = "$src" ] && printf ' *' || printf ' ?'; done)
        ok=$(printf '%s\n' $out | grep -c '^[0-9]'); tot=$((tot+ok))
        printf '%-6s' "$src"; for c in $out; do printf '%-6s' "$c"; done
        printf '%s/%s\n' "$ok" "$((n-1))"
        { printf '| **%s** |' "$src"; for c in $out; do printf ' %s |' "$c"; done
          printf ' %s/%s |\n' "$ok" "$((n-1))"; } >> "$md"
    done
    printf '\nreached %s/%s\n' "$tot" "$((n*(n-1)))" >> "$md"
    set +f
    echo "saved $md" >&2
    rm -rf "$probe" "$rowdir"
    ;;

meshcfg)
    # (was `mesh` until 2026-09-26 -- the name now belongs to the latency
    # square below, which is the question "mesh" actually asks.)
    # THE mNN PEER MESH SHOULD BE IDENTICAL ON EVERY BOX -- and it is
    # THREE tiers, not two (user ruling 2026-09-18: "mesh configure should
    # have 15 m.*, 22, 2200, 2222 ... M_Hosts, P22, P2200, P2222 should be
    # 5, that is the shape").
    #
    #     mNN      container  :2222   <- the harness tier, was MISSING
    #     mNNwsl   distro     :2200
    #     mNNwin   windows    :22
    #
    # So the shape is 15 `Host mNN*` blocks and FIVE of each port -- one
    # per box, including the box itself (a box dials itself by the same
    # name a peer uses, so the map is uniform and copyable).
    #
    # :trap: COUNTING `Port 22` WITH grep -c MATCHES THE OTHER TWO.  `Port
    # 2200` and `Port 2222` both begin `Port 22`, so an unanchored count
    # reports 15 where the answer is 5.  Anchor with `$`.
    #
    # :trap: A `Port` COUNT IS NOT A MESH COUNT.  ~/.ssh/config also holds
    # `sv` (:22) and any leftover cNN blocks from an older generator, so
    # the port columns below count only lines inside mNN blocks would be
    # wrong too -- they count the WHOLE file on purpose, and the mNN_*
    # columns are the authority.  A P22 of 6 with MWIN=5 is the `sv` block,
    # not a sixth peer.
    #
    # MEASURED 2026-09-18, and no two boxes agreed:
    #     BOX  HOSTS  MCTR  MWSL  MWIN   generator
    #     c01  15     5     5     5      fleet.py sshconfig  (the shape)
    #     c02  10     0     5     5      fleet-mesh-keys.sh
    #     c03  10     0     5     5      fleet-mesh-keys.sh
    #     c04  10     0     5     5      fleet-mesh-keys.sh
    #     c05  15     0     10    5      BOTH, appended
    # c05's 10 wsl blocks are DUPLICATES -- two generators wrote the same
    # file and neither truncated the other's work.  That is why MDUP is a
    # column: a duplicate Host block is silently won by the FIRST match,
    # so a stale earlier entry beats a correct later one and the config
    # looks complete while routing to the wrong place.
    #
    # THE CONTAINER TIER IS THE ONE THAT MATTERS FOR STAGE 3.  Without
    # `Host mNN` a box cannot dial a peer's harness container at all, so
    # `broadcast`, any cross-box harness probe, and the e2e smoke have no
    # route -- and the failure is `Could not resolve hostname`, which
    # reads like a dead peer rather than an absent alias.
    #
    # MEASURED 2026-09-17: c01 and c05 hold all 10; c02/c03/c04 hold only
    # the 5 `wsl` blocks and are missing all 5 `win` blocks.  Uniform
    # absence across three boxes reads like "win peers don't exist" --
    # they do (c01/c05 prove it), so this is a rollout gap, not a design
    # choice.  `-b c02,c03,c04` on its own is a NON-mesh check (relay
    # only) and would not have caught it: this reads ~/.ssh/config, the
    # thing that decides whether `ssh mNNwin` even resolves.
    #
    # `mesh_n` is the headline column; `mesh_missing` names exactly which
    # aliases are absent so a short count is not left as a bare number --
    # "5" alone does not say WHICH five are gone.
    "$FS" "$@" \
        hosts='grep -oE "(^Host | )m[0-9]{2}(win|wsl)?( |$)" ~/.ssh/config 2>/dev/null |  sed "s/^Host //; s/^ //; s/ $//" | sort -u | wc -l' \
        mctr='grep -oE "(^Host | )m[0-9]{2}( |$)" ~/.ssh/config 2>/dev/null |  sed "s/^Host //; s/^ //; s/ $//" | sort -u | wc -l' \
        mwsl='grep -oE "(^Host | )m[0-9]{2}wsl( |$)" ~/.ssh/config 2>/dev/null |  sed "s/^Host //; s/^ //; s/ $//" | sort -u | wc -l' \
        mwin='grep -oE "(^Host | )m[0-9]{2}win( |$)" ~/.ssh/config 2>/dev/null |  sed "s/^Host //; s/^ //; s/ $//" | sort -u | wc -l' \
        p2222='grep -cE "^[[:space:]]*Port 2222$" ~/.ssh/config 2>/dev/null' \
        p2200='grep -cE "^[[:space:]]*Port 2200$" ~/.ssh/config 2>/dev/null' \
        p22='grep -cE "^[[:space:]]*Port 22$" ~/.ssh/config 2>/dev/null' \
        mdup='grep -oE "^Host m[0-9]{2}(win|wsl)?( |$)" ~/.ssh/config 2>/dev/null | sed "s/^Host //; s/ $//" | sort | uniq -d | tr "\n" "," | sed "s/,$//"' \
        missing='P=$(grep -oE "(^Host | )m[0-9]{2}(win|wsl)?( |$)" ~/.ssh/config 2>/dev/null |  sed "s/^Host //; s/^ //; s/ $//" | sort -u); M=""; for n in 01 02 03 04 05; do for t in "" wsl win; do echo "$P" | grep -qx "m$n$t" || M="$M,m$n$t"; done; done; echo "${M#,}"'
    ;;

harness-mesh)
    # CAN EACH BOX REACH ITS PEERS' HARNESS CONTAINERS -- over the mesh,
    # on :2222?  (user 2026-09-18: "recipe in fleet_ssh to check the
    # harness provision status via ssh mesh connection to 2222".)
    #
    # :WHY_THIS_IS_NOT_`harness`.  `harness` asks THIS DRIVER -> each
    # container: a STAR.  It proves the hub's reach and says nothing about
    # whether the boxes reach each other -- the exact false-success class
    # bin/mesh-verify.sh's header documents ("every 'the mesh works' claim
    # in this repo's history was a star measurement, and all of them were
    # wrong").  This dials peer->peer from inside each box.
    #
    # :WHY_NOT_`mesh`.  `mesh` reads ~/.ssh/config -- it asks whether the
    # ALIAS EXISTS.  This asks whether the alias WORKS and whether what
    # answers is a provisioned harness.  A present block that dials a dead
    # container is exactly the gap between the two.
    #
    # THE PROBE RUNS ON THE BOX and fans to its peers, so each cell is one
    # box's view of the whole fleet: `ok` counts peers whose container
    # answered AND carried the devbase toolkit.  A box with a complete
    # config but no route scores 0 while `mesh` shows it green.
    #
    # :trap: `hostname` IS NOT IN THE CONTAINER IMAGE (measured: `bash:
    # hostname: command not found` on the azurelinux base).  Identify the
    # peer by something that exists -- the toolkit probe itself is enough,
    # and asking for a missing binary would report every healthy peer as
    # broken.
    #
    # :trap: BOUND EVERY HOP.  One unroutable peer costs a full TCP
    # timeout, and five boxes x four peers serialised is minutes of dead
    # air.  ConnectTimeout + an outer `timeout` keep a dark peer to ~8s.
    #
    # :trap: THE SELF-DIAL IS NOT THE SAME PATH AS A PEER DIAL, and it
    # fails differently.  MEASURED 2026-09-18: c01 reaches m02..m05 but its
    # OWN m01 returns `kex_exchange_identification: read: Connection reset
    # by peer` on 10.30.2.154:2222 -- 4/5 with the failure on the diagonal.
    # A peer arrives at the Windows host's published port; the box itself
    # hairpins to its own LAN address, which is a different route.  So a
    # 4/5 here with only the self entry dark is a DIFFERENT (and smaller)
    # problem than 4/5 with a peer dark -- the DARK column names which, and
    # that is why it prints names rather than a count.
    "$FS" "$@" \
        peers_ok='n=0; d=""; for p in m01 m02 m03 m04 m05; do r=$(timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o ControlPath=none "$p" "command -v rg >/dev/null && command -v jq >/dev/null && command -v parallel >/dev/null && echo OK" 2>/dev/null | tr -d "\r" | grep -c OK); if [ "$r" = 1 ]; then n=$((n+1)); else d="$d,$p"; fi; done; echo "$n/5"' \
        dark='n=0; d=""; for p in m01 m02 m03 m04 m05; do timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o ControlPath=none "$p" true 2>/dev/null || d="$d,$p"; done; echo "${d#,}"' \
        api='n=0; for p in m01 m02 m03 m04 m05; do timeout 15 ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o ControlPath=none "$p" "tmux ls 2>/dev/null | grep -qc api-server" >/dev/null 2>&1 && n=$((n+1)); done; echo "$n/5"'
    ;;

listen2200|sshd)
    # "all 2200 listen" -- is the WSL-layer sshd up on every box?
    # :*** THIS IS THE ONE SWEEP THAT MUST NOT USE ssh. ***  Asking a box
    # over ssh whether its sshd listens is circular: a box that fails to
    # answer renders `(unreachable)`, which is the SAME cell a box with a
    # dead sshd would produce, so the probe cannot distinguish the two
    # states it exists to tell apart.  Dial the PORT instead -- a bounded
    # TCP connect answers for a box we cannot log into, which is exactly
    # the cj11 case (plan 25 item 7.7: ARM said Running, every tier dark).
    # :trap: BOUND EVERY DIAL.  A filtered edge does not refuse, it
    # HANGS -- measured rc=124 at the timeout on the 10.30 edge from
    # helix.  Unbounded, 31 boxes would cost minutes and risk the
    # session-host ack deadline.
    scope=${1:-all}
    ips="${FLEET_SSH_IPS:-$FIPS}"
    printf '%-7s %-14s %-10s %s\n' BOX IP REGION P2200
    python3 - "$ips" "$scope" <<'PYEOF' | while IFS='|' read -r box ip region; do
import json, sys
d = json.load(open(sys.argv[1])); want = sys.argv[2]
for name, r in (d.get("regions") or {}).items():
    if want not in ("all", name):
        continue
    for b, ip in r.get("boxes", {}).items():
        print(f"{b}|{ip}|{name}")
PYEOF
        if [ -z "$ip" ]; then st="(no ip)"
        elif timeout "${FLEET_LISTEN_TIMEOUT:-6}" bash -c "exec 3<>/dev/tcp/$ip/2200" 2>/dev/null; then st=LISTEN
        else st=dark; fi
        printf '%-7s %-14s %-10s %s\n' "$box" "${ip:--}" "$region" "$st"
    done
    ;;

matrix)
    # THE FULL N-BY-N REACHABILITY MATRIX -- every ordered pair, dialled
    # with a REAL ssh, rendered as a square.  (user 2026-09-19: "add such
    # format as good example of recipe show the powerful connection
    # between node ... our mesh should like 16*16, 256 connection mesh, or
    # 30*30 900 connection huge mesh".)
    #
    #     recipes.sh matrix            # container tier (:2222), the default
    #     recipes.sh matrix wsl        # distro tier (:2200)
    #
    #                 TO
    #     FROM   c01 c02 c03 c04 c05  OK
    #     c01     .   o   o   o   o   5/5
    #     c02     o   .   o   o   o   5/5
    #
    # `o` = answered, `X` = dark, `.` = the DIAGONAL (self).  The diagonal
    # is a real dial, not a skipped cell -- see the trap below; it is drawn
    # differently only so the eye can find it.
    #
    # :WHY_A_SQUARE_AND_NOT_A_COUNT.  `harness-mesh` prints `4/5` per box,
    # which tells you a peer is dark but not WHICH, and cannot show
    # ASYMMETRY at all.  A->B working while B->A fails is the single most
    # informative shape in a mesh -- it separates "B is down" (a dark
    # COLUMN) from "A cannot route out" (a dark ROW) -- and a per-box
    # count cannot express it.  MEASURED 2026-09-19: the fleet had exactly
    # ONE dark cell out of 25, on the diagonal, and no count-shaped view
    # would have told you it was the diagonal.
    #
    # READ IT AS SHAPES, which is the whole reason it is square:
    #     a dark ROW      that box cannot dial OUT    (its config/route)
    #     a dark COLUMN   that box cannot be REACHED  (its sshd/publish)
    #     one dark CELL   a single broken pair        (a route, not a host)
    #     dark DIAGONAL   the self-dial only          (the hairpin, below)
    #
    # :trap: THE DIAGONAL IS A DIFFERENT ROUTE AND FAILS DIFFERENTLY.
    # A peer arrives at the box's published port from outside; the box
    # dialling ITSELF by its own 10.30 address has to hairpin.  MEASURED
    # 2026-09-19 on m01 -- and it is a ROUTING TABLE, not a firewall:
    #     ip route get 10.30.2.154
    #       m01: via 169.254.73.152 dev eth0 TABLE 128   <- hairpin
    #       m03: dev eth0 src 10.30.5.71                 <- direct
    # m03 has no table 128 at all.  The symptom was
    # `kex_exchange_identification: Connection closed by remote host`,
    # which reads like a dead container; the container was healthy and
    # answered `172.17.0.1:2222` (docker0) instantly.  Fixed by
    # bin/ctr-selfdial-fix.sh, which points the SELF entry at docker0 and
    # leaves every peer entry on its ProxyJump.  Never "fix" a dark
    # diagonal by deleting the self block: the shape is N blocks BECAUSE
    # a box carries an entry for itself.
    #
    # :trap: THIS SCALES AS N^2 -- 5x5=25, 16x16=256, 30x30=900.  The
    # dials are therefore fanned out ACROSS boxes (`parallel -j`, one job
    # per source row) and run SEQUENTIALLY within a row, so the wall time
    # is one ROW, not the whole square.  At 30 boxes a serial square would
    # be 900 x ~1s; this is ~30.  Every hop is bounded twice
    # (ConnectTimeout + outer `timeout`) because ONE unroutable peer
    # otherwise costs a full TCP timeout and N of them cost minutes.
    #
    # :trap: DO NOT RENDER THE SQUARE FROM A COUNT.  Each cell is its own
    # dial and prints its own character; a row that reports `4/5` with no
    # per-cell record cannot say which column was dark, which is exactly
    # the information the square exists to carry.
    tier=${1:-ctr}
    boxes=${FLEET_SSH_BOXES:-c01,c02,c03,c04,c05}
    list=$(printf '%s' "$boxes" | tr ',' ' ')
    # --json emits the measured graph instead of the square.  Same dials,
    # same semantics -- a RENDERING of the one probe, never a second
    # source of truth (the same rule the ghcp tier-split obeys).
    emit_json=0
    if [ "$tier" = "--json" ]; then emit_json=1; tier=${2:-ctr}; fi
    case "$tier" in
        ctr) port=2222; suffix="" ;;
        wsl) port=2200; suffix="wsl" ;;
        *) echo "matrix: tier must be ctr or wsl" >&2; exit 2 ;;
    esac
    jrows=""   # accumulates "src cell cell ..." lines for the JSON arm

    # ONE JOB PER SOURCE ROW.  The probe runs ON the source box and dials
    # its peers from there -- a star from this driver would measure the
    # DRIVER's reach and is the exact false-success mesh-verify.sh's
    # header warns about.
    # :*** RESOLVE THE PEER ALIAS THE WAY THE BOX DOES, NOT THE WAY THE
    # BOX LIST IS SPELLED. ***  MEASURED 2026-09-23: this square reported
    # **0/10 on four boxes that were 10/10 by direct dial**.  The box list
    # is keyed `cNN` (it is the fleet-ips.json key form), but a box's OWN
    # generated peer config -- written by `fleet-mesh-keys.sh` from
    # `fleet.py meshconfig` -- defines `mNNwsl`.  Dialling `c5-72wsl`
    # therefore misses a config that only knows `m5-72wsl`.
    # :trap: THE FAILURE SHAPE IS THE MOST ALARMING ONE THE LEGEND ALLOWS
    # -- a dark ROW *and* a dark COLUMN, read as "cannot dial out" AND
    # "cannot be reached".  A probe that mis-renders the mesh is worse
    # than no probe: this one would send a reader to rebuild a healthy
    # fleet.  The stem swap is the same `c`->`m` the SOURCE dial below
    # already does; it was simply never applied to the PEER.
    #
    # :*** `ssh -n` IS LOAD-BEARING ONCE THE CONTAINER HOP IS GONE. ***
    # The probe arrives on the remote shell's STDIN (`bash -s`), so a bare
    # `ssh` inside the loop EATS THE REST OF THE SCRIPT.  MEASURED: the
    # first peer dialled fine (rc=0) and the line after it never ran, so
    # the probe printed NOTHING and every cell rendered `?`.  The old code
    # never hit this only because `docker exec` shielded stdin for it.
    #
    # :*** AND THE `wsl` TIER MUST NOT HOP THROUGH THE CONTAINER. ***
    # Both tiers used `docker exec`, so a box whose container is down
    # read X on every column even when its distro answered perfectly --
    # a CONTAINER fact rendered as a MESH fact.  `-t wsl` asks about the
    # distro, so it dials from the distro.  `-t ctr` keeps the hop,
    # because the container IS its subject.
    probe=$(mktemp)
    if [ "$tier" = wsl ]; then
    # :*** CROSS-ISLAND CELLS RIDE TWO RELAY HOPS, SO THE ROW IS FANNED. ***
    # MEASURED 2026-09-26: with every island publishing an observer on sea,
    # c01 -> cj05 is c01 -> sea -> helix -> cj05.  Serial at 31 peers that
    # is minutes per row; each peer dials in the background and the row is
    # reassembled IN ORDER from per-peer files, so a cell still prints its
    # own dial.  cNNwsl is tried FIRST: ssh-config-islands.sh --push puts
    # it on every box; the mNN rewrite is the legacy 10.30 fallback.
    cat > "$probe" <<PROBEEOF
d=\$(mktemp -d)
i=0
for p in $list; do
    i=\$((i+1))
    t="\${p}$suffix"
    ssh -G "\$t" 2>/dev/null | grep -q "^hostname \$t\$" && t="\${p/#c/m}$suffix"
    if [ "\$p" = "\$SELFBOX" ]; then mark="."; else mark="o"; fi
    # sea runs MaxStartups 10:30:100: a burst of relay dials is dropped
    # at RANDOM, which renders as scattered false X.  Cap the row at 6 in
    # flight and retry a failed dial twice with jitter before calling it X.
    while [ "\$(jobs -rp | wc -l)" -ge 6 ]; do wait -n; done
    ( c=X; for a in 1 2 3; do
          if timeout 30 ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o ControlPath=none \
               "\$t" true >/dev/null 2>&1 </dev/null; then c="\$mark"; break; fi
          sleep \$((RANDOM % 4 + 1))
      done; echo "\$c" > "\$d/\$i" ) &
done
wait
row=""
j=0
for p in $list; do j=\$((j+1)); row="\$row \$(cat "\$d/\$j" 2>/dev/null || echo '?')"; done
rm -rf "\$d"
echo "\$row"
PROBEEOF
    else
    cat > "$probe" <<PROBEEOF
row=""
for p in $list; do
    t="\${p}$suffix"
    if [ "\$p" = "\$SELFBOX" ]; then mark="."; else mark="o"; fi
    if timeout 12 docker exec ${CTR_NAME:-officeagent-dev} sh -c \
         "timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlPath=none \$t true" \
         >/dev/null 2>&1; then
        row="\$row \$mark"
    else
        row="\$row X"
    fi
done
echo "\$row"
PROBEEOF
    fi

    # :trap: A HEADER ON STDOUT MAKES THE JSON ARM UNPARSABLE.  MEASURED
    # 2026-09-24: `matrix --json` emitted a valid object preceded by the
    # `FROM cj00 cj06 ...` line, so `json.load` died on char 0 while the
    # output LOOKED correct to a human reading the terminal.  A machine
    # artifact must be the ONLY thing on stdout.
    [ "$emit_json" = 1 ] || {
        printf '%-6s' "FROM"; for p in $list; do printf '%-4s' "$p"; done; printf '%s\n' "OK"
    }
    rowdir=$(mktemp -d)
    for src in $list; do
        # :*** `${src/#c/m}wsl` IS A SOUTHEASTASIA-ONLY ALIAS RULE. ***
        # It rewrites c01 -> m01wsl, which is right for the 10.30 mesh and
        # WRONG everywhere else: cj00 becomes `mj00wsl`, a host that does
        # not exist, and every cell of the row renders `?`.  MEASURED
        # 2026-09-24 -- a 4x4 japan east square came back 0/4 on all four
        # rows, which reads as a dead region rather than a naming bug.
        # Same family as the `m${peer#c}` traps in broadcast and
        # fleet-mesh-keys.  Use the rewrite ONLY when it resolves; fall
        # back to the alias the caller actually named.
        _srcal="${src}wsl"
        ssh -G "$_srcal" 2>/dev/null | awk '/^hostname /{exit ($2=="'"$_srcal"'")}' \
            || _srcal="${src/#c/m}wsl"
        # ROWS FAN TOO (the header claimed they did; they ran serially).
        # Collect every row in the background, render in order below.
        while [ "$(jobs -rp | wc -l)" -ge "${MATRIX_ROWS_J:-8}" ]; do wait -n; done
        ( timeout 400 ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout=15 "$_srcal" \
                "SELFBOX=$src bash -s" < "$probe" 2>/dev/null | tail -1 > "$rowdir/$src" ) &
    done
    wait
    for src in $list; do
        out=$(cat "$rowdir/$src" 2>/dev/null)
        [ -n "$out" ] || out=$(for p in $list; do printf ' ?'; done)
        ok=$(printf '%s' "$out" | tr -cd 'o.' | wc -c)
        n=$(printf '%s' "$list" | wc -w)
        if [ "$emit_json" = 1 ]; then
            jrows="$jrows$src$out
"
        else
            printf '%-6s' "$src"
            for c in $out; do printf '%-4s' "$c"; done
            printf '%s/%s\n' "$ok" "$n"
        fi
    done
    if [ "$emit_json" = 1 ]; then
        # :*** THE GRAPH IS MEASURED, NEVER DERIVED FROM ADDRESSES. ***
        # An edge here is one real ssh dial.  It CANNOT be computed from
        # the /17s: measured 2026-09-24, helix routes 10.12 and 10.30
        # through the SAME next hop (10.18.0.1) and one is open while the
        # other is dark -- so the boundary is POLICY, not topology.  A
        # hand-authored reachability file would encode the wrong variable
        # and route a broadcast down an edge that drops.
        # :trap: THIS FILE GOES STALE.  It carries `measured_at` and the
        # box list for exactly that reason -- an edge map with no
        # timestamp is indistinguishable from a fresh one.  Re-run it;
        # do not trust it past a provisioning change.
        printf '%s' "$jrows" | python3 -c '
import sys, json, datetime
boxes = sys.argv[1].split()
tier  = sys.argv[2]
edges, reach = {}, {}
for line in sys.stdin.read().splitlines():
    if not line.strip(): continue
    parts = line.split()
    src, cells = parts[0], parts[1:]
    row = {}
    for dst, c in zip(boxes, cells):
        # o/. reached (. is the self-dial, a REAL dial drawn differently);
        # X dark; ? the row never answered at all -- three distinct facts,
        # never collapsed, same rule as the table cell states.
        row[dst] = {"o": True, ".": True}.get(c, False if c == "X" else None)
    edges[src] = row
    reach[src] = sum(1 for v in row.values() if v)
out = {
  "schema": 1,
  "_comment": ("MEASURED reachability, one real ssh dial per ordered pair. "
               "NOT derivable from fleet-ips.json: the block boundaries are "
               "policy (devcenter project / NSG), not routing -- helix sends "
               "10.12 and 10.30 via the same gateway and only one answers. "
               "true=reached, false=dark, null=source row never answered."),
  "measured_at": datetime.datetime.now(datetime.timezone.utc)
                     .strftime("%Y-%m-%dT%H:%M:%SZ"),
  "tier": tier, "port": int(sys.argv[3]), "boxes": boxes,
  "reach_count": reach, "edges": edges,
}
print(json.dumps(out, indent=1))
' "$list" "$tier" "$port"
    fi
    rm -rf "$probe" "$rowdir"
    ;;

broadcast)
    # BROADCAST — copy ONE directory from ONE source box to every peer,
    # over the MESH, in parallel.  `recipes.sh broadcast c02 OfficeAgent`.
    #
    # :*** THIS IS THE ONE RECIPE THAT WRITES. *** Every other recipe here
    # READS -- fleet-ssh.sh takes only the first line of output and is
    # built for reading (SKILL.md "When NOT to use it").  A copy CHANGES
    # state on N boxes, so it deliberately does NOT go through the table
    # wrapper: it fans a real command out with `parallel --tag` and
    # reports per peer.  That is the R-REPEATABLE shape the skill asks
    # for -- "write a script and fan THAT out".
    #
    # WHY THE MESH AND NOT THE DRIVER.  The obvious version pulls to the
    # driver then pushes N times, moving the payload N+1 times over the
    # slow relay.  The boxes reach each other directly on the 10.30
    # subnet via the `mNNwsl` aliases (plan 05), so the payload crosses
    # the fast path ONCE per peer and never touches the driver.
    # MEASURED 2026-09-16 (plan 05): relay 7.820s vs direct 0.308s, 25x.
    #
    # :trap: THE SOURCE BOX PUSHES.  rsync runs ON the source over ssh, so
    # its delta/compress work happens between the two peers.  Driving the
    # rsync from here would put the driver back in the middle of 31G.
    #
    # :trap: mNN IS THE SAME BOX AS cNN -- the prefix is the ROUTE, not a
    # different machine.  VERIFIED 2026-09-17 from c02: m01wsl->RP0DF,
    # m02wsl->PMBMN, m03wsl->8SBST, m04wsl->0U0P5, m05wsl->ZLP0K, i.e.
    # exactly c01..c05.  So the destination alias is the source-relative
    # `c` -> `m` swap and nothing cleverer.
    src=${1:?usage: recipes.sh broadcast <src-box> <path-under-/workspace|IMAGE:TAG>}
    what=${2:?usage: recipes.sh broadcast <src-box> <path-under-/workspace|IMAGE:TAG>}
    shift 2 || true
    all=${FLEET_SSH_BOXES:-c01,c02,c03,c04,c05}
    dst_list=$(printf '%s\n' "${all//,/ }" | tr ' ' '\n' | sed '/^$/d' | grep -vx "$src" | paste -sd' ')
    [ -n "$dst_list" ] || { echo "broadcast: no peers besides $src" >&2; exit 2; }

    # THE SOURCE ALIAS IS THE BOX AS GIVEN; only the DESTINATION is the
    # mesh route.  MEASURED 2026-09-17: this driver's ~/.ssh/config holds
    # ONLY mNN stems (no cNN at all), so the old unconditional `m${peer#c}`
    # produced `c02wsl` for the source and "Could not resolve hostname" on
    # 4/4 -- rc=255 per peer, which reads like a dead fleet rather than a
    # naming bug.  Strip whichever prefix is present, then re-add `m`, so
    # both `c02` and `m02` name the same box and the recipe works from a
    # driver holding either scheme.
    src_alias="${src}wsl"

    # ---- IMAGE MODE.  A DOCKER IMAGE IS NOT A DIRECTORY, and asking rsync
    # to move one is the mistake this branch exists to stop.  MEASURED
    # 2026-09-17: `broadcast c02 officeagent:devlatest` resolved to
    # /workspace/officeagent:devlatest, which DOES NOT EXIST -- and the
    # directory arm runs `--delete`, so a path typo is a MIRROR of nothing
    # onto four boxes.  An image lives in the docker graph driver, so it
    # must leave through `docker save` and arrive through `docker load`.
    #
    # DETECTION IS BY THE DOCKER DAEMON, NOT BY THE STRING.  A `:` in the
    # argument is not proof (a directory may legally contain one) and its
    # absence is not proof either (`officeagent` alone is a valid tag).
    # So ASK THE SOURCE BOX: if `docker image inspect` on $src resolves it,
    # it is an image.  That also fails closed -- a typo'd tag is reported
    # as "no such image" instead of silently falling through to rsync and
    # deleting a peer's directory.
    if timeout 20 ssh -o BatchMode=yes -o ControlPath=none "$src_alias" \
         "timeout 10 docker image inspect -- '$what' >/dev/null 2>&1"; then
        # STREAM, NEVER STAGE.  `docker save > file` then rsync then load
        # writes ~19G to the source disk, reads it back, and writes it
        # again per peer.  Piping save -> ssh -> load moves it once with no
        # temp file on either end, so a full disk cannot corrupt a copy.
        #
        # pigz, NOT gzip: VERIFIED present on 5/5 with nproc=32 (2026-09-17).
        # gzip is single-threaded and would make the CPU the bottleneck on a
        # 19G payload; `-1` is deliberate -- these layers are already
        # compressed, so high ratios buy almost nothing and cost real time.
        # If pigz is missing the pipe falls back to `cat` rather than
        # failing: the mesh is fast enough that raw bytes beat no copy.
        #
        # :trap: THE SOURCE PUSHES, exactly as in the directory arm -- the
        # payload crosses the fast 10.30 path once per peer and never
        # touches this driver.
        #
        # :trap: GRADE ON `docker load`'s OWN OUTPUT, NOT ON rc ALONE.  A
        # broken pipe can still exit 0 through some shells, so the peer is
        # re-asked with `docker image inspect` AFTER the load and the
        # resulting image Id is printed.  Matching Ids across peers is the
        # proof the copy is real; rc=0 on its own is not.
        printf '== broadcast IMAGE %s:%s -> %s (mesh, save|load, j=%s) ==\n' \
            "$src" "$what" "${dst_list// /,}" "${BROADCAST_J:-4}"
        src_id=$(timeout 30 ssh -o BatchMode=yes -o ControlPath=none "$src_alias" \
                   "timeout 20 docker image inspect --format '{{.Id}}' -- '$what'" 2>/dev/null)
        printf 'SRC_ID\t%s\n' "${src_id:-UNKNOWN}"
        printf '%s\n' $dst_list \
          | parallel -j"${BROADCAST_J:-4}" --tag "
              peer={}; stem=\${peer#[cm]}; mpeer=\"m\${stem}wsl\"
              out=\$(timeout ${BROADCAST_TIMEOUT:-7200} ssh -o BatchMode=yes -o ControlPath=none $src_alias \
                \"set -o pipefail; Z=\\\$(command -v pigz >/dev/null && echo 'pigz -1' || echo cat); \
                   docker save -- '$what' | \\\$Z | \
                   ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ControlPath=none \$mpeer \
                     'Z2=\\\$(command -v pigz >/dev/null && echo \\\"pigz -d\\\" || echo cat); \\\$Z2 | docker load'\" 2>&1); rc=\$?
              echo \"\$out\" | grep -vE 'setlocale|LC_ALL' | grep -E 'Loaded image|error|denied|No such' | head -2
              # Re-ask the PEER -- the load's own claim is not the check.
              pid=\$(timeout 30 ssh -o BatchMode=yes -o ControlPath=none \$mpeer \
                      \"timeout 20 docker image inspect --format '{{.Id}}' -- '$what'\" 2>/dev/null)
              echo \"peer_id=\${pid:-MISSING}\"
              echo \"rc=\$rc\"" 2>/dev/null
        exit 0
    fi
    # Not an image on the source -- fall through to the DIRECTORY arm.
    # A non-existent path lands here too, and rsync reports "No such"
    # per peer rather than this script guessing what was meant.
    printf '== broadcast %s:/workspace/%s -> %s (mesh, j=%s) ==\n' \
        "$src" "$what" "${dst_list// /,}" "${BROADCAST_J:-4}"
    # -a archive · -H hardlinks · --delete so the copy is a MIRROR (a
    # tree that merely "has the files" makes a later diff meaningless)
    # --partial so a dropped link resumes instead of restarting 31G.
    printf '%s\n' $dst_list \
      | parallel -j"${BROADCAST_J:-4}" --tag "
          peer={}; stem=\${peer#[cm]}; mpeer=\"m\${stem}wsl\"
          out=\$(timeout ${BROADCAST_TIMEOUT:-7200} ssh -o BatchMode=yes -o ControlPath=none $src_alias \
            \"LC_ALL=C rsync -aH --delete --partial --info=stats2 \
               -e 'ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ControlPath=none' \
               /workspace/$what/ \$mpeer:/workspace/$what/\" 2>&1); rc=\$?
          # :trap: the remote login shell emits a setlocale WARNING on
          # these distros, and it crowded the real stats line out of a
          # head -2.  Drop it explicitly rather than widening head --
          # a wider window just moves the truncation.
          echo \"\$out\" | grep -vE 'setlocale|LC_ALL' \
            | grep -E 'Total transferred|speedup|rsync error|No such|Permission denied' | head -2
          echo \"rc=\$rc\"" 2>/dev/null
    ;;

harness-ctr)
    # THE CONTAINER TIER, ASKED DIRECTLY -- the fast, legible variant of
    # `harness`'s container columns.
    #
    # WHY A SECOND RECIPE AND NOT A REWRITE OF `harness`:
    # `harness` must answer on a box whose container sshd is DOWN; that is
    # half of what it exists to detect (`h1_2222`).  A `-t ctr` sweep of
    # such a box returns (unreachable) for EVERY field, losing the columns
    # that say why.  So the diagnostic sweep keeps `docker exec`, and this
    # is the fast path for a fleet whose :2222 is known good.
    #
    # MEASURED 2026-09-19 (bench/ctr-bench.sh): the gain is PER FIELD --
    # 251ms at 1 field, 1138ms at 8 -- because `docker exec` forks a
    # container process per field while this opens ONE ssh session.  It is
    # ~1s on a ~6s sweep; the bigger win is that every probe below is PLAIN
    # SHELL instead of a three-shell quoting sandwich.
    #
    # :trap: AN (unreachable) ROW HERE IS NOT A DEAD BOX.  It means the
    # CONTAINER's sshd did not answer -- the distro may be perfectly
    # healthy.  Cross-read with `recipes.sh harness`, which asks the distro
    # and can tell "no container" from "container without sshd".
    "$FS" -t ctr "$@" \
        hostname='cat /etc/hostname' \
        api='curl -s --max-time 5 http://localhost:6010/health 2>/dev/null | head -c 24 || echo DOWN' \
        pane='tmux capture-pane -t api-server -p 2>/dev/null | grep -vc "^$"' \
        emacs='emacs --version >/dev/null 2>&1 && echo y || echo NO' \
        ghcp='command -v copilot >/dev/null && echo y || echo NO' \
        mesh='grep -c "^Host " /root/.ssh/config 2>/dev/null || echo 0' \
        scroll='tmux show -gv mouse 2>/dev/null || echo no-server'
    ;;

reduce)
    # REDUCE — cross-box repo MERGE, one box at a time, into one tip.
    # `recipes.sh reduce [repo]`   (repo defaults to cluster)
    #
    # :*** THE THIRD PATTERN, AND IT IS NEITHER OF THE OTHER TWO. ***
    #   BROADCAST  1 -> N, parallel.  Right for a PAYLOAD: every peer gets
    #              the SAME bytes, order is irrelevant, --delete mirrors.
    #   TABLE      N -> N rows, parallel.  Right for a READ: no box's
    #              answer depends on another's.
    #   REDUCE     N -> 1, SERIAL.  Right for a MERGE: box B's merge must
    #              start from the result of box A's, or one is discarded.
    #
    # WHY IT CANNOT BE PARALLEL, and this is git's shape rather than a
    # tuning choice: a merge has one first parent and yields one new tip.
    # Two merges onto the same base concurrently produce TWO tips, only one
    # can be pushed, and the loser must redo its merge against the winner.
    # The work is not saved by parallelism, only moved.  Asserted as a
    # counter-example in bench/reduce-bench.sh (property 5).
    #
    # THE LOOP IS A FOLD:
    #     acc = origin/master
    #     for box in boxes:  acc = merge(acc, box)      # ordered, serial
    #     push(acc)                                     # ONE push, at the end
    #
    # :trap: ORDER IS ANCESTRY, NOT TIME.  Sorting boxes by commit date is
    # the obvious move and it is wrong twice: committer time is attacker-
    # and skew-controlled, and a commit that is OLDER can be a DESCENDANT
    # (a box that pulled late then committed early).  The only ordering git
    # honours is `merge-base --is-ancestor`, which the loop tests per box.
    # bench property 2 pins this with a deliberately inverted clock.
    #
    # :trap: ALREADY-CONTAINED IS A NO-OP, NOT A MERGE.  Without the
    # is-ancestor guard a re-run creates empty merge commits forever, and
    # the reduce stops being re-runnable -- which is the property that
    # makes it safe to retry after a conflict.  bench property 3.
    #
    # :trap: A CONFLICT STOPS THE FOLD.  It does NOT take a side and carry
    # on.  Both sides are another agent's committed work; picking one
    # silently is the one failure this recipe must never have.  The loop
    # aborts the merge, leaves the accumulator untouched, and NAMES the box
    # and the files so a human resolves it.  bench property 4.
    repo=${1:-cluster}
    all=${FLEET_SSH_BOXES:-c01,c02,c03,c04,c05}
    boxes=$(printf '%s' "${all//,/ }")
    # :trap: GIT SPAWNS ITS OWN ssh AND IGNORES ~/.ssh/config's IdentityFile
    # FOR A URL WITH NO Host BLOCK.  MEASURED 2026-09-18: `ssh m04wsl` works
    # while `git fetch ssh://root@10.30.5.25:2200/...` returns "Please make
    # sure you have the correct access rights" on 5/5 -- a UNIFORM failure
    # that reads as a dead fleet.  It is not: ssh tries id_rsa/id_ecdsa/
    # id_ed25519, none of which exist, and never offers nx.rsa.  The
    # CONTROL that settles it is plain `ssh` to the same box in the same
    # minute: SSH_OK + a real HEAD.  Pass the key explicitly.
    export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -i $HOME/.ssh/nx.rsa -o BatchMode=yes -o StrictHostKeyChecking=no -o ControlPath=none -o ConnectTimeout=20"}

    drv=/workspace/$repo
    [ -d "$drv/.git" ] || { echo "reduce: no repo at $drv" >&2; exit 2; }

    # The DRIVER is the accumulator.  It is the only checkout guaranteed to
    # be reachable from every box (each box is reachable from here, but the
    # boxes cannot all reach each other -- peer-to-peer TCP is NSG-denied).
    printf '%-5s %-9s %s\n' BOX STATE DETAIL
    git -C "$drv" fetch -q origin master 2>/dev/null
    acc_before=$(git -C "$drv" rev-parse --short HEAD)

    rc=0
    for b in $boxes; do
        ip=$(python3 -c "import json;print(json.load(open('$drv/bin/fleet-ips.json'))['${b}'].split()[0])" 2>/dev/null)
        [ -n "$ip" ] || { printf '%-5s %-9s %s\n' "$b" "SKIP" "no mesh ip"; continue; }
        url="ssh://root@$ip:2200/workspace/$repo"

        if ! git -C "$drv" fetch -q "$url" master 2>/dev/null; then
            printf '%-5s %-9s %s\n' "$b" "UNREACH" "fetch failed ($ip:2200)"; rc=1; continue
        fi
        f=$(git -C "$drv" rev-parse --short FETCH_HEAD)

        if git -C "$drv" merge-base --is-ancestor FETCH_HEAD HEAD 2>/dev/null; then
            printf '%-5s %-9s %s\n' "$b" "contained" "$f already in the tip"; continue
        fi

        if git -C "$drv" merge --no-edit FETCH_HEAD >/dev/null 2>&1; then
            printf '%-5s %-9s %s\n' "$b" "MERGED" "$f -> $(git -C "$drv" rev-parse --short HEAD)"
        else
            cf=$(git -C "$drv" diff --name-only --diff-filter=U 2>/dev/null | paste -sd, - | cut -c1-60)
            git -C "$drv" merge --abort 2>/dev/null
            printf '%-5s %-9s %s\n' "$b" "CONFLICT" "$f :: $cf"
            echo "  reduce STOPPED at $b -- resolve by hand, then re-run (it is idempotent)." >&2
            exit 3
        fi
    done

    acc_after=$(git -C "$drv" rev-parse --short HEAD)
    if [ "$acc_before" = "$acc_after" ]; then
        echo "-- nothing to reduce; tip unchanged at $acc_after"
    else
        echo "-- reduced $acc_before -> $acc_after; push with:  git -C $drv push origin master"
    fi

    # :trap: "contained" ON 5/5 IS NOT "THE FLEET IS AT THE TIP", AND THE
    # TWO LOOK IDENTICAL IN THIS TABLE.  MEASURED 2026-09-18: reduce printed
    # `contained` for every box and `tip unchanged`, while the five boxes
    # sat on FIVE DIFFERENT HEADS (a0a2ea8 / d360a77 / e1c9ef7 / 84848d5 /
    # 532123f).  Both statements were true: the driver's tip already held
    # every box's work.  REDUCE IS N->1 AND ONLY EVER ASKS ABOUT THE 1.
    # Distributing the result back is the SEPARATE 1->N half, and it is a
    # fast-forward per box, not a merge.  Read as "the fleet converged",
    # a green reduce table leaves four boxes behind.
    echo "-- reduce is N->1; boxes are NOT updated.  Converge them with:"
    echo "   $0 disperse $repo"
    exit "$rc"
    ;;

disperse)
    # DISPERSE — the 1->N half of reduce.  `recipes.sh disperse [repo]`
    #
    # Separate from `broadcast` because the payload is not bytes: each box
    # already has the objects' ancestor, so this is a FETCH + FAST-FORWARD
    # the box performs on itself, not a file copy.  Parallel is correct
    # here (reduce's serial constraint is about producing ONE tip; every
    # box consuming the same tip is independent).
    #
    # :trap: --ff-only IS THE WHOLE SAFETY PROPERTY.  A plain `git pull`
    # on a box that has local commits would MERGE -- creating a second tip
    # on a box nobody is watching, which the next reduce must then clean
    # up.  --ff-only refuses instead, and the refusal is the signal that
    # the box has work the tip does not: feed it back through reduce.
    repo=${1:-cluster}
    all=${FLEET_SSH_BOXES:-c01,c02,c03,c04,c05}
    drv=/workspace/$repo
    tip=$(git -C "$drv" rev-parse HEAD)

    # :trap: A DROPPED ROW IS THE ONE FAILURE THIS TABLE MUST NOT HAVE, and
    # the obvious shape produces it.  MEASURED 2026-09-18: two `printf`s fed
    # by a 2-line remote probe printed THREE rows for a five-box fleet --
    # the unreachable boxes emitted nothing and silently left the table.
    # A sweep that omits the broken box is worse than one that fails.  So
    # the probe emits exactly ONE line, always, and ssh failure is caught
    # by the caller rather than by the absence of output.
    #
    # :trap: AHEAD IS NOT AT-TIP.  MEASURED: c03 answered `is-ancestor tip
    # HEAD` = true while sitting on 0cfe427, a DESCENDANT of the tip -- it
    # had committed since the reduce.  Both are "the tip is contained", and
    # collapsing them reports a box with unreduced work as converged.  The
    # equality test has to come FIRST.
    printf '%-5s %-9s %s\n' BOX STATE HEAD
    # :trap: `git fetch` CAN HANG FOREVER AND TAKE THE ROW WITH IT.  MEASURED
    # 2026-09-18 on c04: plain `ssh c04wsl git rev-parse HEAD` answered in
    # under a second, while this recipe printed NO ROW for it at all.  The
    # cause is not the network -- it is the Windows credential manager the
    # fleet uses as `credential.helper`, which prompts when it has no cached
    # credential for the remote, and over ssh there is no console to prompt
    # on, so it blocks.  `ConnectTimeout` does not cover it (the connection
    # succeeded; the remote COMMAND stalled), and the box that hangs is
    # exactly the box you needed to see.  Two guards: a hard `timeout` on
    # the remote fetch, and GIT_TERMINAL_PROMPT=0 so it fails instead of
    # asking.  A stale fetch is survivable here -- the merge below is
    # against the tip passed from the driver, not against origin.
    #
    # :trap: "DIVERGED" AND "NEVER GOT THE OBJECT" ARE OPPOSITE FAULTS THAT
    # LOOK THE SAME FROM THE ELSE BRANCH.  MEASURED 2026-09-18: c04 reported
    # DIVERGED, which reads as "this box has local commits, reduce it" -- it
    # had ZERO (`origin/master..HEAD` = 0).  Its fetch had failed, so the tip
    # COMMIT WAS NOT ON THE BOX, and `merge --ff-only <unknown sha>` fails
    # exactly like a non-fast-forward.  The repairs are opposite: DIVERGED
    # needs a reduce, NOFETCH needs the box's credentials fixed.  `cat-file
    # -e` on the tip separates them and must be asked BEFORE the merge.
    printf '%s\n' "${all//,/ }" | tr ' ' '\n' | parallel --tag -j8 \
      "timeout 120 ssh -o BatchMode=yes -o ConnectTimeout=25 -o ControlPath=none {}wsl \
        'cd $drv 2>/dev/null || { echo \"NOREPO -\"; exit 0; }
         export GIT_TERMINAL_PROMPT=0
         timeout 45 git fetch -q origin master 2>/dev/null
         h=\$(git rev-parse HEAD)
         if   [ \"\$h\" = $tip ];                                  then s=AT-TIP
         elif git merge-base --is-ancestor $tip HEAD 2>/dev/null; then s=AHEAD
         elif ! git cat-file -e $tip 2>/dev/null;                 then s=NOFETCH
         elif git merge --ff-only $tip >/dev/null 2>&1;           then s=FF
         else s=DIVERGED; fi
         echo \"\$s \$(git rev-parse --short HEAD)\"' 2>/dev/null \
       || echo UNREACH -" |
      while read -r b state head; do
          printf '%-5s %-9s %s\n' "$b" "$state" "$head"
      done
    ;;

*)
    echo "recipes.sh: unknown recipe '$recipe' (try: recipes.sh list)" >&2
    exit 2
    ;;
esac
