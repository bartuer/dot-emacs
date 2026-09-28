"""room_gate -- the claim gate shared by room.py (portable) and fleet.py (hub).

49-D3: extracted from fleet.py so the portable cli/room set (49-D4) needs no
fleet.py.  fleet.py re-exports these names; edit them HERE only.
GATE_SH runs on the claimant box and prints key=value lines; _refuse reads
them and returns '' (admitted) or the FIRST gate that refused (37 1.3).
"""
import os

__all__ = ["GATE_SH", "SLOT_CAP", "_refuse"]

GATE_SH = r"""
cd /workspace/cluster 2>/dev/null || { echo repo=absent; exit 0; }
echo slots=$(tmux ls -F '#{session_name}' 2>/dev/null | awk -F+ 'NF==4' | wc -l)
echo excel=$(tmux ls -F '#{session_name}' 2>/dev/null | awk -F+ 'NF==4' | while read s; do tmux show-environment -t "=$s:" ORCH_EXCEL 2>/dev/null; done | grep -c =1)
echo lserver=$(curl -s -o /dev/null -w '%{http_code}' -m 5 127.0.0.1:11434/health)
echo inflight=$(ss -Htn state established '( sport = :11434 )' 2>/dev/null | wc -l)
echo tserver=$(curl -s -o /dev/null -w '%{http_code}' -m 5 127.0.0.1:11435/token/ado)
echo wserver=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}\n' | nc -q2 127.0.0.1 47390 2>/dev/null | grep -c jsonrpc)
echo ahead=$(git log --oneline @{u}..HEAD 2>/dev/null | wc -l)
echo dirty=$(git status --porcelain -uno | wc -l)
"""
SLOT_CAP = int(os.environ.get("ORCH_SLOT_CAP", "5"))


def _refuse(g: dict, excel: bool) -> str:
    """'' = admitted; else the FIRST gate that refused (37 1.3 ruling)."""
    if not g["reach"]:
        return "reach"
    if g.get("repo") == "absent":
        return "repo"
    if int(g["slots"]) >= SLOT_CAP:
        return f"slots {g['slots']}/{SLOT_CAP}"
    if g["lserver"] != "200":
        return f"lserver {g['lserver']}"
    if g["tserver"] != "200":
        return f"tserver {g['tserver']}"
    if int(g["ahead"]) or int(g["dirty"]):
        return f"checkout ahead={g['ahead']} dirty={g['dirty']}"
    if excel and (g["wserver"] == "0" or int(g["excel"])):
        return f"wserver={g['wserver']} excel_units={g['excel']}"
    return ""
