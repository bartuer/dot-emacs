# usage: FLEET_BOX=<box> bash 39.shell.sh   -- idempotent, light: cli + bashrc block, host + container
CL=/workspace/cluster; CLI=$CL/bin/cli-sessions.sh
cd $CL 2>/dev/null || { echo NO-REPO; exit 0; }
git config --global --add safe.directory $CL 2>/dev/null
timeout 120 git pull -q --ff-only --no-edit >/dev/null 2>&1 || timeout 120 bash bin/box-pull.sh >/dev/null 2>&1
v=$(git log -1 --format=%h -- bin/cli-sessions.sh)
ln -sfn $CLI /usr/local/bin/cli; ln -sfn $CL/bin/room.sh /usr/local/bin/room
B=${FLEET_BOX:-}
for ip in $(hostname -I 2>/dev/null); do
  [ -n "$B" ] || B=$(jq -r --arg ip "$ip" '.regions[].boxes|to_entries[]|select(.value==$ip)|.key' bin/fleet-ips.json 2>/dev/null | head -1)
done
[ -n "$B" ] || { echo "NO-BOXNAME $(hostname -I)"; exit 0; }
blk() { cat <<'BLK'
# >>> fleet shell >>>   (managed by 39.shell.sh -- replaced whole on each roll-out)
_cli_complete() { COMPREPLY=($(compgen -W "all $(cut -d'|' -f1,2 ~/.copilot/sessions 2>/dev/null | tr '|' '\n' | sort -u)" -- "${COMP_WORDS[COMP_CWORD]}")); }
complete -F _cli_complete cli
# t [name] [session]: attach-or-create tmux "<box>.<name>" running GHCP CLI.
# session (default = name) is resumed ONLY if it has events.jsonl -- a bare or unloadable
# --resume drops copilot into its interactive picker; otherwise start it fresh under that name.
# tmux gives a new session the SERVER's env, not this shell's -> forward COPILOT_* with -e.
# no args -> per-box defaults T_NAME/T_SID/T_ARGS (39.shell.sh converts an old `alias t=` into them).
alias t >/dev/null 2>&1 || function t {
    local v n s r d; local -a e=()
    if (($#)); then n=$1; s=${2:-$1}; else n=${T_NAME:-main}; s=${T_SID:-$n}; fi
    for v in ${!COPILOT_PROVIDER_@} COPILOT_MODEL; do [ -n "${!v:-}" ] && e+=(-e "$v=${!v}"); done
    for d in $(grep -lxF -e "id: $s" -e "name: $s" ~/.copilot/session-state/*/workspace.yaml 2>/dev/null); do
        d=${d%/*}; [ -s "$d/events.jsonl" ] && { r="--resume ${d##*/}"; break; }
    done
    [[ -z $r && $s =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] && r="--session-id $s"
    tmux new -A -s "${FLEET_BOX}.$n" "${e[@]}" \
      "copilot --model ${COPILOT_MODEL:-claude-opus-5-5} --allow-all ${T_ARGS:-}--add-dir /workspace/cluster ${r:---name '$s'}"
}
# <<< fleet shell <<<
BLK
}
put() {  # $1 = bashrc path (reads/writes via $2 prefix cmd)
    f=$1; tmp=$(mktemp)
    $2 cat "$f" 2>/dev/null | sed '/^# >>> fleet shell >>>/,/^# <<< fleet shell <<</d' > $tmp
    local al n sid ar; al=$(grep -m1 '^alias t=' $tmp)   # old per-box alias t -> defaults for function t
    if [ -n "$al" ]; then
        n=$(sed -n 's/.* -s \([^ ]*\) .*/\1/p' <<<"$al"); n=${n#"$B".}; n=${n#"$B"_}
        sid=$(sed -n 's/.*--resume \([^ "'"'"']*\).*/\1/p' <<<"$al"); ar=
        grep -q -- '--autopilot' <<<"$al" && ar='--autopilot '
        sed -i "s|^alias t=.*|T_NAME=${n:-main} T_SID=$sid T_ARGS='$ar'  # was: alias t (converted by 39.shell.sh)|" $tmp
    fi
    { grep -v '^export FLEET_BOX=' $tmp; blk | sed "1a export FLEET_BOX=$B"; } > $tmp.n
    $2 sh -c "test -f $f.pre39 || cp -p $f $f.pre39"
    if [ -n "$2" ]; then $2 sh -c "cat > $f" < $tmp.n; else cat $tmp.n > $f; fi
    rm -f $tmp $tmp.n
}
put ~/.bashrc ""
H=$(bash -ic 'printf "%s,%s,%s" "$(command -v cli)" "$(type -t t)" "$(complete -p cli 2>/dev/null | grep -c _cli_complete)"' 2>/dev/null | tail -1)
C=-
if command -v docker >/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx officeagent-dev; then
    D="docker exec -i officeagent-dev"
    if $D test -x $CLI; then $D ln -sfn $CLI /root/local/bin/cli; $D ln -sfn $CL/bin/room.sh /root/local/bin/room; fi
    put /root/.bashrc "$D"
    C=$($D bash -ic 'printf "%s,%s,%s" "$(readlink -f $(command -v cli))" "$(type -t t)" "$COPILOT_MODEL"' 2>/dev/null | tail -1)
fi
echo "$v host:$H ctr:$C"
