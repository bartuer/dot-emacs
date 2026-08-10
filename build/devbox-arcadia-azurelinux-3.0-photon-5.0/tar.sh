#!/bin/sh
set -eu

# For dev.base we package files from the packages we explicitly installed
# (git, openssh-clients, openssh-server, glibc-lang, glibc-i18n when available,
# file, jq, rsync) plus SSH config and pinned upstream commands.
# Base-image packages are NOT included — they're already there at runtime.

OUT=/opt/amd64.arcadia.dev.base.azl3.0.tar.gz

# Collect files from the packages we added on top of base,
# plus entry point and shell config.
FLIST=$(mktemp)
PKGS="git openssh-clients openssh-server glibc-lang file jq rsync"
if rpm -q glibc-i18n >/dev/null 2>&1; then
  PKGS="$PKGS glibc-i18n"
fi

# Include RPM-owned runtime libraries introduced by jq and rsync.
RUNTIME_PKGS=$(
  for cmd in jq rsync; do
    ldd "$(command -v "$cmd")" 2>/dev/null \
      | awk '/=> \// { print $3 } /^\// { print $1 }'
  done \
    | while read -r lib; do rpm -qf "$lib" 2>/dev/null || true; done \
    | sort -u
)
PKGS="$PKGS $RUNTIME_PKGS"

rpm -ql $PKGS 2>/dev/null \
  | sort -u \
  | while read -r f; do [ -e "$f" ] && [ ! -d "$f" ] && echo "$f"; done \
  | sed 's|^/||' > "$FLIST"
echo bin/entry >> "$FLIST"
echo root/.bashrc >> "$FLIST"
echo root/.gitconfig >> "$FLIST"
echo root/.ssh/config >> "$FLIST"
echo root/.ssh/authorized_keys >> "$FLIST"
echo usr/local/bin/rg >> "$FLIST"
echo usr/local/bin/parallel >> "$FLIST"

# Pre-generated SSH host keys (from ssh-keygen -A in Dockerfile)
find /etc/ssh -name 'ssh_host_*' -type f 2>/dev/null \
  | sed 's|^/||' >> "$FLIST"

# Custom sshd_config
echo etc/ssh/sshd_config >> "$FLIST"

# --- LSP servers installed via pip (jedi-language-server + full transitive closure) ---
# We must bundle ALL transitive deps because:
#   - Some deps (e.g. cattrs) are NEW and land in python3.12/site-packages
#   - Some deps (e.g. attrs) were ALREADY in the base image at python3.1/site-packages
#     but as an old version; pip upgrades them in-place at python3.1/site-packages.
#   - Going only 1 level deep misses these transitively-upgraded packages.
# Strategy: BFS over pip's Requires graph until no new packages found.
PIP=/app/officepy/bin/pip

_pip_direct_deps() {
  $PIP show "$1" 2>/dev/null \
    | awk '/^Requires:/{$1=""; gsub(/,/,""); print}' \
    | tr ' ' '\n' | grep -v '^$'
}

_pip_files_for_pkg() {
  $PIP show -f "$1" 2>/dev/null \
    | awk '/^Location:/{loc=$2} /^Files:/{p=1;next} p{
        if (/^[[:space:]]/ && NF>0) {
          f=$0; gsub(/^[[:space:]]*/,"",f); print loc "/" f
        } else { p=0 }
      }' \
    | while read -r f; do
        f=$(realpath -m "$f" 2>/dev/null) || continue
        [ -e "$f" ] && [ ! -d "$f" ] && echo "${f#/}"
      done
}

SEEN="jedi-language-server"
QUEUE="jedi-language-server"
while [ -n "$QUEUE" ]; do
  NEXT=""
  for pkg in $QUEUE; do
    for dep in $(_pip_direct_deps "$pkg"); do
      # normalise: pip package names are case-insensitive, use lowercase
      dep_lc=$(echo "$dep" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
      if ! echo " $SEEN " | grep -qi " $dep_lc "; then
        SEEN="$SEEN $dep_lc"
        NEXT="$NEXT $dep_lc"
      fi
    done
  done
  QUEUE=$NEXT
done

for pkg in $SEEN; do
  _pip_files_for_pkg "$pkg"
done | sort -u >> "$FLIST"

# Also capture the console-script entrypoint binary itself
find /app/officepy/bin -name 'jedi-language-server' -type f 2>/dev/null \
  | sed 's|^/||' >> "$FLIST"

# --- LSP servers installed via npm -g (typescript + typescript-language-server) ---
NPM_GPREFIX=$(npm config get prefix 2>/dev/null || echo /usr)
for mod in typescript typescript-language-server; do
  find "$NPM_GPREFIX/lib/node_modules/$mod" -type f 2>/dev/null \
    | sed 's|^/||' >> "$FLIST"
done
# npm wrapper scripts (symlinks → real files)
for cmd in tsc tsserver typescript-language-server; do
  target=$(readlink -f "$NPM_GPREFIX/bin/$cmd" 2>/dev/null || true)
  [ -n "$target" ] && echo "${target#/}" >> "$FLIST"
  [ -e "$NPM_GPREFIX/bin/$cmd" ] && echo "${NPM_GPREFIX#/}/bin/$cmd" >> "$FLIST"
done

sort -u "$FLIST" -o "$FLIST"
tar czf "$OUT" -C / -T "$FLIST"
rm -f "$FLIST"

echo "Created $OUT"