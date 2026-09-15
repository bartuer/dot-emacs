#!/usr/bin/env bash
# Build the calamine READ engine ("silo") from source, on a bare box.
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# The xlsx read path (46% of the corpus) needs cells + formulas + charts in
# ONE pass.  Nothing off-the-shelf provides it:
#
#   * the dev image does NOT ship calamine.  Verified 4 ways against
#     ~/.copilot/amd64.arcadia.dev.base.azl3.0.tar.gz (10,723 entries,
#     250 MB extracted): filename grep = 0, `strings` over all 3 custom
#     binaries = 0, exhaustive `grep -ria` over the extracted image = 0
#     files, and no python xlsx reader either.  The image's 3 custom
#     binaries are exactly: parallel, rg, xlsx2csv.
#   * `usr/local/bin/xlsx2csv` is NOT calamine -- it is built on the
#     `ooxml-0.2.8` crate.  It fails 25/40 SpreadsheetBench inputs with
#     "unimplemented format support", emits ZERO formulas (silo finds
#     36,344 in 1_59932_answer.xlsx), and leaks raw `dbg!` lines from
#     ooxml-0.2.8/src/.../mod.rs:192 into STDOUT, which would corrupt any
#     CSV artifact generated from it.
#   * crates.io calamine does NOT have chart reading.  `src/chart.rs`,
#     `src/style.rs` and `src/conditional_format.rs` do not exist on
#     origin/master; they arrive only via PR #683.
#
# So the engine must be BUILT.  This script is the whole recipe.
#
# ⚠ PIN DISCIPLINE (do NOT fork, TRACK)
# PR #683 is UNMERGED upstream.  We pin it by SHA and build it as-is.
# When it merges, drop the pull-ref fetch and move to a released tag --
# do not accumulate local patches on top, or the pin becomes a fork.
#
# ⚠ This is a DEV-BOX provisioning script.  It lives in fix.archive/ and
# builds OUTSIDE the checkout ($PREFIX defaults to /workspace/research),
# so nothing here enters src/ (G1) and no /app/officepy path is used (G4).
#
# Usage:
#   bash build-calamine-silo.sh            # build into /workspace/research
#   PREFIX=/some/dir bash build-calamine-silo.sh
#   bash build-calamine-silo.sh --verify   # only re-run the smoke check
#
set -euo pipefail

PREFIX="${PREFIX:-/workspace/research}"
CALAMINE_REPO="https://github.com/tafia/calamine.git"
# PR #683 "feat(xlsx): implement chart reading" -- head of refs/pull/683/head.
# Base at time of pinning: origin/master 263762c8e98e.  calamine 0.36.0.
CALAMINE_SHA="d69ae3cda8725fd864269ecffe458e022050a23b"
CALAMINE_DIR="$PREFIX/calamine"
SILO_DIR="$PREFIX/silo"

log() { printf '\n=== %s\n' "$*"; }

# ---------------------------------------------------------------- toolchain
log "toolchain"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not found -- installing rustup (needs network)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"
fi
cargo --version
rustc --version

if [ "${1:-}" = "--verify" ]; then SKIP_BUILD=1; else SKIP_BUILD=0; fi

if [ "$SKIP_BUILD" = "0" ]; then
    # ------------------------------------------------------------- clone
    # Fetch the PR ref explicitly: the SHA is NOT on any branch head, it is
    # only reachable via refs/pull/683/head.  A plain `git clone` will NOT
    # contain it.
    log "clone calamine @ PR#683 -> $CALAMINE_DIR"
    mkdir -p "$PREFIX"
    if [ ! -d "$CALAMINE_DIR/.git" ]; then
        git clone --no-checkout "$CALAMINE_REPO" "$CALAMINE_DIR"
    fi
    cd "$CALAMINE_DIR"
    git fetch --force origin "refs/pull/683/head:pr683"
    git checkout --force pr683

    # Fail loudly if the pin drifted -- a silent different SHA means silently
    # different chart numbers downstream.
    GOT="$(git rev-parse HEAD)"
    if [ "$GOT" != "$CALAMINE_SHA" ]; then
        echo "PIN MISMATCH: expected $CALAMINE_SHA got $GOT" >&2
        exit 1
    fi
    echo "pinned OK: $GOT"
    test -f src/chart.rs || { echo "src/chart.rs missing -- wrong ref" >&2; exit 1; }

    # -------------------------------------------------------------- silo
    log "write silo crate -> $SILO_DIR"
    mkdir -p "$SILO_DIR/src"
    cat > "$SILO_DIR/Cargo.toml" <<EOF
[package]
name="silo"
version="0.1.0"
edition="2021"
[dependencies]
calamine={path="$CALAMINE_DIR"}
[profile.release]
opt-level=3
lto=true
codegen-units=1
EOF
    if [ ! -f "$SILO_DIR/src/main.rs" ]; then
        echo "NOTE: $SILO_DIR/src/main.rs absent -- restore it from the repo"
        echo "      (the emitter body is source, not provisioning)."
        exit 1
    fi

    log "cargo build --release  (~26 s clean)"
    cd "$SILO_DIR"
    cargo build --release
fi

# ------------------------------------------------------------------ verify
log "verify"
BIN="$SILO_DIR/target/release/silo"
test -x "$BIN" || { echo "missing binary $BIN" >&2; exit 1; }
ls -la "$BIN"

# Smoke it on a real workbook and assert non-zero signal on ALL THREE axes.
# An exit code is not a measurement -- check the numbers.
SMOKE="${SMOKE:-/workspace/datasets/SpreadsheetBench/answers/1_59932_answer.xlsx}"
if [ -f "$SMOKE" ]; then
    OUT="$("$BIN" "$SMOKE")"
    echo "$OUT"
    echo "$OUT" | grep -q '"formulas":[1-9]' || { echo "FAIL: zero formulas" >&2; exit 1; }
    echo "$OUT" | grep -q '"charts":[1-9]'   || { echo "FAIL: zero charts"   >&2; exit 1; }
    echo "$OUT" | grep -q '"cells":[1-9]'    || { echo "FAIL: zero cells"    >&2; exit 1; }
    echo "OK: cells + formulas + charts all non-zero in ONE pass"
    echo "    (expected for this file: cells 36547 / formulas 36344 / charts 14)"
else
    echo "SKIP smoke: $SMOKE not present"
fi

log "done -- add to PATH:"
echo "    export PATH=\"$SILO_DIR/target/release:\$PATH\""
