#!/bin/bash
set -euo pipefail

artifact="${1:-amd64.emacs30.1_26.04.tar.gz}"
artifact="$(readlink -f "$artifact")"
[[ -f "$artifact" ]]

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
expected_glibc_version="$(<"$script_dir/glibc.version")"
expected_gcc_jit_version="$(<"$script_dir/libgccjit.version")"
allowlist="$script_dir/glibc-dev.allow.list"
glibc_packages=(
  libc6
  libc-bin
  libc-gconv-modules-extra
  libc6-dev
  libc-dev-bin
)

for package in "${glibc_packages[@]}"; do
  host_version="$(dpkg-query -W -f='${Version}' "$package")"
  [[ "$host_version" == "$expected_glibc_version" ]] || {
    echo "Host $package version $host_version != $expected_glibc_version" >&2
    exit 1
  }
  image_version="$(
    docker run --rm --entrypoint dpkg-query \
      caapi/amd64.emacs30.1:26.04 -W -f='${Version}' "$package"
  )"
  [[ "$image_version" == "$expected_glibc_version" ]] || {
    echo "Image $package version $image_version != $expected_glibc_version" >&2
    exit 1
  }
done

for package in gcc-14 libgccjit0 libgccjit-14-dev; do
  image_version="$(
    docker run --rm --entrypoint dpkg-query \
      caapi/amd64.emacs30.1:26.04 -W -f='${Version}' "$package"
  )"
  [[ "$image_version" == "$expected_gcc_jit_version" ]] || {
    echo "Image $package version $image_version != $expected_gcc_jit_version" >&2
    exit 1
  }
done

docker run --rm -i --platform linux/amd64 \
  -e EXPECTED_GLIBC_VERSION="$expected_glibc_version" \
  -v "$artifact:/opt/emacs.tar.gz:ro" \
  -v "$allowlist:/opt/glibc-dev.allow.list:ro" \
  ubuntu:26.04 bash -s <<'CONTAINER'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  file \
  "libc6=$EXPECTED_GLIBC_VERSION" \
  "libc-bin=$EXPECTED_GLIBC_VERSION" \
  "libc-gconv-modules-extra=$EXPECTED_GLIBC_VERSION" \
  "libc6-dev=$EXPECTED_GLIBC_VERSION" \
  "libc-dev-bin=$EXPECTED_GLIBC_VERSION" >/dev/null

for package in \
  libc6 libc-bin libc-gconv-modules-extra libc6-dev libc-dev-bin; do
  [[ "$(dpkg-query -W -f='${Version}' "$package")" == "$EXPECTED_GLIBC_VERSION" ]]
done

LC_ALL=C tar tzf /opt/emacs.tar.gz | sed 's#^\./##' |
  LC_ALL=C sort -u > /tmp/artifact.paths
if grep -q '^root/etc/el/build/' /tmp/artifact.paths; then
  echo "Artifact contains embedded builder history" >&2
  exit 1
fi
mapfile -t glibc_packages < <(
  dpkg-query -W -f='${binary:Package}\t${source:Package}\n' |
    awk -F '\t' '$2 == "glibc" {print $1}'
)
dpkg-query -L "${glibc_packages[@]}" |
  sed 's#^/##' | sed '/^$/d' | LC_ALL=C sort -u \
  > /tmp/glibc-owned.paths
LC_ALL=C comm -12 /tmp/artifact.paths /tmp/glibc-owned.paths \
  > /tmp/glibc-overlap.paths
LC_ALL=C sort -u /opt/glibc-dev.allow.list > /tmp/glibc-allowed.paths
diff -u /tmp/glibc-allowed.paths /tmp/glibc-overlap.paths

while IFS= read -r path; do
  system_hash="$(sha256sum "/$path" | awk '{print $1}')"
  archive_hash="$(tar xOf /opt/emacs.tar.gz "$path" | sha256sum | awk '{print $1}')"
  [[ "$system_hash" == "$archive_hash" ]]
done < /tmp/glibc-allowed.paths

mapfile -t core < <(
  for path in \
    /lib/x86_64-linux-gnu/libc.so.6 \
    /lib/x86_64-linux-gnu/libm.so.6 \
    /lib64/ld-linux-x86-64.so.2; do
    readlink -f "$path"
  done | awk '!seen[$0]++'
)
before="$(sha256sum "${core[@]}")"
glibc_dev_before="$(sha256sum $(sed 's#^#/#' /tmp/glibc-allowed.paths))"

if grep -Eq '(^|/)(libc\.so\.6|libm\.so\.6|ld-linux-x86-64\.so\.2)$' \
    /tmp/artifact.paths; then
  echo "Artifact contains core glibc files" >&2
  exit 1
fi

tar xzf /opt/emacs.tar.gz -C /
ldconfig
after="$(sha256sum "${core[@]}")"
[[ "$before" == "$after" ]]
glibc_dev_after="$(sha256sum $(sed 's#^#/#' /tmp/glibc-allowed.paths))"
[[ "$glibc_dev_before" == "$glibc_dev_after" ]]

ldd --version | head -1 | tee /tmp/glibc.version
grep -q ' 2\.43' /tmp/glibc.version

emacs_bin="$(readlink -f /root/local/bin/emacs)"
ldd "$emacs_bin" | tee /tmp/emacs.ldd
! grep -q 'not found' /tmp/emacs.ldd
file "$emacs_bin" /root/etc/el/vendor/vterm/vterm-module.so |
  tee /tmp/emacs.files
[[ "$(grep -c 'x86-64' /tmp/emacs.files)" -eq 2 ]]
! grep -qi 'aarch64' /tmp/emacs.files

file \
  /usr/local/lib/libtree-sitter.so.0.24 \
  /root/etc/el/vendor/tsc/tsc-dyn.so |
  tee /tmp/tree-sitter.files
[[ "$(grep -c 'x86-64' /tmp/tree-sitter.files)" -eq 2 ]]
! grep -qi 'aarch64' /tmp/tree-sitter.files

grep -E '\.so($|\.)' /tmp/artifact.paths |
  while IFS= read -r path; do
    [[ -e "/$path" || -L "/$path" ]] && file "/$path"
  done > /tmp/artifact-shared-object.files
! grep -qi 'ARM aarch64' /tmp/artifact-shared-object.files

ldd /usr/bin/jq | tee /tmp/jq.ldd
! grep -q 'not found' /tmp/jq.ldd
jq --version

/root/local/bin/emacs --version | head -1
/root/local/bin/emacs -Q --batch \
  --eval '(princ emacs-version)' | grep -qx '30.1'
/root/local/bin/emacs -Q --batch \
  --eval '(princ (if (native-comp-available-p) "NATIVE_COMP_OK" "NATIVE_COMP_MISSING"))' |
  grep -qx 'NATIVE_COMP_OK'
cat > /tmp/plan09-jit-smoke.el <<'ELISP'
;;; -*- lexical-binding: t; -*-
(defun plan09-jit-square (x) (* x x))
(provide 'plan09-jit-smoke)
ELISP
jit_eln="$(
  /root/local/bin/emacs -Q --batch \
    --eval '(princ (native-compile "/tmp/plan09-jit-smoke.el"))'
)"
[[ -f "$jit_eln" ]]
file "$jit_eln" | grep -q 'x86-64'
/root/local/bin/emacs -Q --batch \
  --eval "(progn (load \"$jit_eln\" nil t) (princ (plan09-jit-square 9)))" |
  grep -qx '81'
/root/local/bin/emacs -Q --batch \
  --eval '(princ (if (treesit-available-p) "TREESIT_OK" "TREESIT_MISSING"))' |
  grep -qx 'TREESIT_OK'
/root/local/bin/emacs -Q --batch \
  --eval '(add-to-list (quote load-path) "/root/etc/el/vendor/vterm")' \
  --eval '(require (quote vterm))' \
  --eval '(princ "VTERM_OK")' | grep -qx 'VTERM_OK'

bash -ic '
  test "$COPILOT_PROVIDER_TYPE" = "openai"
  test "$COPILOT_PROVIDER_BASE_URL" = "http://127.0.0.1:11434/v1"
  test "$COPILOT_PROVIDER_API_KEY" = "ollama"
  test -z "${COPILOT_MODEL+x}"
  command -v curl
  command -v jq
  test "$(type -t h)" = "function"
  alias ghe | grep -F -- "--model gpt-5.6-sol"
  alias ghe | grep -F -- "--effort high"
  alias ghe | grep -F -- "--context long_context"
'

echo "GLIBC_EXACT_MATCH_OK version=$EXPECTED_GLIBC_VERSION overlap=$(wc -l < /tmp/glibc-overlap.paths)"
echo EMACS_26_04_VERIFY_OK
CONTAINER
