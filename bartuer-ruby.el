;copyed from http://www.emacswiki.org/emacs/FlymakeRuby
(defun flymake-ruby-init ()             
  (let* ((temp-file   (flymake-init-create-temp-buffer-copy
                       'flymake-create-temp-inplace))
	 (local-file  (file-relative-name
                       temp-file
                       (file-name-directory buffer-file-name))))
    (list "ruby" (list "-c" local-file))))

(defun ruby-test-toggle ()
  (interactive)
  (ruby-toggle-buffer)
  )

(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-ri (entry)
  "return the documents of entry"
  (let ((item (widget-princ-to-string entry)))
    (with-output-to-temp-buffer (format "ri %s" item) 
      (princ
       (ri-ruby-process-get-lines "DISPLAY_INFO" item)))))

;; Imporve xml-filter: if some error occured, should throw a
;; compilation buffer include the error backtrace, not only dump it
;; at end of the file.
;; 
;; So, if there is no error, I do not need check the result at end
;; of the file, in error case I switch to the compile/correct loop
;; immediately.  See rinari's solution for the same problem.
;; 
;; Such solution can save screen space, do not need monit the end
;; file in one frame anymore, and more, will create an useful tool
;; to reading code, for I can generate a raise, and get the call
;; stack there, go through them to understand the related codes. The
;; idea is as same as reading code through debugger.
;;
;; And the successful test result will not mess up version control,
;; meaningless to record that in VC.

(defun bartuer-xmp (&optional option)
  "dump the xmpfilter output apropose"
  (interactive (rct-interactive))
  (xmp option)
  (if (file-exists-p "/tmp/rct-emacs-backtrace")
      (pop-to-buffer 
       (ruby-compilation-do "rct-compilation"
                            (cons "cat" (list "/tmp/rct-emacs-backtrace")))))
  (if (file-exists-p "/tmp/rct-emacs-message")
      (with-current-buffer
          (get-buffer-create "rct-result")
        (if (buffer-size)
            (erase-buffer))
        (with-output-to-string (call-process "cat" nil t nil "/tmp/rct-emacs-message"))    
        (goto-char (point-min))
        t)))


(defun rinari-ido ()
  "jump to rinari-command"
  (interactive)
  (let* ((rinari-command (ido-completing-read "rinari:" 
                                   (list  "find-controller" "find-environment" "find-file-in-project"
                                          "find-helper" "find-migration" "find-javascript" "find-plugin"
                                          "find-model" "find-configuration" "find-log"
                                          "find-public" "find-script" "find-test" "find-view"
                                          "find-worker" "find-fixture" "find-stylesheet" "find-by-context"
                                          "console" "cap" "insert-erb-skeleton" "rgrep"
                                          "sql" "rake" "script" "test" "web-server" "extract-partial" ) nil t)))
    (apply (intern (concat "rinari-" rinari-command)) nil)))

(defun bartuer-ruby-load ()
  "mode hooks for ruby"

  ;; pre load to speed up
  (visit-tags-table "~/local/src/ruby/branches/ruby_1_8_6/TAGS.exuberant")
  (visit-tags-table "~/local/src/rails/TAGS.rtags")

  ;; toggle these modes
  (setq icicle-candidate-help-fn 'bartuer-ruby-ri)
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (flyspell-prog-mode)
  (flymake-mode)

  ;; if in test buffer, will do test
  ;; C-u C-j initialize the rct option
  ;; rake -t test_... TEST=test_file
  ;; then,
  ;; REMOVE test loader
  ;; REMOVE ruby binary
  ;; normally it is the include path
  (if (fboundp 'bartuer-xmp)
      (add-hook 'before-save-hook (lambda ()
                                    (bartuer-xmp (car rct-option-history))))) 

  (define-key rinari-minor-mode-map "\M-r" 'rinari-ido)
  (define-key ruby-mode-map "\C-cj" 'ruby-test-toggle)
  (define-key ruby-mode-map "\C-c\C-j" 'ruby-test-toggle)
  (define-key ruby-mode-map "\C-j" 'bartuer-xmp)
  (define-key ruby-mode-map "\C-hh" 'rct-ri)
  (define-key ruby-mode-map "\C-\M-h" 'ruby-mark-defun)
  (define-key ruby-mode-map "\C-\M-n" 'ctrl-meta-n-dwim)
  (define-key ruby-mode-map "\C-\M-p" 'ctrl-meta-p-dwim)
  (define-key ruby-mode-map "\C-\M-a" 'ruby-beginning-of-block)
  (define-key ruby-mode-map "\C-\M-e" 'ruby-end-of-block)
  (define-key ruby-mode-map "\C-m" 'reindent-then-newline-and-indent)
  (define-key ruby-mode-map [(f7)] 'ri-ruby-show-args)
  ;; also see binding in inf-ruby.el
  (define-key ruby-mode-map "\C-c\C-s" 'inf-ruby)
  (define-key ruby-mode-map "\C-\M-x" 'ruby-send-definition)
  (define-key ruby-mode-map "\C-c\C-r" 'ruby-send-region)
  (define-key ruby-mode-map "\C-c\C-l" 'ruby-send-last-sexp)
  (define-key ruby-mode-map "\C-c\C-b" 'ruby-send-block)
  (define-key ruby-mode-map "\C-c\C-c" 'ruby-load-file)

  ; only set to ruby-mode, no idea about inf-ruby-mode , for it is not TDC
  (define-key ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything)
  (define-key inf-ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything) 
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map [(f7)] 'ri-ruby-show-args)
  (define-key rhtml-mode-map "\M-=" 'bartuer-ruby-assign))

