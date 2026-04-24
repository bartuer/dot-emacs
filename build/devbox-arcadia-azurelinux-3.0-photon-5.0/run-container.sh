#!/bin/sh
# Convenience wrapper to start an arcadia devcontainer with:
#   - persistent /root/.copilot bound to $HOME/.copilot-arcadia on the host
#     (so ghcp CLI sessions, checkpoints, plans and auth survive docker rm)
#   - host .ssh mounted read-only for git + reverse tunnel
#
# LLM endpoints are hard-coded in /root/.bashrc to point at
# http://localhost:11434 (Ollama) and pick up anything you pass via
# `-e OPENAI_BASE_URL=...` etc. — no host-side plumbing required.
#
# This script is intentionally host-side only — it is NOT shipped inside
# the dev.base tarball. Kept here so it lives next to the Dockerfile that
# defines the contract.
#
# Usage:
#   ./run-container.sh [container-name [extra docker args...]]
set -eu

NAME="${1:-arcadia}"
shift || true

IMAGE="${IMAGE:-mcr.microsoft.com/officepy/codeexecutionjupyterext1:dev.base.arcadia}"
COPILOT_HOST_DIR="${COPILOT_HOST_DIR:-$HOME/.copilot-arcadia}"

mkdir -p "$COPILOT_HOST_DIR"
chmod 700 "$COPILOT_HOST_DIR"

ssh_mount=""
if [ -d "$HOME/.ssh" ]; then
    ssh_mount="-v $HOME/.ssh:/root/.ssh:ro"
fi

exec docker run -d \
    --name "$NAME" \
    -v "$COPILOT_HOST_DIR:/root/.copilot" \
    $ssh_mount \
    "$@" \
    "$IMAGE"
