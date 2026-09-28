#!/usr/bin/env bash
# 49.ctr.test.sh IMG [REF] -- plan 49 T: clean-container test of cli + room from a public dot-emacs clone.
# Throwaway `docker run --rm --network host` (49-D7); ~/.ssh + ~/.fleet read-only; NO /workspace/cluster.
# Prints one line per check; last line PASS n/n or FAIL.
IMG=${1:?usage: 49.ctr.test.sh ubuntu:24.04|ubuntu:26.04 [ref]}; REF=${2:-master}
docker run --rm --network host -e REF="$REF" -v ~/.ssh:/root/.ssh:ro -v ~/.fleet:/root/.fleet:ro "$IMG" bash -c '
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null && apt-get -qq install -y git openssh-client python3 tmux jq parallel curl procps >/dev/null 2>&1
git clone -q https://github.com/bartuer/dot-emacs /d && git -C /d checkout -q "$REF" && echo "ref=$(git -C /d log -1 --format=%h)"
bash /d/install/fleet-install.sh; export PATH=~/local/bin:$PATH
n=0; ok=0; c() { n=$((n+1)); if eval "$2" >/tmp/o 2>&1; then ok=$((ok+1)); echo "ok   $1 $(head -1 /tmp/o | cut -c1-90)"; else echo "FAIL $1 $(tail -2 /tmp/o | tr "\n" " " | cut -c1-160)"; fi; }
c no-cluster "test ! -e /workspace/cluster"
c cli-V      "cli -V"
c cli-r      "timeout 120 cli -r | head -1 | grep -E \"[0-9]+ live/\""
c room-read  "room -c session_top read --peek"
c room-tasks "room -c session_top tasks"
gt() { python3 - <<PY
import sys; sys.path.insert(0, "/d/install/fleet"); import room
r = room.gate({"needs": {"tier": "wsl"}, "repo": "dot-emacs@master"})
print("refused:", r); sys.exit(0 if r else 1)   # a ctr is not tier wsl -> must refuse
PY
}
c room-gate  gt
c export-ok  "grep -c . /d/install/fleet/MANIFEST"
[ $ok = $n ] && echo "PASS $ok/$n" || { echo "FAIL $ok/$n"; exit 1; }'
