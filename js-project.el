(defvar prototype-root "~/local/src/prototype/")

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

(defun js-toggle ()
  "js version `rinari-ido'"
  (interactive)
  (let* ((js-toggle-target (ido-completing-read "Jump to :" 
                                                 (list  "file-in-project" "jspec"  "jspecimp" "jspec-fixture" 
                                                        "prototype-fixture" "prototype-test" "prototype-testimp"
                                                        "autotest") nil t)))
    (apply (intern (concat "js-find-" js-toggle-target)) nil))
  )
