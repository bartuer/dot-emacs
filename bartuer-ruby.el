;copyed from http://www.emacswiki.org/emacs/FlymakeRuby
(defun flymake-ruby-init ()             
  (let* ((temp-file   (flymake-init-create-temp-buffer-copy
                       'flymake-create-temp-inplace))
	 (local-file  (file-relative-name
                       temp-file
                       (file-name-directory buffer-file-name))))
    (list "ruby" (list "-c" local-file))))

(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-load ()
  "mode hooks for ruby"
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (flyspell-mode)
  (flymake-mode)
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

