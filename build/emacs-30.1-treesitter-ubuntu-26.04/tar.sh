#!/bin/bash
set -euo pipefail

# :trap: amd64.tar.list line 1 is the BARE DIRECTORY `root/local`, and
# `tar -T` expands a directory RECURSIVELY. That one line silently pulled in
# the whole build tree -- root/local/src/emacs-30.1 (393 MiB, 8149 files:
# .el/.elc sources, .o objects, temacs, .pdmp dumps, texinfo) plus the
# 79 MiB emacs-30.1.tar.gz it was unpacked from. 472 MiB of dead weight,
# none of it needed at run time: `make install` already copied the real
# binaries to root/local/{bin,lib,libexec,share}.
#
# MEASURED 2026-09-15: that is the ENTIRE 24.04-vs-26.04 gap --
#   26.04 uncompressed 926 MiB - 472 MiB src = 454 MiB vs 24.04's 467 MiB,
#   i.e. 0.97x after the fix where it was 1.98x before.
# 24.04 ships ZERO root/local/src files and works fine, which is what makes
# excluding it safe.
#
# :trap: do NOT "fix" this by deleting the bare `root/local` line from the
# manifest -- it is also the ONLY thing pulling in 93 share/emacs,
# 40 lib/emacs and 4 libexec/emacs runtime files that no explicit entry
# covers (12793 paths land under root/local, only 4608 are listed). Exclude
# the src subtree, not the root.
#
# Same hazard, same file: root/etc/el is a bare dir too, which is why
# root/etc/el/build is already excluded below.
cd /
tar czf /opt/amd64.emacs30.1_26.04.tar.gz \
  --exclude="root/etc/el/.git" \
  --exclude="root/etc/el/build" \
  --exclude="root/local/src" \
  -T /opt/amd64.tar.list