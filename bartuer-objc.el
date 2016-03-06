(require 'anything-yasnippet)

(defun bartuer-objc-load ()
  "mode hooks for objc"
  (interactive)
  (which-function-mode t)               ;even if imenu workable, can not open
  (define-key objc-mode-map "\C-\M-i" 'anything-etags-complete-objc-message)
)




