;copyed from http://www.emacswiki.org/emacs/FlymakeRuby
(defun flymake-ruby-init ()             
  (let* ((temp-file   (flymake-init-create-temp-buffer-copy
                       'flymake-create-temp-inplace))
	 (local-file  (file-relative-name
                       temp-file
                       (file-name-directory buffer-file-name))))
    (list "ruby" (list "-c" local-file))))

(defun ruby-test-toggle ()
  "toggle between test and implement files"
  (interactive)
  (ruby-toggle-buffer)
  )

(defun bartuer-ruby-assign ()
  "insert the =>"
  (interactive)
  (insert " => "))

(defun bartuer-ruby-ri-current (entry)
  "after query ri, jump to *current* buffer immediatly"
  (bartuer-ruby-ri entry)
  (goto-line 2 "*current*")
  )

(defalias 'rdoc 'bartuer-ruby-ri-current)

(defun bartuer-ruby-ri (entry)
  "return the ri documents of entry  

Common problem for document reading is read it not hard but find
the right one need time, so the above problem divided to :

- how to filter proper ones among huge candidates?
- how to go through a list of document as soon as possible?

`icy-mode' and `icicle-help-on-next-apropos-candidate'
resolve such problem very well. The trick is advice any place
where a candidate list exist, see `ri-ruby-read-keyw'.

Common problem for understand document is the other side of coin:
to understand code you need read the document, but to understand
the document you need try the sample code.

`xmp',`ruby-send-region' such tools could save your time to move
code in document to an interpreter, so why not make the document
buffer behave like a source code buffer?  The trick is comment
the document part and make the code part ready to be evaluated.

finally, it is easy access document from source code for document
is generated from source code, but if I want to access source
code from document, there is no direct way like docstring in
lisp, really need add one.
"
  (let ((item (widget-princ-to-string entry)))
    (ri item)
    (with-current-buffer (format "ri `%s'" item)
      (copy-to-buffer "*current*" (point-min) (point-max)))
    (with-current-buffer "*current*"
      (goto-char (point-min))
      (insert "=begin\n")
      (insert-source-link entry)
      (insert "\n")
      )
    ))

(defun actionpack-rct-option ()
  "-I/Users/bartuer/local/src/rails/actionpack/test -I/Users/bartuer/local/src/rails/actionpack/lib")

;; (link "~/local/src/rails/activerecord/xmp-option" 1)
(defun activerecord-rct-option ()
  "-I/Users/bartuer/local/src/rails/activerecord/lib -I/Users/bartuer/local/src/rails/activerecord/test -I/Users/bartuer/local/src/rails/activerecord/test/connections/native_sqlite3")

(defun baza-rct-option ()
  "-I~/local/src/baza/test")

(defun ido-rct-option ()
  "select rct options from candidate"
  (list
   (let ((option (or rct-option-local "")))
     (if current-prefix-arg
         (let ((compact-rct-option (ido-completing-read "(describe-variable 'rct-option-local)"
                                               (list "actionpack" "activerecord" "baza"))))(actionpack-rct-option)
           (setq rct-option-local (apply (intern (concat compact-rct-option "-rct-option")) nil)))
       option))))

(defun bartuer-xmp (&optional option)
  "link compilation to xmp

Imporve xml-filter: if some error occured, should throw a
compilation buffer include the error backtrace, not only dump it
at end of the file.

So, if there is no error, I do not need check the result at end
of the file,

In error case I switch to the compile/correct loop immediately.

Such solution can save screen space, for do not need monit the
end of file in one frame anymore.

And more, will create an useful tool to reading code, for I can
generate a raise, and get the call stack there, go through them
to understand the related codes. The idea is as same as reading
code through debugger.

if in test buffer, will do test C-u C-j initialize the rct
option rake -t test_... TEST=test_file then, REMOVE test loader
REMOVE ruby binary NORMALLY IT IS THE INCLUDE PATH.
 "
  (interactive (ido-rct-option))
  (xmp (concat option " --current_file_name=" (buffer-file-name)))
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

(defun rails-logs ()
  (interactive)
  (find-file "~/Sites/baza/current/log/production.log")
  (find-file "/private/var/log/apache2/error_log")
  (find-file "/private/var/log/apache2/access_log")
  (find-file "~/local/src/baza/log/development.log")
  (find-file "~/local/src/baza/log/mongrel.log")
  (pop-to-buffer "*Ibuffer*")
  (ibuffer-update nil)
  (ibuffer-jump-to-filter-group "log"))
(defalias 'rinari-rails-logs 'rails-logs)

(defun bartuer-dev-server ()
  "start up mongrel_rails server"
  (interactive)
  (let ((mongrel_pid (shell-command-to-string
                      (concat "cat " (rinari-root) "log/mongrel.pid")))
        )
    (if (eq 0 (signal-process mongrel_pid 19)) 
        (progn (shell-command (concat "mongrel_rails restart -P "
                                      (rinari-root) "log/mongrel.pid"))
               (sleep-for 3)
               (message (format "dev-server restart %s -> %s"
                                mongrel_pid
                                (shell-command-to-string
                                 (concat "cat " (rinari-root) "log/mongrel.pid")))))
      (shell-command (concat "mongrel_rails start -C "
                             (rinari-root) "config/mongrel_rails.rb"))
      (find-file (concat (rinari-root) "log/mongrel.log"))
      (message (format "dev-server start as pid:%s"
                       mongrel_pid)))))

(defun rinari-rails-rct-fork ()
  "start and shutdown rcodetool fork server"
  (interactive)
  (rct-fork (concat "-r " (rinari-root) "config/environment -r console_app -r console_with_helpers -r actionpack"
                    " -I" (rinari-root) "lib" " -I" (rinari-root) "test")))

(setq rinari-script-list
      (list "about" "browserreload" "console" "dbconsole" "debugconsole"
       "destroy" "generate" "performance/benchmarker" "performance/profiler"
       "plugin" "process/inspector" "process/reaper" "process/spawner" "runner" "server" "spin"
       "generate controller" "generate helper" "generate integration_test" "generate mailer"
       "generate metal" "generate migration" "generate model" "generate observer"
       "generate performance_test" "generate plugin" "generate resource"
       "generate scaffold" "generate session_migration"
       ))

(defun insert-source-link (string)
  (with-current-buffer "TAGS.rtags"
    (goto-char (point-min))
    (if (re-search-forward (concat string "\\b") nil t)
        (progn
          (setq source-link-hit t)
          (beginning-of-line)
          (setq follow-etags-goto-func goto-tag-location-function)
          (setq follow-etags-tag-info (save-excursion (funcall snarf-tag-function)))
          (setq tag (if (eq t (car follow-etags-tag-info))
                        nil
                      (car follow-etags-tag-info)))
          (setq follow-etags-file-path (save-excursion (if tag (file-of-tag)
                                                         (save-excursion (forward-line 1)
                                                                         (file-of-tag)))))

          (setq full-file-name-string (if tag (file-of-tag t)
                                        (save-excursion (forward-line 1)
                                                        (file-of-tag t))))
          (setq file-label (substring full-file-name-string
                                      (length (file-name-directory full-file-name-string))))
          )
      (setq source-link-hit nil)))
  (setq pt (point))
  (if source-link-hit
      (if tag
          (progn
            (insert (format "%s : " file-label))
            (insert tag)
            (make-text-button pt (point)
                              'tag-info follow-etags-tag-info
                              'file-path follow-etags-file-path
                              'goto-func follow-etags-goto-func
                              'action (lambda (button)
                                        (let ((tag-info (button-get button 'tag-info))
                                              (goto-func (button-get button 'goto-func)))
                                          (tag-find-file-of-tag (button-get button 'file-path))
                                          (widen)
                                          (funcall goto-func tag-info)))
                              'face 'speedbar-button-face
                              'type 'button))
        (insert (format "- %s" file-label))
        (make-text-button pt (point)
                          'file-path follow-etags-file-path
                          'action (lambda (button)
                                    (tag-find-file-of-tag (button-get button 'file-path))
                                    (goto-char (point-min)))
                          'face 'speedbar-button-face
                          'type 'button)
        )))


(setq anything-c-source-qri 
      '((name . "All Ruby Classes and Methods")
        (candidates 
         .
         (lambda () anything-c-source-qri-list)) 
        (init
         . 
         (lambda ()
           (condition-case x
               (setq anything-c-source-qri-list (split-string
                                                          (shell-command-to-string
                                                           (concat
                                                           "qri --classes --methods|grep "
                                                           anything-qri-query)
                                                          )))
             (error (setq anything-c-source-qri-methods-list nil))
             ))
           )
        (action
         ("ri" . bartuer-ruby-ri-current)
         ("location" . tags-apropos)
        )))

(defun anything-qri (query)
  "
show all ruby methods, filter and and invoke ri on candidate
"
  (interactive (list
                (read-string "qri --classes --methods: " )))
  (setq anything-qri-query query)
  (let ((anything-sources (list anything-c-source-qri)))
    (anything)))

(defun full-qri (query)
  "query all ri's fulltext"
  (interactive (list (read-string "qri -S : ")))
  (get-buffer-create "qri")
  (with-current-buffer "qri"
    (insert (shell-command-to-string (concat "qri -S " query)))
    (goto-char (point-min))
    (occur "^Found in")
    )
  (pop-to-buffer "qri")
  (display-buffer "*Occur*")
  )

(defun rinari-qri ()
  "query fast ri server"
  (interactive)
  (let ((rinari-qri-command (ido-completing-read "qri:" 
                     (list  "anything"
                            "full"))))
    (if (string-equal rinari-qri-command "full")
                   (call-interactively 'full-qri)
      (call-interactively 'anything-qri))
   ))

(defun bartuer-debug-console ()
  "start a server with debug enabled"
  (interactive)
  (unless (setq rails-debug-process (get-buffer-process "rails-debugger"))
    (setq rails-debug-process (make-comint "rails-debugger"
                                           (concat (rinari-root) "script/debugconsole"))
                                                            rails-debug-process))
  (pop-to-buffer "*rails-debugger*"))

(setq browserreload-location "script/browserreload -b Safari,Firefox http://localhost:3000/")
(defun rinari-browserreload ()
  "start a monitor server to reload browser when file changed"
  (interactive)
  (ruby-compilation-run (concat (rinari-root) browserreload-location
                                (read-from-minibuffer browserreload-location)))
)

(require 'bartuer-gem)
(require 'rcodetools)
(defalias 'rinari-bartuer-gem 'bartuer-gem)
(defalias 'rinari-bartuer-mongrel 'bartuer-mongrel)
(defalias 'rinari-dev-server 'bartuer-dev-server)
(defalias 'rinari-rct-fork-kill 'rct-fork-kill)
(defalias 'rinari-debug-console 'bartuer-debug-console)
(defalias 'q 'rinari-qri)

(defun rinari-ido ()
  "jump to rinari-command

the basic idea is I do not need remember rinari bindings, they
are hard to press and hard to remember, `ido-completing-read' do
it perfectly.
"
  (interactive)
  (let* ((rinari-command (ido-completing-read "rinari:" 
                                   (list  "find-model" "find-migration" "find-controller" "find-view" "find-stylesheet"
                                          "find-javascript" "find-script" "find-public" "find-test" "find-fixture"
                                          "script" "browserreload" "dev-server" "web-server" "test"
                                          "console" "debug-console" 
                                          "find-environment" "find-configuration" "find-file-in-project"
                                          "find-helper"  "find-plugin" 
                                          "find-log" "rails-logs"
                                          "find-worker"  "find-by-context"
                                          "cap" "insert-erb-skeleton" "rgrep" "sql" "rake"   
                                          "rails-rct-fork" "rct-fork-kill" 
                                          "extract-partial" "bartuer-gem" "bartuer-mongrel"  "qri") nil t)))
    (apply (intern (concat "rinari-" rinari-command)) nil)))


(defun anything-ruby-browser (reset)
  "let `anything-etags-select' do the right job

it is suitable to browse OO hierarchy"
  (interactive "P")
  (setq anything-etags-enable-tag-file-dir-cache t)
  (if reset
      (setq anything-etags-cache-tag-file-dir nil))
  (unless anything-etags-cache-tag-file-dir
    (setq anything-etags-cache-tag-file-dir (ido-completing-read "TAGS location:"
                                                               (list "~/local/src/rails/actionpack"
                                                                     "~/local/src/rails/activemodel"
                                                                     "~/local/src/rails/activerecord"
                                                                     "~/local/src/rails/railties"
                                                                     "~/local/src/rails/actionmailer"
                                                                     "~/local/src/rails/activesupport"))))
  (anything-etags-select))


(defun not-region-p ()
  "is there a region actived?"
  (if (region-active-p)
      (progn
        (setq rct-comment-beg (region-beginning))
        (setq rct-comment-end (region-end))
        nil)
    t))

(defun comment-block-dwim (beg end)
  "add/remove =begin/=end depend on region beg and end

=begin
the block line one
the block line two
the block line three
=end

"
  (if (and (progn
             (goto-char beg)
             (search-forward "=begin" end t))
           (progn
             (goto-char beg)
             (search-forward "=end" end t))
           )
      (progn
        (goto-char end)
        (search-backward "=end" beg t)
        (kill-line)
        (goto-char beg)
        (search-forward "=begin" end t)
        (beginning-of-line)
        (kill-line))
    (goto-char end)
    (insert "=end")
    (goto-char beg)
    (insert "=begin ")
    (goto-char beg)
  ))

(defun ruby-block-comment ()
  "insert/remove =begin/=end style comments"
  (interactive)
  (unless (not-region-p)
    (comment-block-dwim rct-comment-beg rct-comment-end)))
  
(defun bartuer-ruby-load ()
  "mode hooks for ruby"

  ;; pre load to speed up
  (when (file-exists-p "~/local/src/ruby/branches/ruby_1_8_6/TAGS.exuberant")
      (visit-tags-table "~/local/src/ruby/branches/ruby_1_8_6/TAGS.exuberant"))
  (when (file-exists-p "~/local/src/rails/TAGS.rtags")
    (visit-tags-table "~/local/src/rails/TAGS.rtags"))


  ;; toggle these modes
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (flyspell-prog-mode)
  (unless (string-equal (buffer-name) "*current*")
          (flymake-mode))

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
  (define-key ruby-mode-map "\C-c\C-o" 'ruby-load-file)
  (define-key ruby-mode-map "\C-c\C-c" 'anything-ruby-browser)
  (define-key ruby-mode-map "\C-c\M-;" 'ruby-block-comment)
  (define-key inf-ruby-mode-map "\C-c\C-c" 'anything-ruby-browser)
  (define-key anything-isearch-map "\C-c\C-c" 'anything-ruby-browser)

  ; only set to ruby-mode, no idea about inf-ruby-mode , for it is not TDC
  (define-key ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything)
  (define-key inf-ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything) 
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map [(f7)] 'ri-ruby-show-args)
  (define-key ruby-mode-map "\C-x\C-e" 'eval-last-sexp)
  )

(provide 'bartuer-ruby)