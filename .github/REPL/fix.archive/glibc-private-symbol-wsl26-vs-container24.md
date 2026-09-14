# GLIBC_PRIVATE mismatch: WSL Ubuntu 26.04 vs a 24.04/azl3 build image

**Symptom.** Every binary in c01's WSL distro dies before `main`:

```
/bin/bash: symbol lookup error: /usr/lib/x86_64-linux-gnu/libc.so.6:
           undefined symbol: __nptl_change_stack_perm, version GLIBC_PRIVATE
```

Not just `bash` — `cat` fails identically. The dynamic loader is broken
for **every** dynamically linked executable, so the distro is unusable
while still reporting `STATE=Running` to `wsl.exe -l -v`.

**This is NOT "the box is down".** Measured, in this order:

| layer                     | result                                  |
|---------------------------|-----------------------------------------|
| `ssh c01win`              | `win-ok` — the Windows hop is healthy   |
| `wsl.exe -l -v` on c01    | `Ubuntu  Running  2` — the distro is up |
| port 2200 on c01win       | **0 listeners** — WSL sshd never started |
| any binary in the distro  | `symbol lookup error` (above)           |

So the ssh failure is a *consequence*: sshd cannot exec, therefore
nothing listens on 2200, therefore `c01wsl`'s ProxyCommand
(`ssh -q -W 127.0.0.1:2200 C01win`) gets `Connection closed`. The config
is correct and identical to c02's — verified line by line.

## Root cause: a private symbol that only exists in the OLD glibc

`__nptl_change_stack_perm` is a `GLIBC_PRIVATE` symbol. Private symbols
carry **no compatibility guarantee between glibc releases** — they are
internal plumbing, versioned so that a mismatched pair refuses to link
rather than corrupting memory. The error means some component in the
link chain was built against an older glibc that *exported* it, and is
now resolving against a newer libc that does not.

Measured glibc across the three tiers that matter here:

| tier                            | OS                         | glibc |
|---------------------------------|----------------------------|-------|
| WSL distro (c02/c03/c04)        | Ubuntu 26.04               | 2.43  |
| build image `ubuntu:24.04`      | Ubuntu 24.04               | 2.39  |
| container `officeagent-dev`     | Microsoft Azure Linux 3.0  | 2.38  |

And the symbol itself, on a healthy 26.04 WSL distro (c02):

```
readelf -sW /usr/lib/x86_64-linux-gnu/libc.so.6 | grep -c __nptl_change_stack_perm
0            # absent -- 26.04's libc does not export it
readelf -sW /usr/lib/x86_64-linux-gnu/libc.so.6 | grep -c GLIBC_PRIVATE
295          # ...while 295 other private symbols ARE exported
```

The `0` is the whole finding: the symbol the loader is asked for **does
not exist in 26.04**. Whatever is asking was built on 2.38/2.39.

## Why this bites the emacs/devbase bundle plan specifically

Plan 03 (`.github/REPL/03.emacs.bundle.org.txt`) builds root-extractable
tarballs in a container and unpacks them at `/` on a target. The tarballs
are built from:

- `emacs-30.1-treesitter-ubuntu-24.04`  → glibc **2.39**
- `devbox-ubuntu-24.04`                 → glibc **2.39**
- `*-arcadia-azurelinux-3.0-*`          → glibc **2.38**

The WSL *target* is Ubuntu 26.04 → glibc **2.43**.

**A tarball built at 2.38/2.39 and unpacked onto 2.43 is exactly the
configuration that produces this error** — and the failure mode is the
worst kind: it is not a build error, not an unpack error, and not
detectable by `tar tzf`. It surfaces only when the binary is executed,
and if the tarball overwrites anything in the loader's path it takes the
whole distro down with it, as c01 demonstrates.

### The directional rule

Glibc is **backward** compatible, not forward:

- built on OLD glibc → runs on NEW glibc  ✔ *for public symbols*
- built on NEW glibc → runs on OLD glibc  ✘
- **anything touching `GLIBC_PRIVATE` → neither direction is safe**

The middle row is the one people know. The third row is the one that
bit here: a private symbol makes even the "safe" direction unsafe,
because private versioning is exact-match by design.

:hard-rule: **DO NOT SHIP A TARBALL ACROSS A GLIBC BOUNDARY WITHOUT
MEASURING BOTH SIDES.** One command, before any bundle is trusted:

```bash
# build side and target side must agree, or the payload must be static
ldd --version | head -1
```

## Consequences for plan 03

1. **The WSL-tier bundle must be built on 26.04, not 24.04.** The
   `devbox-ubuntu-24.04` / `emacs-30.1-treesitter-ubuntu-24.04` recipes
   target the wrong glibc for this fleet. Either add a 26.04 builder or
   accept that those tarballs are container-only.
2. **The container-tier bundle is fine as-is** — azl3 builds land in an
   azl3 container; both sides are 2.38, no boundary crossed.
3. **`container-tmux.sh`'s precedent holds and explains why it works.**
   It ships ONE binary whose two libs were *verified present in the base
   image before shipping* — that check is the thing that makes a bundle
   safe, and it is exactly the check missing above.

## Recovery for c01

The distro cannot run a binary, so it cannot repair itself from inside.
From Windows:

```powershell
wsl.exe --shutdown          # then restart; if the libc is truly replaced,
                            # this will NOT fix it
```

If a bad unpack replaced `libc.so.6`, the honest options are restoring
that file from a known-good copy via `\\wsl$\Ubuntu\...` (Windows-side
file access does not need the distro's loader), or re-provisioning the
distro. Diagnose before acting: confirm whether `libc.so.6` was modified,
rather than assuming the upgrade did it.

:trap: **`STATE=Running` is not "healthy".** `wsl.exe -l -v` reports the
VM, not userspace. A distro whose loader is broken reports Running while
being unable to execute `/bin/true`.

:trap: **A tier can fail while every layer above it is green.** c01win
answered `win-ok` throughout. Probing the outermost reachable layer and
concluding "the box is up" would have missed this entirely; probing only
`c01wsl` and concluding "the box is down" was equally wrong. The layer
that actually failed was two hops in.
