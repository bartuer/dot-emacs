(defun ragel-indent-line ()
  "proxy indent line to js2"
  (interactive)
  (js2-indent-line)
  )

(defun ragel-new-line ()
  "handle new line"
  (interactive)
  (newline-and-indent)
  (ragel-indent-line)
  )

(defun bartuer-ragel-load ()
  "mode hooks for ragel"

  (set (make-local-variable 'ruby-block-beg-keywords) (cons "%%{" ruby-block-beg-keywords))
  (set (make-local-variable 'ruby-block-beg-re) (regexp-opt ruby-block-beg-keywords))
  (set (make-local-variable 'ruby-block-end-re) "\\<end\\|%%}\\>")
  (set (make-local-variable 'font-lock-defaults) '((ruby-font-lock-keywords) nil nil))

  (font-lock-add-keywords
   nil
   '(
     ("\\<\\(fhold\\|fgoto\\|fcall\\|fret\\|fentry\\|fnext\\|fexec\\|fbreak\\)\\>" . font-lock-builtin-face)
     ("\\<\\(machine\\|action\\|context\\|include\\|range\\|import\\|export\\|prepush\\|postpop\\)\\>" . font-lock-function-name-face)
     ("\\<\\(write\\) +\\(init\\|data\\|exec\\|exports\\|start\\|error\\|first_final\\|contained\\)\\>"
      (1 font-lock-function-name-face nil t)
      (2 font-lock-variable-name-face nil t))
     ("\\<\\(when\\|inwhen\\|outwhen\\|err\\|lerr\\|eof\\|from\\|to\\)\\>" . font-lock-keyword-face)
     ("\\<\\(fpc\\|fc\\|fcurs\\|fbuf\\|fblen\\|ftargs\\|fstack\\)\\>" . font-lock-constant-face)) 
   (font-lock-fontify-buffer))

  (set (make-local-variable 'indent-line-function) 'ragel-indent-line)

  (define-key ruby-mode-map "\C-j" 'compile-ruby)
  (define-key ruby-mode-map "\C-c\C-s" 'show-graph)
  (define-key ruby-mode-map "\C-m" 'newline-and-indent)
)