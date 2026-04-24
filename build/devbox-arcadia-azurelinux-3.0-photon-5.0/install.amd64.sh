# Arcadia install script (example)
# Extract tarballs into system root.
#
# Usage:
#   sudo ./install.amd64.sh

set -e

tar zxf amd64.arcadia.dev.base.azl3.0.tar.gz -C /
tar zxf amd64.arcadia.emacs30.1_azl3.0.tar.gz -C /

# Refresh the dynamic linker cache so /usr/local/lib/{libtree-sitter,
# libvterm}.so.* are discoverable without relying on LD_LIBRARY_PATH.
# Without this a fresh `emacs` invocation fails with
# "libtree-sitter.so.0: cannot open shared object file".
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi

# Copilot CLI writes sessions, checkpoints, plans, auth, and its
# vendored node pkg into /root/.copilot.  Make sure the dir exists
# with tight perms so a fresh container doesn't fail the first run.
# If the caller bind-mounted a host path onto /root/.copilot, this
# is a no-op; otherwise it's created inside the container layer and
# data will NOT survive `docker rm`.
mkdir -p /root/.copilot
chmod 700 /root/.copilot
if command -v mountpoint >/dev/null 2>&1; then
  if ! mountpoint -q /root/.copilot; then
    printf '[warn] /root/.copilot is NOT a bind-mount; Copilot CLI session\n' >&2
    printf '       data will be lost when this container is removed.\n' >&2
    printf '       Run the container with: -v <HOST_DIR>:/root/.copilot\n' >&2
  fi
fi

# Keep consistent with existing pattern
source ~/.bashrc
