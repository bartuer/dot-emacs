#!/bin/sh
# Upload the Arcadia dev.base tarball to a GitHub release as an artifact.
#
# Auth: reuses the existing github.com credential from the git credential
# helper (macOS osxkeychain) via `git credential fill`. No token is stored in
# this repo (Hard Rule #6). Falls back to $GITHUB_TOKEN if set.
#
# Usage:
#   ./upload-release.sh <tag> [asset.tar.gz]
# Examples:
#   ./upload-release.sh devbase-azl3.0-amd64            # default tarball below
#   ./upload-release.sh devbase-azl3.0-amd64 path/to/x.tar.gz
#
# The release is created if it does not exist, then the asset is uploaded
# (an existing asset with the same name is replaced).

set -eu

REPO="bartuer/dot-emacs"
API="https://api.github.com"
UPLOADS="https://uploads.github.com"

TAG=${1:?usage: $0 <tag> [asset.tar.gz]}
ASSET=${2:-"$(dirname "$0")/amd64.arcadia.dev.base.azl3.0.tar.gz"}
NAME=$(basename "$ASSET")

[ -f "$ASSET" ] || { echo "asset not found: $ASSET" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }

# --- Resolve a github.com token -------------------------------------------------
if [ -n "${GITHUB_TOKEN:-}" ]; then
  TOKEN=$GITHUB_TOKEN
else
  TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' \
    | git credential fill 2>/dev/null \
    | sed -n 's/^password=//p')
fi
[ -n "$TOKEN" ] || { echo "no github.com token (set GITHUB_TOKEN or add a git credential)" >&2; exit 1; }

auth() { curl -fsS -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

# --- Get or create the release --------------------------------------------------
RELEASE_JSON=$(auth "$API/repos/$REPO/releases/tags/$TAG" 2>/dev/null || true)
RELEASE_ID=$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"id": *\([0-9]*\).*/\1/p' | head -1)

if [ -z "$RELEASE_ID" ]; then
  echo "creating release $TAG ..."
  RELEASE_JSON=$(auth -X POST "$API/repos/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"draft\":false,\"prerelease\":true}")
  RELEASE_ID=$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"id": *\([0-9]*\).*/\1/p' | head -1)
fi
[ -n "$RELEASE_ID" ] || { echo "could not resolve release id for tag $TAG" >&2; exit 1; }
echo "release id: $RELEASE_ID"

# --- Replace existing asset with the same name ----------------------------------
EXISTING=$(auth "$API/repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" \
  | sed -n "s/.*{\"url\":[^}]*\"id\": *\([0-9]*\)[^}]*\"name\": *\"$NAME\".*/\1/p" | head -1)
if [ -n "$EXISTING" ]; then
  echo "deleting existing asset $NAME (id $EXISTING) ..."
  auth -X DELETE "$API/repos/$REPO/releases/assets/$EXISTING" >/dev/null
fi

# --- Upload ---------------------------------------------------------------------
echo "uploading $NAME ($(du -h "$ASSET" | cut -f1)) ..."
auth -X POST "$UPLOADS/repos/$REPO/releases/$RELEASE_ID/assets?name=$NAME" \
  -H "Content-Type: application/gzip" \
  --data-binary @"$ASSET" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/download: \1/p'

echo "done."
