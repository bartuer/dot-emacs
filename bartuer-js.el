
;;; Bartuer-js --- For editing javascript


(require 'moz nil t)
(require 'bartuer-js-inf nil t)
(require 'js2-refactor nil t)

;;; Code:
(defvar suite-list nil)

(defvar live-edit-string "")

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

(defun js-push-spec ()
  "send current buffer related spec to browser"
  (mapcar (lambda (suite)
            (shell-command
             (concat
              "push "
              "\"dev.exesuite('"
              suite
              "')\""
              )))
          suite-list))

(defun find-jexp-beg ()
                 (backward-sexp)
                 (if (or (eq 32 (char-before))
                         (bolp))  
                     (point)
                     (find-jexp-beg)
                   )
  )

(defun jslime-eval-for-loop ()
  (interactive)
  (let ((loop-value-array-code "var slime-js-loop-value = [];"))
    (slime-js-eval
     (concat loop-value-array-code slime-js-buffer-or-region-string))
  )
  )

(defun get-jslime-sexp ()
  (save-excursion
    (let ((end (point))
          (beg (find-jexp-beg))
          )
      (buffer-substring-no-properties beg end)
      )
  )
)

(defun slime-js-send-buffer ()
  (interactive)
  (save-excursion
    (let ((start (point-min))
          (end (point-max)))
      (message "send buffer to swank server")
      (slime-js-eval
       (buffer-substring-no-properties start end))
      (message "Sent buffer"))))

(defun slime-js-send-region ()
  (interactive)
  (save-excursion
    (let ((start (region-beginning))
          (end (region-end)))
      (message "send buffer to swank server")
      (slime-js-eval
       (buffer-substring-no-properties start end))
      (message "Sent region"))))

(defun bartuer-jslime ()
  (interactive)
  (slime-js-send-buffer)
  (let ((expression (get-jslime-sexp)))
    (slime-repl-eval-string  expression)  
    )
  )

(defun bartuer-jxmp (&optional option)
  "dump the jxmpfilter output apropose"
  (interactive (jct-interactive))
  (cond ((string-equal (js-project-root)
                       (expand-file-name prototype-root))
         (unit-test-js))
        ((string-match ".*scratch.js"
                       (file-name-nondirectory
                        (buffer-file-name)))
         (jxmp (concat option
                       " --current_file_name="
                       (expand-file-name (buffer-file-name))))
         (if (file-exists-p "/tmp/jct-emacs-backtrace")
             (progn (pop-to-buffer 
                     (ruby-compilation-do
                      "jct-compilation"
                      (cons "cat" (list "/tmp/jct-emacs-backtrace"))))
                    (sleep-for 0.1)
                    (goto-char (point-min))
                    (compile-goto-error))
           )
         (if (file-exists-p "/tmp/jct-emacs-message")
             (with-current-buffer
                 (get-buffer-create "jct-result")
               (if (buffer-size)
                   (erase-buffer))
               (with-output-to-string
                 (call-process
                  "cat" nil t nil "/tmp/jct-emacs-message"))    
               (ansi-color-apply-on-region (point-min) (point-max))
               (goto-char (point-min))
               t))
         )
        )
  (js-push)
  )

(defun anything-js-browser (reset)
  "let `anything-etags-select' do the right job

it is suitable to browse OO hierarchy"
  (interactive "P")
  (setq anything-etags-enable-tag-file-dir-cache t)
  (if reset
      (setq anything-etags-cache-tag-file-dir nil))
  (unless anything-etags-cache-tag-file-dir
    (setq anything-etags-cache-tag-file-dir
          (ido-completing-read
           "TAGS location:"
           (list "~/local/src/tone/js"
                 "~/etc/el/js"
                 (concat prototype-root "src")
                 "~/local/src/js-functional"
                 "~/etc/el/js/jscore"
                 "~/local/src/closure-library/closure/goog"
                 "./"
                 ))))
  (anything-etags-select))

(defvar js2-parse-mode nil)

(defcustom js2-parse-minor-mode-string " Js2-parse"
  "String to display in mode line when Js2-parse mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  :group 'js2)

(defun js2-show-parse ()
  (interactive)
  (js2-mode-show-node))

(define-minor-mode js2-parse-mode
  "Minor mode to show parse result"
  :group 'js2 :lighter js2-parse-minor-mode-string
  (cond
   (js2-parse-mode
    (add-hook 'post-command-hook 'js2-show-parse nil t)
    )
   (t
    (remove-hook 'post-command-hook 'js2-show-parse t))))

(defun js-push ()
  "send current buffer to browser"
  (interactive)
  (when push-mode
    (let ((filename (file-name-nondirectory
                     (buffer-file-name)))
          (lanuch-cmd live-edit-string))
      (cond ((string-match "spec.js" filename)
             (with-current-buffer (get-buffer-create "*jspec-without-reload*")
               (delete-region (point-min) (point-max))
               (goto-char (point-min)))
             (copy-to-buffer (get-buffer-create "*jspec-without-reload*")
                             (point-min)
                             (point-max))
             (with-current-buffer (get-buffer-create "*jspec-without-reload*")
               (insert "JSpec.allSuites=[];")
               (shell-command-on-region (point-min) (point-max) "push")
               )
             )
            (t
             (with-current-buffer (get-buffer-create "*js-without-reload*")
               (delete-region (point-min) (point-max)))
             (copy-to-buffer (get-buffer-create "*jspec-without-reload*")
                             (point-min)
                             (point-max))
             (with-current-buffer (get-buffer-create "*js-without-reload*")
               (goto-char (point-max))
               (insert "\n;")
               (insert lanuch-cmd)
               (shell-command-on-region (point-min) (point-max) "push")
               )
             )
            )
      )
    (js-push-spec)
    (tmp-test)
    )
  )

(defcustom push-minor-mode-string " Push"
  "String to display in mode line when push mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  :group 'js2)

(defcustom slime-push-minor-mode-string " SlimePush"
  "String to display in mode line when push mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  :group 'js2)

(define-minor-mode push-mode
  "Minor mode to push current buffer to browser"
  :group 'js2 :lighter push-minor-mode-string
  (cond
   (push-mode
    (add-hook 'after-save-hook 'js-push t t)
    )
   (t
    (remove-hook 'after-save-hook 'js-push t)))
  )

(define-minor-mode slime-push-mode
  "Minor mode to push current buffer to browser via slime"
  :group 'js2 :lighter slime-push-minor-mode-string
  (cond
   (push-mode
    (add-hook 'after-save-hook ' 'js-try-to-parse-buffer t)
    )
   (t
    (remove-hook 'after-save-hook 'js-try-to-parse-buffer t)))
  )

(fset 'stepin
        (lambda (&optional arg)
          "Keyboard macro.
can bind C-j in comint buffer"
          (interactive "p")
          (kmacro-exec-ring-item (quote ("step in" 0 "%d")) arg)))

(defun slime-js-complete-symbol-prefix-at-point ()
  (interactive)
  (let* ((expr-beg (line-beginning-position))
        (last-space (save-excursion
                      (search-backward " ")
                      (point)
                      )))
    (if last-space
        (if (< expr-beg last-space)
            last-space
          expr-beg)
      expr-beg
      )
    )
  )

(defun js-try-to-parse-buffer ()
  (interactive)
  (slime-js-send-buffer)
  (slime-repl-eval-string "(function () {if (undefined !== test_result) { try{return JSON2.stringify(test_result, null, '\t');} catch(e) {return test_result;}}}());") 
  )

(eval-after-load 'tern '(progn (require 'tern-auto-complete) (tern-ac-setup)))

(defun web-beautify-format-region-js (beg end)
  "By PROGRAM, format each line in the BEG .. END region."
  (let* ((program (locate-file  "js-beautify.js" (list "~/etc/el/vendor/node_modules/js-beautify/js/bin/"))))
    (save-excursion
      (apply 'call-process-region beg end program t
             (list t nil) t web-beautify-args))))


(defun bartuer-js-load ()
  "for javascript language
"
  (unless (fboundp 'jxmp)
    (load "~/etc/el/jcodetools/jcodetools.el"))

  (require 'flyspell nil t)

  (when (fboundp 'flyspell-prog-mode)
    (flyspell-prog-mode))
  (yas-minor-mode-on)

  (setq js2-mode-show-overlay t)
  (setq js2-mirror-mode nil)
  (set-up-slime-js-ac)
  (slime-js-minor-mode)
  
  (make-local-variable 'js2-mode-show-node)
  (setq js2-mode-show-node nil)

  (set (make-local-variable 'indent-region-function) 'web-beautify-format-region-js)

  (define-key js2-mode-map "\C-cj" 'js-smart-toggle)
  (define-key js2-mode-map "\C-c\C-j" 'js-toggle)
  (define-key js2-mode-map "\C-c\C-u" 'js2-show-element)

  (define-key js2-mode-map "\C-c\C-s" 'connect-jsh)
  (define-key js2-mode-map "\C-\M-x" 'js-send-last-sexp-and-go)
  (define-key js2-mode-map "\C-c\C-e" 'send-expression-jsh)
  (define-key js2-mode-map "\C-c\C-l" 'send-current-line-jsh)

  (define-key js2-mode-map "\C-c\C-\M-n" 'js2-next-error)

  (define-key js2-mode-map "\C-\M-x" 'slime-js-send-defun)
  (define-key js2-mode-map "\C-c\C-b" 'slime-js-send-buffer)
  (define-key js2-mode-map "\C-c\C-r" 'slime-js-send-region)
  (define-key js2-mode-map "\C-\M-u" 'slime-js-start-of-toplevel-form)
  ;; (define-key js2-mode-map "\C-c\C-c" 'anything-js-browser)

  (define-key js2-mode-map "\C-j" 'bartuer-jslime)
  (define-key js2-mode-map "\M-r" 'js-find-file-in-project)
  (define-key js2-mode-map "\C-\M-i" 'anything-complete-js)

  (define-key input-decode-map "\e\eOA" [(meta up)])
  (define-key input-decode-map "\e\eOB" [(meta down)])
  (define-key js2-mode-map [(meta down)] 'js2r-move-line-down)
  (define-key js2-mode-map [(meta up)] 'js2r-move-line-up)

  (define-key js2-mode-map "\C-\M-r" 'js2r-unwrap)
  (define-key js2-mode-map "\C-c\C-c" 'js2r-log-this)
  (define-key js2-mode-map "\M-S" 'js2r-split-string)
  
  (add-hook 'before-save-hook 'web-beautify-js-buffer t t)
  )


(require 'bartuer-page nil t)
(provide 'bartuer-js)