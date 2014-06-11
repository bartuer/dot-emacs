(defun bartuer-scheme-load ()
  "for scheme language
"
  (load "xscheme.el")
  (when (fboundp 'advertised-xscheme-send-previous-expression)
    (define-key scheme-mode-map "\C-j" 'advertised-xscheme-send-previous-expression)
    (define-key scheme-interaction-mode-map "\C-j" 'advertised-xscheme-send-previous-expression)
  ))