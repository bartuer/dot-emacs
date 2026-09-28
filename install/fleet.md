# install/fleet — `cli` + `room` from a dot-emacs clone

`install/fleet/` holds the fleet session console (`cli`) and the room chat/task
tool (`room`), so a box gets them from a **public dot-emacs clone or bundle**
with no `/workspace/cluster` checkout. (plan 49, `.github/REPL/49.make.room.decouple.org.txt`)

> This README sits **beside** `install/fleet/`, not in it: that dir is generated
> and `--check` rejects any file the export did not write.

**Who needs what.** A dot-emacs user needs only this repo: `install/fleet-install.sh`
and `install/fleet/` are committed here (public GitHub). Only a *maintainer*
refreshing the copy after a cluster change needs the cluster checkout
(`room-export.sh`, section "Updating after a cluster change").

## Quick start

```bash
git clone https://github.com/bartuer/dot-emacs && cd dot-emacs
bash install/fleet-install.sh          # idempotent; 2nd run prints "no change"
export PATH=~/local/bin:$PATH
cli -V                                 # cli 2026.09.28.N
cli -r | head -1                       # "... | N live/M box"
room -c session_top read --peek
```

Needs: `bash git openssh-client jq tmux curl procps parallel`, and **`python3` for room**
(cli works without it). `~/.ssh` must reach the boxes.

`fleet-install.sh` does exactly this, and nothing else:
- links `~/local/bin/cli -> install/fleet/cli-sessions.sh` and `~/local/bin/room -> install/fleet/room.sh`
  (never replaces a real file, only symlinks);
- links `~/.copilot/skills/room -> install/fleet/skills/room` if absent;
- prints which fleet facts are missing from `${FLEET_HOME:-~/.fleet}`. It **never writes** `~/.fleet`.

## Fleet facts are NOT in this repo

dot-emacs is public. The box/IP facts live only in `${FLEET_HOME:-~/.fleet}`:

| file                    | used by                     |
|-------------------------|-----------------------------|
| `fleet-ips.json`        | cli box list, room islands  |
| `fleet-connection.json` | room hub reachability       |
| `cluster.md`            | exec_plan / org_plan skills |

Copy them from a fleet box (`scp -r c00:.fleet ~/`). The export refuses to copy
`fleet-*.json` / `cluster.md` (rc 2), and `--check` flags them.

## One source: where to edit

| what                     | where                                  |
|--------------------------|----------------------------------------|
| cli / room code          | **cluster** `bin/` only                |
| `install/fleet/*`        | generated — never hand-edit            |
| installer, test, this doc| dot-emacs `install/fleet-install.sh`, `install/49.ctr.test.sh`, `install/fleet.md` |

## Updating after a cluster change

```bash
cd /workspace/cluster && git pull --ff-only          # the fix is committed there first
cd /workspace/dot-emacs
bash /workspace/cluster/bin/room-export.sh install/fleet
bash /workspace/cluster/bin/room-export.sh --check install/fleet   # "OK cluster <sha> 12 files", rc 0
git add install/fleet && git commit -m "re-export install/fleet = cluster <sha> (cli <ver>)" && git push
```

`MANIFEST` line 1 is `cluster <sha>` (`+dirty` if exported from uncommitted
work — don't commit that); the rest is `sha256sum` format. `--check` exits 1 on
a hand edit, an unlisted file, or a copy that no longer matches cluster HEAD.
Stray `__pycache__/` from running room in the clone also counts (gitignored,
just `rm -rf install/fleet/__pycache__` before checking).

Then verify in clean containers, one per image (each ~2–4 min):

```bash
bash install/49.ctr.test.sh ubuntu:24.04 <dot-emacs-sha>   # PASS 7/7
bash install/49.ctr.test.sh ubuntu:26.04 <dot-emacs-sha>   # PASS 7/7
```

The test clones the **pushed** sha from GitHub (push first), mounts `~/.ssh` and
`~/.fleet` read-only, uses host network, and asserts: no `/workspace/cluster`,
`cli -V`, `cli -r` header, `room read`, `room tasks`, room gate refuses
(`tier wsl!=ctr`), MANIFEST present.

Last: re-pin and rebuild the bundles (next section).

## Bundles

`tar -zxf <bundle> -C /` already carries `/root/etc/el/install/fleet` plus
`~/local/bin/{cli,room}` symlinks into it:

| bundle                            | builder                                                   | picks up install/fleet via |
|-----------------------------------|-----------------------------------------------------------|----------------------------|
| `amd64.emacs30.1_26.04`           | `build/emacs-30.1-treesitter-ubuntu-26.04/`               | `DOT_EMACS_COMMIT` pin — bump it |
| `amd64.arcadia.emacs30.1_azl3.0`  | `build/emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/` | clones HEAD at build time |

Archived bundles and their sha256 rows are in cluster `archive/README.split.md`.

## Which cli/room wins on a box

Each shell (bundle `.bashrc`) and `install/fleet-shell.sh` link to the first that exists:

1. `/workspace/cluster/bin/` — a live cluster checkout (cluster edits land here first);
2. `/root/etc/el/install/fleet/` — the vendored export.

## Known gotchas

- **bash 5.2 (ubuntu 24.04)**: a bare `wait` also waits on a `2> >(…)`
  process substitution and never returns — this hung `cli -r` before cli
  2026.09.28.5 (cluster 44d06fd). Wait on a pid instead.
- room without `python3` fails (`room -h`); bare ubuntu:26.04 and some base
  images lack it.
- `room.py`'s default hub list names boxes (`cj00wsl,c00wsl,c16wsl`) — names
  only, no IPs; override with `ROOM_GATEWAYS`.
