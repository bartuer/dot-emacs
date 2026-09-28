# Arcadia (Azure Linux 3.0) emacs/devbase build fixes — 2026-09-14

Found and fixed while executing `.github/REPL/03.emacs.bundle.org.txt`
Group 2, items 2.5/2.6, building locally on a `c01wsl` container-tier
box (32 CPU, 909G free, direct non-proxied internet, Docker overlayfs).

## 1. `emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/Dockerfile`: stale "already in base" claim

The Dockerfile's own header comment said:

```
# Pre-installed in base: gcc 13.2.0, g++, make, tar, curl, zlib-devel,
#   pkgconf, ncurses-libs, node v22, python 3.12
```

MEASURED FALSE for `gcc`, `make`, `which` against
`mcr.microsoft.com/officepy/codeexecutionjupyterext1:latest`
(digest `sha256:ab52c303b896d8f77be82b8837601f8c0e89e244153968cb46c42b192aa3fe28`,
pulled 2026-09-12):

```bash
docker run --rm --entrypoint sh <image> -c "rpm -qa | grep -iE 'gcc|^make|binutils'"
# -> only libgcc-13.2.0-7.azl3.x86_64 (runtime lib, not the compiler)
docker run --rm --entrypoint sh <image> -c "find / -xdev -iname gcc -o -iname make"
# -> nothing (only /usr/share/gcc-13.2.0 doc dir)
```

`zlib` (runtime), `pkgconf`, `ncurses`/`ncurses-libs`, `tar`, `curl` ARE
present — only the compiler toolchain (gcc/make) and `which` are
missing. `binutils` was already being installed explicitly by the
Dockerfile's own `tdnf install` line, so that part of the comment was
also stale but harmless (redundant explicit install already covered
it).

**Why `devbox-arcadia-azurelinux-3.0-photon-5.0` never noticed**: its
Dockerfile carries the identical stale comment but never actually
invokes `gcc` or `make` in any `RUN` step, so the false claim was
never exercised there.

**Symptom**: `RUN ... ./configure && make ...` for the aspell-en
dictionary (first source-compiled dependency in the Dockerfile) failed
with:
```
./configure: line 82: which: command not found
./configure: line 84: which: command not found
/bin/sh: line 1: make: command not found
```
exit code 127.

**Fix**: add `gcc make which` to the Dockerfile's `tdnf install -y`
list (unpinned, matching every other package in that same list — only
`TREE_SITTER_TAG`/`EMACS_LIBVTERM_COMMIT` are load-bearing pins per
this repo's rules). Available versions at fix time:
`gcc-13.2.0-7.azl3`, `make-4.4.1-2.azl3`, `which-2.21-8.azl3`.

## 2. `emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/amd64.tar.list`: hardcoded shared-lib version drift

`amd64.tar.list` is a hand-written manifest with exact filenames
including upstream patch-version suffixes for base-image system
libraries:

```
usr/lib/libgnutls.so.30.37.1
usr/lib/libhogweed.so.6.8
usr/lib/libnettle.so.8.8
```

MEASURED against the actual built image
(`codeexecutionjupyterext1:emacs30.1.arcadia`), these libraries are
now:

```
libgnutls.so.30.42.0
libhogweed.so.6.9
libnettle.so.8.9
```

i.e. the AzureLinux base image had shipped newer point releases since
the list was last hand-authored, and `tar -T amd64.tar.list` fails hard
(`Cannot stat: No such file or directory`, `Exiting with failure status
due to previous errors`) on the mismatch rather than silently skipping.

**Fix**: updated the three hardcoded entries in `amd64.tar.list` to the
MEASURED current filenames. This is a recurring class of bug — any
`.tar.list` with a fully-versioned shared-library filename will break
the next time the base image updates that library. A more durable fix
(not done here, scope-limited to unblocking this run) would be to
generate these three lines dynamically inside `tar.sh` via
`ls /usr/lib/libgnutls.so.30.* ...` instead of hardcoding them, the way
`devbox-*/tar.sh` already does for its `dpkg -L`/`rpm -ql`-driven file
lists. Left as a follow-up — not required to unblock this run, and
changing `tar.sh`'s generation strategy is a separate, more invasive
change than the plan's scope needed.

## 3. `devbox-arcadia-azurelinux-3.0-photon-5.0/tar.sh`: phantom `tsserver` entry from unguarded `readlink -f`

```sh
for cmd in tsc tsserver typescript-language-server; do
  target=$(readlink -f "$NPM_GPREFIX/bin/$cmd" 2>/dev/null || true)
  [ -n "$target" ] && echo "${target#/}" >> "$FLIST"
  [ -e "$NPM_GPREFIX/bin/$cmd" ] && echo "${NPM_GPREFIX#/}/bin/$cmd" >> "$FLIST"
done
```

GNU coreutils `readlink -f` canonicalizes a path SYNTACTICALLY even
when the target does not exist — it does not require the final
component to be present, only the parent directories to resolve. So
for `tsserver` (which is not present because `typescript@7.0.2`, the
current `npm install -g typescript` HEAD-of-major pull, folded the
`tsserver` binary out of the package — `typescript-language-server`
does not need it and still answers `--version` correctly), the command
still produced a non-empty `$target` string pointing at a file that
does not exist. That path is what got written to the file list, and
`tar -T` aborted:

```
tar: usr/bin/tsserver: Cannot stat: No such file or directory
tar: Exiting with failure status due to previous errors
```

**Fix**: guard the loop with an existence check on the SOURCE
(`$NPM_GPREFIX/bin/$cmd`) before calling `readlink -f` at all:

```sh
for cmd in tsc tsserver typescript-language-server; do
  [ -e "$NPM_GPREFIX/bin/$cmd" ] || continue
  target=$(readlink -f "$NPM_GPREFIX/bin/$cmd" 2>/dev/null || true)
  [ -n "$target" ] && echo "${target#/}" >> "$FLIST"
  echo "${NPM_GPREFIX#/}/bin/$cmd" >> "$FLIST"
done
```

**Note**: `devbox-ubuntu-24.04`'s `pack.sh` does not have this bug — it
builds its file list via `dpkg -L`, which only lists files a package
actually owns, so it never manufactures a phantom path in the first
place. This class of bug is specific to hand-rolled `readlink -f`
loops over commands that may or may not exist.

## Verified artifacts (all three, MEASURED sizes and smoke tests)

| tarball                                  | size (measured)      | smoke test                                                                 |
|-------------------------------------------|----------------------|-----------------------------------------------------------------------------|
| `amd64.emacs30.1_24.04.tar.gz`             | 198 MiB (207167222 B)| `emacs --version` → GNU Emacs 30.1; vterm `require` → OK                     |
| `amd64.arcadia.emacs30.1_azl3.0.tar.gz`    | 265 MiB (277081286 B)| `emacs --version` → GNU Emacs 30.1; vterm `require` → OK                     |
| `amd64.arcadia.dev.base.azl3.0.tar.gz`     | 47 MiB (49034304 B)  | `typescript-language-server --version` → 6.0.0; `jedi-language-server --version` → 0.47.0; ssh assets `-rw-r--r--` |

All three smoke tests ran in a clean container via `docker run
--entrypoint sh -v <builddir>:/opt <fresh-base-image> sh -c 'tar -zxf
/opt/<tarball> -C / && ldconfig && ...'`, in a SEPARATE shell from the
one that ran the build — never the same shell, per this repo's Verify
rule.
