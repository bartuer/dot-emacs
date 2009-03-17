(defun bartuer-html-load ()
  "html mode modification"
  (define-key sgml-mode-map "\C-\M-f" 'sgml-skip-tag-forward)
  (define-key sgml-mode-map "\C-\M-b" 'sgmll-skip-tag-backward)
  (define-key sgml-mode-map "\C-\M-k" 'sgmll-delete-tag)
  (define-key sgml-mode-map "\C-\M-v" 'sgml-validate)
  (define-key sgml-mode-map "\C-c\C-ct" 'sgmll-close-tag))