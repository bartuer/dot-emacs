(load "~/etc/el/vendor/ruby-mode/ruby-electric.el")

(require 'ruby-eletric nil t)

(require 'ri-query nil t)

(defun bartuer-ruby-ri (entry)
  "return the documents of entry"
  (let ((item (widget-princ-to-string entry)))
    (with-output-to-temp-buffer item
      (princ
       (ri-query item))))
  )

(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-load ()
  "mode hooks for ruby"
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (define-key ruby-mode-map "\C-\M-h" 'ruby-mark-defun)
  (define-key ruby-mode-map "\C-j" 'ruby-send-block)
  (define-key ruby-mode-map "\C-m" 'reindent-then-newline-and-indent)
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key rhtml-mode-map "\M-=" 'bartuer-ruby-assign))

