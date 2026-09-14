#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
artifact="${1:-$script_dir/amd64.emacs30.1_26.04.tar.gz}"
artifact="$(readlink -f "$artifact")"
expected_version="$(<"$script_dir/glibc.version")"
allowlist="$script_dir/glibc-dev.allow.list"

[[ $EUID -eq 0 ]] || {
  echo "Run as root: this package extracts at /" >&2
  exit 1
}
[[ -f "$artifact" ]]
[[ -f "$allowlist" ]]

glibc_packages=(
  libc6
  libc-bin
  libc-gconv-modules-extra
  libc6-dev
  libc-dev-bin
)

for package in "${glibc_packages[@]}"; do
  actual="$(dpkg-query -W -f='${Version}' "$package")"
  [[ "$actual" == "$expected_version" ]] || {
    echo "$package version $actual does not match required $expected_version" >&2
    exit 1
  }
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

LC_ALL=C tar tzf "$artifact" | sed 's#^\./##' | LC_ALL=C sort -u \
  > "$workdir/artifact.paths"

mapfile -t installed_glibc_packages < <(
  dpkg-query -W -f='${binary:Package}\t${source:Package}\n' |
    awk -F '\t' '$2 == "glibc" {print $1}'
)
dpkg-query -L "${installed_glibc_packages[@]}" |
  sed 's#^/##' | sed '/^$/d' | LC_ALL=C sort -u \
  > "$workdir/glibc-owned.paths"

LC_ALL=C comm -12 "$workdir/artifact.paths" "$workdir/glibc-owned.paths" \
  > "$workdir/glibc-overlap.paths"
LC_ALL=C sort -u "$allowlist" > "$workdir/glibc-allowed.paths"
diff -u "$workdir/glibc-allowed.paths" "$workdir/glibc-overlap.paths"

if grep -Eq '(^|/)(libc\.so\.6|libm\.so\.6|ld-linux-x86-64\.so\.2)$' \
    "$workdir/artifact.paths"; then
  echo "Artifact contains core glibc runtime files" >&2
  exit 1
fi

while IFS= read -r path; do
  system_hash="$(sha256sum "/$path" | awk '{print $1}')"
  archive_hash="$(tar xOf "$artifact" "$path" | sha256sum | awk '{print $1}')"
  [[ "$system_hash" == "$archive_hash" ]] || {
    echo "Artifact $path differs from the installed glibc file" >&2
    exit 1
  }
done < "$workdir/glibc-allowed.paths"

mapfile -t protected_paths < <(
  sed 's#^#/#' "$workdir/glibc-allowed.paths"
  printf '%s\n' \
    /lib/x86_64-linux-gnu/libc.so.6 \
    /lib/x86_64-linux-gnu/libm.so.6 \
    /lib64/ld-linux-x86-64.so.2
)
before="$(sha256sum "${protected_paths[@]}")"
tar xzf "$artifact" -C /
ldconfig
after="$(sha256sum "${protected_paths[@]}")"
[[ "$before" == "$after" ]]

echo "EMACS_26_04_INSTALL_OK glibc=$expected_version"
