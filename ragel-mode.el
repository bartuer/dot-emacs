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

(define-derived-mode ragel-mode
  ruby-mode "Ragel"
  "Major mode for ragel+ruby.
            \\{ragel-mode-map}"
  )

(define-key ragel-mode-map
  "\C-j" 'compile-ruby)

(define-key ragel-mode-map
  "\C-c\C-j" 'show-graph)

(provide 'ragel-mode)