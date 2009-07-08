(require 'moz nil t)
(require 'bartuer-js-inf nil t)

(defun js-test-toggle ()
  )

(defun autotest ()
  (interactive)
  (cd "..")
  (term "~/bin/jspec_in_term")
  (rename-buffer "jspec-auto-test")
  )

(defun send-current-line-jsh ()
  "send current line to jsh"
  (interactive)
  (beginning-of-line)
  (setq beg (point))
  (end-of-line)
  (setq end (point))
  (send-region-jsh beg end))

(defun bartuer-jxmp (&optional option)
  "dump the jxmpfilter output apropose"
  (interactive (jct-interactive))
  (jxmp option)
  (if (file-exists-p "/tmp/jct-emacs-backtrace")
      (pop-to-buffer 
       (ruby-compilation-do "jct-compilation"
                            (cons "cat" (list "/tmp/jct-emacs-backtrace")))))
  (if (file-exists-p "/tmp/jct-emacs-message")
      (with-current-buffer
          (get-buffer-create "jct-result")
        (if (buffer-size)
            (erase-buffer))
        (with-output-to-string (call-process "cat" nil t nil "/tmp/jct-emacs-message"))    
        (ansi-color-apply-on-region (point-min) (point-max))
        (goto-char (point-min))
        t)))

(defun bartuer-js-load ()
  "for javascript language
"
  (require 'flyspell nil t)
  (when (fboundp 'flyspell-prog-mode)
    (flyspell-prog-mode))
  (yas/minor-mode-on)
  (flymake-mode t)
  (define-key js2-mode-map "\C-cj" 'js-test-toggle)
  (define-key js2-mode-map "\C-c\C-j" 'js-test-toggle)
  (define-key js2-mode-map "\C-\M-n" 'js2-next-error)
  (define-key js2-mode-map "\C-c\C-u" 'js2-show-element)
  (define-key js2-mode-map "\C-c\C-s" 'connect-jsh)
  (define-key js2-mode-map "\C-\M-x" 'send-function-jsh)
  (define-key js2-mode-map "\C-c\C-c" 'send-buffer-jsh)
  (define-key js2-mode-map "\C-c\C-r" 'send-region-jsh)
  (define-key js2-mode-map "\C-c\C-e" 'send-expression-jsh)
  (define-key js2-mode-map "\C-c\C-l" 'send-current-line-jsh)
  (define-key js2-mode-map "\C-j" 'bartuer-jxmp)
  )
