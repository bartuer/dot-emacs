(require 'moz nil t)
(require 'bartuer-js-inf nil t)

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

(defun bartuer-jxmp (&optional option)
  "dump the jxmpfilter output apropose"
  (interactive (jct-interactive))
  (when (string-equal (js-project-root)
                    (expand-file-name prototype-root))
      (unit-test-js))
  (jxmp (concat option " --current_file_name=" (expand-file-name (buffer-file-name))))
  (if (file-exists-p "/tmp/jct-emacs-backtrace")
      (progn (pop-to-buffer 
              (ruby-compilation-do "jct-compilation"
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
        (with-output-to-string (call-process "cat" nil t nil "/tmp/jct-emacs-message"))    
        (ansi-color-apply-on-region (point-min) (point-max))
        (goto-char (point-min))
        t))
  )


(defun anything-js-browser (reset)
  "let `anything-etags-select' do the right job

it is suitable to browse OO hierarchy"
  (interactive "P")
  (setq anything-etags-enable-tag-file-dir-cache t)
  (if reset
      (setq anything-etags-cache-tag-file-dir nil))
  (unless anything-etags-cache-tag-file-dir
    (setq anything-etags-cache-tag-file-dir (ido-completing-read "TAGS location:"
                                                               (list "~/etc/el/js"
                                                                     "~/local/src/baza/lib/Parts"
                                                                     (concat prototype-root "src")
                                                                     "~/local/src/js-functional"
                                                                     "~/local/src/scriptaculous/src"
                                                                     "~/etc/el/js/jscore"
                                                                     "~/local/src/mozilla-1.9.1/js/narcissus"
                                                                     ))))
  (anything-etags-select))

(defun js-project-root ()
  "find current root for javascript project"
  (cond ((eq 0 (string-match
                (expand-file-name prototype-root)
                (expand-file-name (buffer-file-name))))
         (expand-file-name prototype-root))
        ((or
          (eq 0 (string-match
                 "\\(.*\\)/spec/"
                 (expand-file-name (buffer-file-name))))
          (eq 0 (string-match
                 "\\(.*\\)/lib/"
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
    (("spec/spec.\\1.js"                        . "lib/\\1.js")
     ("spec/fixtures/\\1.html"                  . "lib/\\1.js")
     (t                                         . "lib/.*js"))
     nil)
   (jspec
    (("lib/\\1.js"                              . "spec/spec.\\1.js")
     ("spec/fixtures/\\1.html"                  . "spec/spec.\\1.js")
     (t                                         . "spec/spec.*"))
    t);here need a lambda generate a new test file
   (jspec-fixture
    (("spec/spec.\\1.js"                        . "spec/fixtures/\\1.html")
     ("lib/\\1.js"                              . "spec/fixtures/\\1.html")
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
		))))
   schema))

(js-apply-jump-schema js-jump-schema)

(defun js-smart-toggle ()
  "depend on current buffer, switch to the buffer most possible, DWIM"
  (interactive)
  (cond 
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
                 "\\(.*\\)/lib/"
                 (expand-file-name (buffer-file-name)))
              )
          (js-find-jspec)
          )
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
          ))
        )

(defalias 'js-find-autotest 'autotest)

(defun js-toggle ()
  "js version `rinari-ido'"
  (interactive)
  (let* ((js-toggle-target (ido-completing-read "Jump to :" 
                                                 (list  "jspec-fixture" "file-in-project" "autotest"
                                                        "jspec"  "jsepcimp"
                                                        "prototype-fixture" "prototype-test" "prototype-testimp") nil t)))
    (apply (intern (concat "js-find-" js-toggle-target)) nil))
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
  (defalias  'w 'js2-mode-show-node)
  (define-key js2-mode-map "\C-cj" 'js-smart-toggle)
  (define-key js2-mode-map "\C-c\C-j" 'js-toggle)
  (define-key js2-mode-map "\C-\M-n" 'js2-next-error)
  (define-key js2-mode-map "\C-c\C-u" 'js2-show-element)
  (define-key js2-mode-map "\C-c\C-s" 'connect-jsh)
  (define-key js2-mode-map "\C-\M-x" 'send-function-jsh)
  (define-key js2-mode-map "\C-c\C-b" 'send-buffer-jsh)
  (define-key js2-mode-map "\C-c\C-r" 'send-region-jsh)
  (define-key js2-mode-map "\C-c\C-e" 'send-expression-jsh)
  (define-key js2-mode-map "\C-c\C-l" 'send-current-line-jsh)
  (define-key js2-mode-map "\C-c\C-c" 'anything-js-browser)
  (define-key js2-mode-map "\C-j" 'bartuer-jxmp)
  (define-key js2-mode-map "\C-\M-i" 'anything-complete-js)
  )
