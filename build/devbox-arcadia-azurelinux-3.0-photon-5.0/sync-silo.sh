#!/bin/sh
# Sync the silo source from its (actively developed) repo into this build
# context, so the Docker build bakes the CURRENT snapshot, not a stale copy.
# The silo repo lives outside this repo, so it must be copied at build time.
set -eu
SRC=${SILO_SRC:-/Users/bazhou/local/src/silo}
DST=$(dirname "$0")/silo
mkdir -p "$DST"
cp "$SRC/src/main.rs" "$DST/main.rs"
cp "$SRC/Cargo.toml"  "$DST/Cargo.toml"
# Cargo.lock is optional (present once the repo has built once).
[ -f "$SRC/Cargo.lock" ] && cp "$SRC/Cargo.lock" "$DST/Cargo.lock" || true
echo "synced silo from $SRC -> $DST"
