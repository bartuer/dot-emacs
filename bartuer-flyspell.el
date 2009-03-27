(defun bartuer-flyspell-load ()
  "for flyspell minor mode"
  (define-key flyspell-mode-map "\C-c\C-\M-i" 'flyspell-auto-correct-word))