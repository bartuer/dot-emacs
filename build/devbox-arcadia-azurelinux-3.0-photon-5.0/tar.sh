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

tar czf "$OUT" -C / -T "$FLIST"
rm -f "$FLIST"

echo "Created $OUT"
