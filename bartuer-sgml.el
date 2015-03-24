(defun bartuer-sgml-load ()
  "html mode modification"
  (flyspell-mode-off)
  (emmet-mode)
  (setq indent-region-function nil)
  (define-key sgml-mode-map "\C-\M-f" 'sgml-skip-tag-forward)
  (define-key sgml-mode-map "\C-\M-b" 'sgml-skip-tag-backward)
  (define-key sgml-mode-map "\C-\M-k" 'sgml-delete-tag)
  (define-key sgml-mode-map "\C-\M-v" 'sgml-validate)
  (define-key sgml-mode-map "\C-c\C-ct" 'sgml-close-tag))

