(defun bartuer-txt-load ()
  "for text mode"
  (require 'flyspell)
  (if (fboundp 'turn-on-flyspell) 
      (turn-on-flyspell))
  (auto-fill-mode)
  (define-key text-mode-map "\M-\C-i" 'flyspell-auto-correct-word))
