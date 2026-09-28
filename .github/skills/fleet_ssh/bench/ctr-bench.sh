#!/usr/bin/env bash
# ctr-bench.sh -- is `-t ctr` actually FASTER than `docker exec` over wsl?
#
# WHY THIS EXISTS: the assumption "now we have ssh into the container, the
# check will be faster" is plausible and MOSTLY WRONG, and a recipe rewritten
# on it would trade a working path for no gain.  This arm measures the two
# routes head to head so the claim is a number, not a belief.
#
# MEASURED 2026-09-19, 5 boxes, AFTER the tier bug below was fixed:
#     fields   wsl+docker exec   -t ctr    speedup
#          1   5627ms            582ms      9.7x
#          4   5627ms            569ms      9.9x
#          8   6095ms            653ms      9.3x
#
# WHY IT IS ~10x AND FLAT IN FIELD COUNT: `docker exec` needs a full RELAY
# ssh hop to the distro (ProxyCommand -> Windows -> WSL) before it can fork
# anything, and that hop is the whole cost.  `-t ctr` dials the container's
# :2222 on the box's MESH ip directly -- one hop on the fast subnet.  The
# gap is the relay, not the fork, which is why adding fields barely moves
# either arm.
#
# :*** THIS BENCH FIRST REPORTED "NO DIFFERENCE" AND THAT WAS THE BUG. ***
# The first run measured 5.2s vs 5.0s and I nearly concluded the idea was
# not worth it.  `-t ctr` was SILENTLY ANSWERING FROM THE DISTRO: `ssh -G
# c02wsl` returns `hostname c02wsl` (the alias, unresolved -- the address
# lives in the ProxyCommand), so the tier dialled `c02wsl:2222` and ssh
# routed it back through the relay.  I was benchmarking the distro against
# itself, and a ~0 delta is exactly what that produces.
#
# THE CONTROL THAT CAUGHT IT is the one SKILL.md already prescribes for
# `-t win`: ctr and wsl must DISAGREE.
#     -t ctr   CPC-bazho-PMBMNctr   NAME="Microsoft Azure Linux"
#     -t wsl   CPC-bazho-PMBMN      PRETTY_NAME="Ubuntu 26.04.1 LTS"
# Identical rows mean the tier did not land.  RUN THAT ASSERTION BEFORE
# TRUSTING ANY NUMBER HERE -- a benchmark of the wrong tier is not slow,
# it is meaningless.
#
# Usage:   bench/ctr-bench.sh [fields]     # default 4
# Exit:    0 both routes answered · 1 a route failed to produce a table
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FS="$HERE/../fleet-ssh.sh"
N="${1:-4}"
CTR="${FLEET_CTR_NAME:-officeagent-dev}"

# Build N equivalent probes for each route.  They must ask the SAME
# questions or the comparison is meaningless.
probes=(os='head -1 /etc/os-release' hn='cat /etc/hostname' uid='id -u' k='uname -r'
        pwd='pwd' e='echo x' t='date +%s' n='node -v 2>/dev/null | head -1')
ctr_args=(); wsl_args=()
for ((i=0; i<N && i<${#probes[@]}; i++)); do
    key="${probes[$i]%%=*}"; cmd="${probes[$i]#*=}"
    ctr_args+=("$key=$cmd")
    wsl_args+=("$key=docker exec $CTR sh -lc \"$cmd\"")
done

timeit() { local s e; s=$(date +%s%N); "$@" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e-s)/1000000 )); }

# GATE: prove the tier LANDED before timing anything.  A benchmark of the
# wrong tier is not slow, it is meaningless -- that is how this file's
# first version reported "no difference".
ctr_hn=$(bash "$FS" -b "$(echo "${FLEET_SSH_BOXES:-c01,c02,c03,c04,c05}" | cut -d, -f1)" -t ctr hn='cat /etc/hostname' 2>/dev/null | tail -1 | awk '{print $2}')
case "$ctr_hn" in
    *ctr) : ;;
    *) echo "FAIL: -t ctr did not land in a container (hostname=$ctr_hn, expected a *ctr suffix)" >&2
       echo "      the tier is answering from the DISTRO -- fix that before trusting a number" >&2
       exit 1 ;;
esac
printf 'tier_ok   ctr hostname=%s\n' "$ctr_hn"

a=$(timeit bash "$FS" "${wsl_args[@]}")
b=$(timeit bash "$FS" -t ctr "${ctr_args[@]}")

# GRADE ON A TABLE, not on the clock alone: a route that returns instantly
# because it failed is not faster.
rows_a=$(bash "$FS" "${wsl_args[@]}" 2>/dev/null | grep -c '^c0' || echo 0)
rows_b=$(bash "$FS" -t ctr "${ctr_args[@]}" 2>/dev/null | grep -c '^c0' || echo 0)

printf 'fields=%s\n' "$N"
printf '%-18s %6sms  rows=%s\n' 'wsl+docker exec' "$a" "$rows_a"
printf '%-18s %6sms  rows=%s\n' '-t ctr'          "$b" "$rows_b"
printf 'delta=%sms  (negative means ctr is slower)\n' "$((a-b))"

[ "$rows_a" -gt 0 ] && [ "$rows_b" -gt 0 ] || { echo "FAIL: a route produced no rows" >&2; exit 1; }
[ "$rows_a" = "$rows_b" ] || { echo "FAIL: routes disagree on row count ($rows_a vs $rows_b)" >&2; exit 1; }
exit 0
