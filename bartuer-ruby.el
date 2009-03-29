(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-load ()
  "mode hooks for ruby"
  (require 'rcodetools nil t)
  (require 'anything-rcodetools)
  (require 'ruby-eletric nil t)
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (define-key ruby-mode-map "\C-\M-h" 'ruby-mark-defun)
  (define-key ruby-mode-map "\C-j" 'ruby-send-block)
  (define-key ruby-mode-map "\C-m" 'reindent-then-newline-and-indent)
  (define-key ruby-mode-map [(f7)] 'ri-ruby-show-args)
  ; only set to ruby-mode, no idea about inf-ruby-mode , for it is not TDC
  (define-key ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything) 
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map [(f7)] 'ri-ruby-show-args)
  (define-key rhtml-mode-map "\M-=" 'bartuer-ruby-assign))

