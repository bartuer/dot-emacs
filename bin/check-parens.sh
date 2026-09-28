#!/usr/bin/env bash
# check-parens.sh [FILE.el ...] -- batch check-parens; prints BAD <file>, rc=1 if any.
[ $# -eq 0 ] && { cd "$(dirname "$0")/.." && set -- bartuer-*.el; }
rc=0
for f in "$@"; do
  emacs --batch -Q --eval "(progn (insert-file-contents \"$f\") (emacs-lisp-mode)
    (condition-case nil (check-parens) (error (kill-emacs 1))))" >/dev/null 2>&1 \
    || { echo "BAD $f"; rc=1; }
done
exit $rc
