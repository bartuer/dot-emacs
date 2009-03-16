(defun bartuer-elisp-load ()
  "added when edit elisp file"
  (define-key emacs-lisp-mode-map "\M-i" 'PC-lisp-complete-symbol))