(defun bartuer-txt-load ()
  "for text mode"
  (require 'flyspell)
  (if (fboundp 'turn-on-flyspell)
      (turn-on-flyspell))
  (auto-fill-mode)
  )
