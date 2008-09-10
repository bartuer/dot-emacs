(defun bartuer-c-common ()
  "for c and C++ language
"
  (c-subword-mode 1)
  ;; is it possible to guess the code style ?
  ;; now I using the c-file-style in file varible
  (define-key c-mode-base-map "\C-m" 'c-context-line-break)
  (define-key makefile-mode-map "\C-j" 'recompile)
  (define-key c-mode-base-map "\C-j" 'recompile))

