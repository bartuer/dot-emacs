#!/bin/bash
# Build arm64.dev.base.24.04.tar.gz from the base-only image, computing a
# VALIDATED file list inside the image (every entry must exist), then tarring.
#
# The list = ssh + git package files + git's HTTPS runtime ldd closure
# (libcurl-gnutls, gnutls, krb5, nghttp2, …, so `git clone https://…` works
# on-target for tree-sitter grammar install) + the ca-certificates bundle
# (/etc/ssl/certs + /usr/share/ca-certificates for HTTPS cert verification)
# + shell/ssh config files.
#
# Prereq: build the image first —
#   docker buildx build --platform linux/arm64 -f Dockerfile.base . \
#     -t caapi/arm64.devbox.base:24.04
set -e
IMG=caapi/arm64.devbox.base:24.04
OUT=arm64.dev.base.24.04.tar.gz

docker run --rm --platform linux/arm64 --entrypoint bash -v "${PWD}":/out "$IMG" -c '
set -e
{
  # ssh package files (skip man/doc)
  apt list --installed 2>/dev/null | grep -E "ssh|libwrap0" | awk -F/ "{print \$1}" \
    | xargs dpkg -L 2>/dev/null
  # git package files (skip doc)
  apt list --installed 2>/dev/null | grep git | awk -F/ "{print \$1}" \
    | xargs dpkg -L 2>/dev/null
  # git HTTPS transport runtime closure (follow symlink chains)
  ldd /usr/lib/git-core/git-remote-https 2>/dev/null | awk "{print \$3}" | grep "^/" \
    | while read f; do echo "$f"; while [ -L "$f" ]; do t=$(readlink -f "$f"); echo "$t"; f="$t"; done; done
  # ca-certificates bundle + source certs + symlinks
  find /etc/ssl/certs -type f -o -type l
  find /usr/share/ca-certificates -type f
  # ssh config dir
  find /etc/ssh
  # explicit extras the container writes
  printf "%s\n" /etc/passwd /etc/timezone \
    /root/.ssh/config /root/.ssh/authorized_keys /root/.gitconfig /root/.bashrc \
    /bin/entry /root/local/bin/install.arm64.sh
} | grep -vE "/(share/doc|share/man|/man[0-9])/" \
  | sed "s#^/##" | sort -u > /tmp/list.raw

# keep only entries that actually exist (files or symlinks), drop dirs
: > /tmp/list.final
while read -r p; do
  [ -z "$p" ] && continue
  if [ -f "/$p" ] || [ -L "/$p" ]; then echo "$p" >> /tmp/list.final; fi
done < /tmp/list.raw
sort -u /tmp/list.final -o /tmp/list.final

echo "list entries: $(wc -l < /tmp/list.final)"
echo "x86_64 in list: $(grep -c x86_64 /tmp/list.final || true)"
tar -C / -czf /out/'"$OUT"' -T /tmp/list.final
echo "packed."
'
echo "=== on host ==="
ls -lh "$OUT"
echo -n "x86_64 leak: "; tar tzf "$OUT" | grep -i x86_64 && echo "LEAK!" || echo "CLEAN"
echo -n "has git-remote-https + libcurl-gnutls + ca bundle: "
tar tzf "$OUT" | grep -E 'git-core/git-remote-https$|libcurl-gnutls\.so|etc/ssl/certs/ca-certificates.crt$' | tr '\n' ' '; echo
