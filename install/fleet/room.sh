#!/usr/bin/env bash
# room.sh -- thin wrapper; the logic is bin/room.py (bin/ rule: Python holds logic).
exec python3 "$(dirname "$(readlink -f "$0")")/room.py" "$@"
