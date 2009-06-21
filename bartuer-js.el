(require 'moz nil t)

(defun autotest ()
  (interactive)
  (cd "..")
  (term "~/bin/jspec_in_term")
  (rename-buffer "jspec-auto-test")
  )

(defun moz-send-current-line ()
  "send current line to mozrepl"
  (interactive)
  (beginning-of-line)
  (setq beg (point))
  (end-of-line)
  (setq end (point))
  (moz-send-region beg end))
    
(defun bartuer-js-load ()
  "for javascript language
"
  (require 'flyspell nil t)
  (when (fboundp 'flyspell-prog-mode)
    (flyspell-prog-mode))

  (moz-minor-mode t)
  (yas/minor-mode-on)
  (flymake-mode t)
  (define-key js2-mode-map "\C-\M-n" 'js2-next-error)
  (define-key js2-mode-map "\C-c\C-u" 'js2-show-element)
  (define-key js2-mode-map "\C-\M-x" 'moz-send-defun)
  (define-key js2-mode-map "\C-j" 'moz-send-current-line)
  )


