(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-load ()
  "mode hooks for ruby"
  (yas/minor-mode-auto-on)
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign))
  