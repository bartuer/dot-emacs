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
: > "$candidate"
: > "$skipped"

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

printf 'MANIFEST_OK entries=%s skipped_stale=%s\n' \
  "$(wc -l < "$output")" \
  "$(wc -l < "$skipped")"
CONTAINER
