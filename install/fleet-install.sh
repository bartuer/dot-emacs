#!/usr/bin/env bash
# fleet-install.sh -- plan 49-D5: cli + room from a dot-emacs clone, no cluster checkout.
# Idempotent, local-only: links ~/local/bin/{cli,room} -> install/fleet/ (the
# cluster export, 49-D1), links the room skill into ~/.copilot/skills/room if
# absent, and reports what ${FLEET_HOME:-~/.fleet} lacks.  Never writes ~/.fleet (49-D2).
# Lives beside install/fleet/, not in it: that dir is export output (--check = no extra files).
set -eu
F=$(cd "$(dirname "$(readlink -f "$0")")/fleet" && pwd)
[ -x "$F/cli-sessions.sh" ] || { echo "no export at $F" >&2; exit 1; }
chg=0
lnk() {  # $1 target $2 link
    [ "$(readlink "$2" 2>/dev/null)" = "$1" ] && return 0
    [ -e "$2" ] && [ ! -L "$2" ] && { echo "keep $2 (not a symlink)"; return 0; }
    mkdir -p "$(dirname "$2")"; ln -sfn "$1" "$2"; echo "link $2 -> $1"; chg=1
}
lnk "$F/cli-sessions.sh" "$HOME/local/bin/cli"
lnk "$F/room.sh"         "$HOME/local/bin/room"
[ -e "$HOME/.copilot/skills/room" ] || lnk "$F/skills/room" "$HOME/.copilot/skills/room"
FH=${FLEET_HOME:-$HOME/.fleet}
for f in fleet-ips.json fleet-connection.json cluster.md; do
    [ -s "$FH/$f" ] || echo "missing $FH/$f (fleet facts are not in this repo; copy from a fleet box)"
done
case ":$PATH:" in *":$HOME/local/bin:"*) ;; *) echo "add to PATH: $HOME/local/bin";; esac
[ $chg = 1 ] || echo "no change ($(head -1 "$F/MANIFEST"))"
