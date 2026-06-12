#!/bin/sh
set -eu

# For dev.base we package files from the packages we explicitly installed
# (git, openssh-clients, openssh-server, glibc-lang, glibc-i18n when available,
# file) plus SSH config.
# Base-image packages are NOT included — they're already there at runtime.

OUT=/opt/amd64.arcadia.dev.base.azl3.0.tar.gz

# Collect files from the packages we added on top of base,
# plus entry point and shell config.
FLIST=$(mktemp)
PKGS="git openssh-clients openssh-server glibc-lang file"
if rpm -q glibc-i18n >/dev/null 2>&1; then
  PKGS="$PKGS glibc-i18n"
fi

rpm -ql $PKGS 2>/dev/null \
  | sort -u \
  | while read -r f; do [ -e "$f" ] && [ ! -d "$f" ] && echo "$f"; done \
  | sed 's|^/||' > "$FLIST"
echo bin/entry >> "$FLIST"
echo root/.bashrc >> "$FLIST"
echo root/.gitconfig >> "$FLIST"

# Pre-generated SSH host keys (from ssh-keygen -A in Dockerfile)
find /etc/ssh -name 'ssh_host_*' -type f 2>/dev/null \
  | sed 's|^/||' >> "$FLIST"

# Custom sshd_config
echo etc/ssh/sshd_config >> "$FLIST"

# --- LSP servers installed via pip (jedi-language-server, outside rpm db) ---
# Collect every file belonging to jedi-language-server + all its dist-info.
# pip show -f lists paths relative to the package's Location.
/app/officepy/bin/pip show -f jedi-language-server 2>/dev/null \
  | awk '/^Location:/{loc=$2} /^Files:/{p=1;next} p && /^ /{gsub(/^ /,""); print loc "/" $0}' \
  | sort -u \
  | while read -r f; do [ -e "$f" ] && [ ! -d "$f" ] && echo "$f"; done \
  | sed 's|^/||' >> "$FLIST"
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
