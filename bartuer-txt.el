(defun txt-imenu ()
  "make the 1.2.3. like section to imenu-index-alist"
  (setq text-imenu ())
  (beginning-of-buffer)
  (while (search-forward-regexp "^\\([0-9]+\\.\\)+[0-9]+\\.? [A-Za-z0-9]" nil t)
    (add-to-list 'text-imenu (cons (save-excursion
                                     (beginning-of-line)
                                     (set-mark-command nil)
                                     (end-of-line)
                                     (buffer-substring-no-properties (mark) (point))
                                     ) (point)) t))
  text-imenu
  )

(defun bartuer-txt-load ()
  "for text mode"
  (require 'flyspell)
  (if (fboundp 'turn-on-flyspell) 
      (turn-on-flyspell))
  (auto-fill-mode)
  (set (make-local-variable 'imenu-create-index-function) 'txt-imenu)
  (define-key text-mode-map "\M-\C-i" 'flyspell-auto-correct-word))
