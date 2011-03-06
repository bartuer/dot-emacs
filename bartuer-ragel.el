(defun bartuer-ragel-load ()
  "mode hooks for ragel"
  (define-key ruby-mode-map "\C-j" 'compile-ruby)
  (define-key ruby-mode-map "\C-c\C-s" 'show-graph)
  
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
  )