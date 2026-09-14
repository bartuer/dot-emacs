#!/bin/bash
set -euo pipefail

image="${IMAGE:-caapi/amd64.emacs30.1:26.04}"

docker run --rm -i --platform linux/amd64 \
  -v "${PWD}:/opt" "$image" bash -s <<'CONTAINER'
set -euo pipefail

template=/opt/amd64.tar.list.template
output=/opt/amd64.tar.list
candidate=/opt/amd64.tar.list.new
skipped=/opt/amd64.tar.list.skipped
glibc_owned=/tmp/glibc-owned.paths
glibc_allowed=/opt/glibc-dev.allow.list
glibc_overlap=/tmp/glibc-overlap.paths
sorted_output=/tmp/amd64.tar.list.sorted
sorted_allowed=/tmp/glibc-allowed.paths
expected_glibc_version="$(</opt/glibc.version)"
: > "$candidate"
: > "$skipped"

for package in \
  libc6 libc-bin libc-gconv-modules-extra libc6-dev libc-dev-bin; do
  actual_version="$(dpkg-query -W -f='${Version}' "$package")"
  [[ "$actual_version" == "$expected_glibc_version" ]] || {
    echo "$package version $actual_version != $expected_glibc_version" >&2
    exit 1
  }
done

mapfile -t glibc_packages < <(
  dpkg-query -W -f='${binary:Package}\t${source:Package}\n' |
    awk -F '\t' '$2 == "glibc" {print $1}'
)
dpkg-query -L "${glibc_packages[@]}" |
  sed 's#^/##' | sed '/^$/d' | LC_ALL=C sort -u > "$glibc_owned"
LC_ALL=C sort -u "$glibc_allowed" > "$sorted_allowed"

while IFS= read -r path; do
  grep -Fxq "$path" "$glibc_owned" || {
    echo "Allowed glibc development path is not package-owned: $path" >&2
    exit 1
  }
  [[ -e "/$path" || -L "/$path" ]] || {
    echo "Allowed glibc development path is missing: $path" >&2
    exit 1
  }
done < "$sorted_allowed"

for root in \
  root/local \
  root/etc/el \
  root/.emacs.el \
  root/.bashrc \
  usr/local/lib/libtree-sitter.so.0.24; do
  if [[ -e "/$root" || -L "/$root" ]]; then
    printf '%s\n' "$root" >> "$candidate"
  fi
done

while IFS= read -r raw || [[ -n "$raw" ]]; do
  path="${raw#/}"
  [[ -n "$path" ]] || continue
  base="${path##*/}"

  if [[ "$path" == root/etc/el/build ||
        "$path" == root/etc/el/build/* ]]; then
    printf '%s\n' "$path" >> "$skipped"
    continue
  fi

  if grep -Fxq "$path" "$glibc_owned" &&
      ! grep -Fxq "$path" "$sorted_allowed"; then
    printf '%s\n' "$path" >> "$skipped"
    continue
  fi

  case "$base" in
    libc.so.6|libm.so.6|ld-linux-x86-64.so.2)
      continue
      ;;
  esac

  if [[ -e "/$path" || -L "/$path" ]]; then
    printf '%s\n' "$path" >> "$candidate"
    continue
  fi

  if [[ "$path" == root/etc/el/* ]]; then
    continue
  fi

  if [[ "$base" == *.so.* ]]; then
    dir="/${path%/*}"
    stem="${base%%.so.*}"
    while IFS= read -r replacement; do
      printf '%s\n' "${replacement#/}" >> "$candidate"
    done < <(
      find "$dir" -maxdepth 1 \( -type f -o -type l \) \
        -name "${stem}.so*" -print 2>/dev/null | sort
    )
    continue
  fi

  printf '%s\n' "$path" >> "$skipped"
done < "$template"

awk '!seen[$0]++' "$candidate" > "$output"
rm -f "$candidate"

for required in \
  root/local \
  root/etc/el \
  root/.emacs.el \
  root/.bashrc \
  usr/local/lib/libtree-sitter.so.0.24; do
  grep -qx "$required" "$output" || {
    echo "Required manifest entry missing: $required" >&2
    exit 1
  }
done

if grep -Eq '(^|/)(libc\.so\.6|libm\.so\.6|ld-linux-x86-64\.so\.2)$' "$output"; then
  echo "Core glibc file leaked into manifest" >&2
  exit 1
fi

LC_ALL=C sort -u "$output" > "$sorted_output"
LC_ALL=C comm -12 "$sorted_output" "$glibc_owned" > "$glibc_overlap"
diff -u "$sorted_allowed" "$glibc_overlap"

printf 'MANIFEST_OK entries=%s skipped=%s glibc_allowed=%s\n' \
  "$(wc -l < "$output")" \
  "$(wc -l < "$skipped")" \
  "$(wc -l < "$glibc_overlap")"
CONTAINER
