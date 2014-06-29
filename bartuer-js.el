(require 'moz nil t)
(require 'bartuer-js-inf nil t)

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

(defvar prototype-root "~/local/src/prototype/")
(defvar mui-root "~/local/src/mui/")

(defun unit-test-js ()
  "for unittest_js"
  (interactive)
  (setq unit-test-result
        (shell-command-to-string
               (concat "rake test TESTS="
                       (replace-regexp-in-string
                        "_test" ""
                        (replace-regexp-in-string
                         "\\.js" ""
                         (file-name-nondirectory (buffer-file-name)))))))
  (with-current-buffer
      (get-buffer-create "jct-result")
      (if (buffer-size)
          (erase-buffer))
      (insert unit-test-result))
  )

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

(defun get-jslime-sexp ()
  (save-excursion
    (let ((end (point))
          (beg (find-jexp-beg))
          )
      (buffer-substring-no-properties beg end)
      )
  )
)

(defun bartuer-jslime ()
  (interactive)
  (slime-js-send-buffer)
  (let ((expression (get-jslime-sexp)))
    (slime-repl-eval-string expression)  
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

(defun js-project-root ()
  "find current root for javascript project"
  (cond ((eq 0 (string-match
                (expand-file-name prototype-root)
                (expand-file-name (buffer-file-name))))
         (expand-file-name prototype-root))
        ((eq 0 (string-match
                (expand-file-name mui-root)
                (expand-file-name (buffer-file-name))))
         (expand-file-name (concat mui-root "/aqua") )
         )
        ((or
          (eq 0 (string-match
                 "\\(.*\\)/spec/"
                 (expand-file-name (buffer-file-name))))
          (eq 0 (string-match
                 "\\(.*\\)/"
                 (expand-file-name (buffer-file-name))))
          (eq 0 (string-match
                 "\\(.*\\)/spec/fixtures/"
                 (expand-file-name (buffer-file-name)))))
         (concat (match-string 1
                       (expand-file-name (buffer-file-name)))
                 "/"))
        (t
          (expand-file-name (file-name-directory (buffer-file-name))))))

(setf
 js-jump-schema
 '(
   (prototype-testimp
    (("test/unit/\\1_test.js"                   . "src/lang/\\1.js")
     ("test/unit/\\1_test.js"                   . "src/dom/\\1.js")
     ("test/unit/base_test.js"                  . "src/prototype.js")
     ("test/unit/prototype_test.js"             . "src/prototype.js")
     ("test/unit/position_test.js"              . "src/deprecated.js")
     (t                                         . "src/.*"))
    nil)
   (prototype-test
    (("src/lang/\\1.js"                         . "test/unit/\\1_test.js")
     ("src/dom/\\1.js"                          . "test/unit/\\1_test.js")
     ("src/ajax/\\1.js"                         . "test/unit/ajax_test.js")
     (t                                         . "test/unit/.*"))
    nil)
   (prototype-fixture
    (("test/unit/hash_test.js"                  . "test/unit/fixtures/hash.js")
     (t                                         . "test/unit/fixtures/.*"))
    nil)
   (jspecimp
    (("spec/\\1.spec.js"                        . "\\1.js")
     ("spec/fixtures/\\1.html"                  . "\\1.js")
     (t                                         . "\\1.js"))
     nil)
   (jspec
    (("javascripts/\\1.js"                      . "spec/\\1.spec.js")
     ("spec/fixtures/\\1.html"                  . "spec/\\1.spec.js")
     (t                                         . "spec/.*"))
    t);here need a lambda generate a new test file
   (jspec-fixture
    (("spec/\\1.spec.js"                        . "spec/fixtures/\\1.html")
     ("javascripts/\\1.js"                      . "spec/fixtures/\\1.html")
     (t                                         . "spec/fixtures/.*"))
    t)
   (file-in-project ((t . ".*")) nil)
   ))

(defun js-apply-jump-schema (schema)
  "This function takes a of SCHEMA s.t. each element in the list
can be fed to `defjump'.  This is used to define all of the
rinari-find-* functions, and can be used to customize their
behavior."
  (mapcar
   (lambda (type)
     (let ((name (first type))
	   (specs (second type))
	   (make (third type)))
       (eval `(defjump
		(quote ,(read (format "js-find-%S" name)))
		(quote ,specs)
		'js-project-root
		,(format "Go to the most logical %S given the current location" name)
		,(if make `(quote ,make))
                ,(lambda ()
                   (car (which-function)))
		))))
   schema))

(js-apply-jump-schema js-jump-schema)

(defun js-smart-toggle ()
  "depend on current buffer, switch to the buffer most possible, DWIM"
  (interactive)
  (cond
   ((eq 0 (string-match
           (expand-file-name (concat prototype-root "test/unit/fixtures"))
           (expand-file-name (buffer-file-name)))
        )
    (js-find-prototype-test)
    )
   ((eq 0 (string-match
           (expand-file-name (concat prototype-root "test/unit"))
           (expand-file-name (buffer-file-name)))
        )
    (js-find-prototype-testimp)
    )
   ((eq 0 (string-match
           (expand-file-name (concat prototype-root "src"))
           (expand-file-name (buffer-file-name)))
        )
    (js-find-prototype-test)
    )
   ((eq 0 (string-match
           "\\(.*\\)/spec/fixtures"
           (expand-file-name (buffer-file-name))))
    (js-find-jspec)
    )
   ((eq 0 (string-match
           "\\(.*\\)/spec/"
           (expand-file-name (buffer-file-name))))
    (js-find-jspecimp)
    )
   ((eq 0 (string-match
           "\\(.*\\)"
           (expand-file-name (buffer-file-name)))
        )
    (js-find-jspec)
    )
   )
  )

(defalias 'js-find-autotest 'autotest)

(defun js-find-suite ()
  "find suite name for current buffer"
  (let ((filename (file-name-nondirectory (buffer-file-name)))
        suite-name)
    (cond ((string-match "\\(app.*\\|dev.*\\|lib.*\\|.*\\).spec.js" filename)
           (setq suite-name (match-string 1 filename)))
          ((string-match "\\(app.*\\|dev.*\\|lib.*\\|.*\\).js" filename)
           (setq suite-name (match-string 1 filename))))
    (add-to-list 'suite-list suite-name)
))

(defun js-find-live-edit-string ()
  "find live edit string for current buffer"
  (let (start end)
    (save-excursion
      (goto-char (point-max))
      (if (search-backward "//live-edit:" nil t 1)
          (progn
           (search-forward " ")
           (setq start (point))
           (end-of-line)
           (setq end (point))
           (setq live-edit-string (buffer-substring-no-properties start end)))
        (setq live-edit-string ""))
      )
    ))

(defun js-toggle ()
  "js version `rinari-ido'"
  (interactive)
  (let* ((js-toggle-target (ido-completing-read "Jump to :" 
                                                 (list  "file-in-project" "jspec"  "jspecimp" "jspec-fixture" 
                                                        "prototype-fixture" "prototype-test" "prototype-testimp"
                                                        "autotest") nil t)))
    (apply (intern (concat "js-find-" js-toggle-target)) nil))
  )

(defun js-min-file (orig)
  "invoke yuicompress minimize current buffer"
  (let ((file-name (replace-regexp-in-string "\\.js" "_min.js"  orig)))
        (unless (eq 0 (shell-command (concat
                                      "~/etc/el/vendor/yui/js-min "
                                      orig  " " file-name) nil))
          (message "minimize js failed")
          )
  ))

(defun js-min ()
  (interactive)
  (js-min-file (buffer-file-name)))

(defun js-merge ()
  "invoke sprocketize merge js files"
  (interactive)
  (setq find-js-merge nil)
  (mapcar (lambda (f)
            (when (string-equal (buffer-file-name) f)
              (setq find-js-merge t))) (split-string (shell-command-to-string "sprocketlist")))
  (when (eq find-js-merge t)
         (unless (eq 0 (shell-command (concat
                                       "sprocketize "
                                       "./load.js"
                                       " > z.js") nil))
           (message "merge js failed")
           )
         ))


(defun js-correct (&optional start end)
  "correct js files
wrap block add semicolon correct plus and equal"
  (interactive)
  (when (eq start nil)
    (setq start (region-beginning))
    (setq end (region-end)))
  (let ((content (buffer-substring (point-min) (point-max))))
    (with-current-buffer
        (get-buffer-create (concat (buffer-name) "-correct"))
      (delete-region (point-min) (point-max))
      (insert content)
      (let ((indent-col (current-column)))
        (write-region start end "/tmp/d8-temp.js")
        (shell-command-on-region start end "~/local/bin/uki_jscorrect" t)))
    (ediff-buffers (get-buffer (buffer-name))
                   (get-buffer-create (concat (buffer-name) "-correct")))))

(defun js-indent (&optional start end)
  "invoke jsindent to indent"
  (interactive)
  (when (eq start nil)
    (setq start (region-beginning))
    (setq end (region-end)))
  (let ((indent-col (current-column)))
    (write-region start end "/tmp/d8-temp.js")
    (shell-command-on-region start end "~/local/bin/uki_jsindent" t)
    (indent-rigidly start (point) indent-col)
    )
  )
  
(defun js-to-json (&optional start end)
  "convert region to json string"
  (interactive)
  (when (eq start nil)
    (setq start (region-beginning))
    (setq end (region-end)))
  (write-region start end "/tmp/d8-temp.js")
  (shell-command-on-region start end "~/local/bin/uki_js2json" "*json*" nil)
  (with-current-buffer "*json*"
    (goto-char (point-min))
    (if (equal (thing-at-point 'char) "{") 
        (json-read-object)
      (json-read-array)
    )
    )
  (pop-to-buffer "*json*")
  (pop-to-buffer "*Pp Eval Output*")
  )


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

(defun tmp-test ()
  "run mini test for UI staff"
  (interactive)
  (let* ((test-script 
          (replace-regexp-in-string ".js" ".test"
           (buffer-file-name))))
    (message test-script)
    (when (file-exists-p test-script)
      (shell-command test-script))))

(defcustom push-minor-mode-string " Push"
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

(fset 'stepin
        (lambda (&optional arg)
          "Keyboard macro.
can bind C-j in comint buffer"
          (interactive "p")
          (kmacro-exec-ring-item (quote ("step in" 0 "%d")) arg)))

(defun d8-location (line)
  (interactive)
  (with-current-buffer (get-buffer "z.js")
    (goto-char (point-min))
    (forward-line line)
    (setq overlay-arrow-string "B>")
    (setq overlay-arrow-position (make-marker))
    (set-marker overlay-arrow-position (point)))
  (pop-to-buffer "*d8r*"))

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
  )

(defun bartuer-js-load ()
  "for javascript language
"
  (unless (fboundp 'jxmp)
    (load "~/etc/el/jcodetools/jcodetools.el"))
  (require 'flyspell nil t)
  (when (fboundp 'flyspell-prog-mode)
    (flyspell-prog-mode))
  (yas/minor-mode-on)
  (flymake-mode t)
  (setq js2-mode-show-overlay t)
  (setq js2-mirror-mode nil)
  (make-local-variable 'suite-list)
  (js-find-suite)
  (make-local-variable 'live-edit-string)
  (js-find-live-edit-string)
  (set-up-slime-js-ac)
  (defalias  'pa (lambda () (interactive)
                 (js2-parse-mode)))
  (defalias  'pu (lambda () (interactive)
                 (push-mode)))

  ;; (reload-mode t)
  ;; TODO need more stable message queue, then push will be cheap
  ;; (push-mode t)
  (add-hook 'after-save-hook 'js-merge nil t)
  (add-hook 'after-save-hook 'js-find-live-edit-string nil t)
  (add-hook 'after-save-hook 'js-try-to-parse-buffer nil t)
  (make-local-variable 'js2-mode-show-node)
  (setq js2-mode-show-node nil)

  (when (> (buffer-size) 15000)         ;the limitation of js2 parser
      (require 'espresso nil t)
      (setq indent-line-function 'espresso-indent-line)
      (define-key js2-mode-map "\C-m" 'newline))
  (set (make-local-variable 'indent-region-function) 'js-indent)


  (define-key js2-mode-map "\C-cj" 'js-smart-toggle)
  (define-key js2-mode-map "\C-c\C-j" 'js-toggle)
  (define-key js2-mode-map "\C-\M-n" 'js2-next-error)
  (define-key js2-mode-map "\C-c\C-u" 'js2-show-element)
  (define-key js2-mode-map "\C-c\C-s" 'connect-jsh)

  (define-key js2-mode-map "\C-\M-x" 'js-send-last-sexp-and-go)
  (define-key js2-mode-map "\C-\M-x" 'send-function-jsh)

  (define-key js2-mode-map "\C-c\C-b" 'send-buffer-jsh)
  (define-key js2-mode-map "\C-c\C-r" 'send-region-jsh)

  (define-key js2-mode-map "\C-c\C-e" 'send-expression-jsh)
  (define-key js2-mode-map "\C-c\C-l" 'send-current-line-jsh)

  (define-key js2-mode-map "\C-c\C-c" 'anything-js-browser)
  (define-key js2-mode-map "\C-j" 'bartuer-jslime)
  (define-key js2-mode-map "\M-r" 'js-find-file-in-project)
  (define-key js2-mode-map "\C-\M-i" 'anything-complete-js)
  )


(require 'bartuer-page nil t)
(provide 'bartuer-js)