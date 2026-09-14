#!/bin/bash
set -euo pipefail

artifact="${1:-amd64.emacs30.1_26.04.tar.gz}"
artifact="$(readlink -f "$artifact")"
[[ -f "$artifact" ]]

docker run --rm -i --platform linux/amd64 \
  -v "$artifact:/opt/emacs.tar.gz:ro" \
  ubuntu:26.04 bash -s <<'CONTAINER'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends file >/dev/null

mapfile -t core < <(
  for path in \
    /lib/x86_64-linux-gnu/libc.so.6 \
    /lib/x86_64-linux-gnu/libm.so.6 \
    /lib64/ld-linux-x86-64.so.2; do
    readlink -f "$path"
  done | awk '!seen[$0]++'
)
before="$(sha256sum "${core[@]}")"

if tar tzf /opt/emacs.tar.gz |
    grep -Eq '(^|/)(libc\.so\.6|libm\.so\.6|ld-linux-x86-64\.so\.2)$'; then
  echo "Artifact contains core glibc files" >&2
  exit 1
fi

tar xzf /opt/emacs.tar.gz -C /
ldconfig
after="$(sha256sum "${core[@]}")"
[[ "$before" == "$after" ]]

ldd --version | head -1 | tee /tmp/glibc.version
grep -q ' 2\.43' /tmp/glibc.version

emacs_bin="$(readlink -f /root/local/bin/emacs)"
ldd "$emacs_bin" | tee /tmp/emacs.ldd
! grep -q 'not found' /tmp/emacs.ldd
file "$emacs_bin" /root/etc/el/vendor/vterm/vterm-module.so |
  tee /tmp/emacs.files
[[ "$(grep -c 'x86-64' /tmp/emacs.files)" -eq 2 ]]
! grep -qi 'aarch64' /tmp/emacs.files

ldd /usr/bin/jq | tee /tmp/jq.ldd
! grep -q 'not found' /tmp/jq.ldd
jq --version

/root/local/bin/emacs --version | head -1
/root/local/bin/emacs -Q --batch \
  --eval '(princ emacs-version)' | grep -qx '30.1'
/root/local/bin/emacs -Q --batch \
  --eval '(princ (if (native-comp-available-p) "NATIVE_COMP_OK" "NATIVE_COMP_MISSING"))' |
  grep -qx 'NATIVE_COMP_OK'
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

echo EMACS_26_04_VERIFY_OK
CONTAINER
