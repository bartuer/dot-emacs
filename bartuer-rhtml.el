(autoload 'bartuer-ruby-assign "bartuer-ruby.el" "for ruby assign" t nil)
(defun bartuer-rhtml-load ()
  "mode hooks for rhtml"
  (yas/minor-mode-auto-on)
  (define-key rhtml-mode-map "\M-=" 'bartuer-ruby-assign))