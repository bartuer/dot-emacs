(defun show-graph ()
  "show ragel defined state machine in graphviz"
  (interactive)
  (shell-command (concat "rlv " (file-name-nondirectory (buffer-file-name))))
  )

(defun compile-ruby ()
  "compile to ruby and run it"
  (interactive)
  (shell-command (concat "rlr " (file-name-nondirectory (buffer-file-name))))
  )

(defun compile-xml ()
  "compile to xml"
  (interactive)
  (let ((name (file-name-nondirectory (buffer-file-name))))
    (shell-command (concat "rlx " name))
    (find-file-other-window (concat (buffer-file-name) ".xml"))
    )
  )

(define-derived-mode ragel-mode
  c-mode "Ragel"
  "Major mode for ragel+ruby.
            \\{ragel-mode-map}"
  )

(define-key ragel-mode-map
  "\C-j" 'compile)

(provide 'ragel-mode)