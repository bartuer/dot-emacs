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
  # ssh CLIENT/host files ONLY — never the SERVER identity/config, which would
  # clobber a live host on `tar -C /` (see plan 08). Exclude sshd_config,
  # ssh_config, every ssh_host_* key, and moduli (all host-owned/regenerable).
  find /etc/ssh -type f ! -name "sshd_config" ! -name "ssh_config" \
    ! -name "ssh_host_*" ! -name "moduli"
  # explicit extras the container writes.
  # NOTE: authorized_keys is shipped to a STAGING path (authorized_keys.devbox)
  # so `tar -C /` cannot overwrite an existing host authorized_keys;
  # install.arm64.sh appends+dedups it. See plan 08 "append-safe root/.ssh".
  # DROPPED (host clobber risk, plan 08):
  #   - /etc/passwd — would overwrite host accounts.
  #   - /root/.ssh/config — the container single-block Host github (with an
  #     in-container ProxyCommand) would obliterate the operator rich host
  #     ~/.ssh/config. The container still gets config via the IMAGE
  #     (COPY config /root/.ssh/config in Dockerfile.base), not the tarball.
  printf "%s\n" /etc/timezone \
    /root/.ssh/authorized_keys.devbox /root/.gitconfig /root/.bashrc \
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

# defence-in-depth: even if a future dpkg -L re-introduces server identity
# paths, strip them here so the tarball can NEVER clobber host SSH. Keep
# root/.ssh/authorized_keys.devbox (staged); DROP etc/passwd and the live
# root/.ssh/config (host clobber risk — see printf note above).
grep -vE "^etc/ssh/(sshd_config|ssh_config|moduli)$" /tmp/list.final \
  | grep -vE "^etc/ssh/ssh_host_" \
  | grep -vE "^etc/pam\.d/sshd$" \
  | grep -vE "^etc/passwd$" \
  | grep -vE "^root/\.ssh/config$" > /tmp/list.safe
mv /tmp/list.safe /tmp/list.final

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

# host-safety gate: the tarball must NEVER carry server SSH identity/config.
echo -n "host-SSH clobber check: "
if tar tzf "$OUT" | grep -Eq '^(\./)?(etc/passwd|etc/ssh/(sshd_config|ssh_config|moduli)|etc/ssh/ssh_host_|etc/pam\.d/sshd|root/\.ssh/(authorized_keys|config))$'; then
  echo "FAIL — host-clobber files leaked:"; tar tzf "$OUT" | grep -E '^(\./)?(etc/passwd|etc/ssh/(sshd_config|ssh_config|moduli)|etc/ssh/ssh_host_|etc/pam\.d/sshd|root/\.ssh/(authorized_keys|config))$'
  exit 1
else
  echo "CLEAN (no passwd/sshd_config/ssh_config/moduli/ssh_host_*/pam.d/sshd/root .ssh authorized_keys|config)"
fi
echo -n "authorized_keys staged (not clobbering): "
tar tzf "$OUT" | grep -E '^(\./)?root/\.ssh/authorized_keys(\.devbox)?$' | tr '\n' ' '; echo
