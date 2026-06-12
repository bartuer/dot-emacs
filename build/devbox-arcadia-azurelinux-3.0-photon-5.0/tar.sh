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

# LSPs (jedi-language-server via pip, typescript-language-server + typescript
# via npm -g) are installed by the Dockerfile so they exist in the IMAGE.
# We deliberately exclude them from the TARBALL — install.amd64.sh re-installs
# them on the target via pip/npm, keeping the dev.base tarball lean.
tar czf "$OUT" -C / \
    --exclude='app/officepy/*' \
    --exclude='usr/lib/node_modules/typescript' \
    --exclude='usr/lib/node_modules/typescript-language-server' \
    --exclude='usr/bin/tsc' \
    --exclude='usr/bin/tsserver' \
    --exclude='usr/bin/typescript-language-server' \
    -T "$FLIST"
rm -f "$FLIST"

echo "Created $OUT"
