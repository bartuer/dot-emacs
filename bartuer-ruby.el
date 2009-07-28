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
"
  (let ((item (widget-princ-to-string entry)))
    (ri item)
    (with-current-buffer (format "ri `%s'" item)
      (copy-to-buffer "*current*" (point-min) (point-max)))
    (with-current-buffer "*current*"
      (goto-char (point-min))
      (insert "=begin\n")
      (search-forward "\n\n")
      (insert "=end\n")
      (ruby-mode)
      )
    ))

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
  (interactive (rct-interactive))
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
  (shell-command (concat "mongrel_rails start -C "
                         (rinari-root) "config/mongrel_rails.rb"))
  (find-file (concat (rinari-root) "log/mongrel.log"))
  (message (format "dev-server pid:%s"
                   (shell-command-to-string
                    (concat "cat " (rinari-root) "log/mongrel.pid")))))

(defun rinari-rails-rct-fork ()
  "start and shutdown rcodetool fork server"
  (interactive )
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

(defun bartuer-debug-console ()
  "start a server with debug enabled"
  (interactive)
  (unless (setq rails-debug-process (get-buffer-process "rails-debugger"))
    (setq rails-debug-process (make-comint "rails-debugger"
                                           (concat (rinari-root) "script/debugconsole"))
                                                            rails-debug-process))
  (pop-to-buffer "*rails-debugger*"))

(require 'bartuer-gem)
(require 'rcodetools)
(defalias 'rinari-bartuer-gem 'bartuer-gem)
(defalias 'rinari-bartuer-mongrel 'bartuer-mongrel)
(defalias 'rinari-dev-server 'bartuer-dev-server)
(defalias 'rinari-rct-fork-kill 'rct-fork-kill)
(defalias 'rinari-debug-console 'bartuer-debug-console)

(defun rinari-ido ()
  "jump to rinari-command

the basic idea is I do not need remember rinari bindings, they
are hard to press and hard to remember, `ido-completing-read' do
it perfectly.
"
  (interactive)
  (let* ((rinari-command (ido-completing-read "rinari:" 
                                   (list  "find-controller" "find-environment" "find-file-in-project"
                                          "find-helper" "find-migration" "find-javascript" "find-plugin"
                                          "find-model" "find-configuration" "find-log"
                                          "find-public" "find-script" "find-test" "find-view"
                                          "find-worker" "find-fixture" "find-stylesheet" "find-by-context"
                                          "console" "debug-console" "cap" "insert-erb-skeleton" "rgrep"
                                          "rct-fork-kill" "rails-rct-fork"
                                          "sql" "rake" "script" "test" "dev-server" "web-server"
                                          "extract-partial" "bartuer-gem" "bartuer-mongrel" "rails-logs") nil t)))
    (apply (intern (concat "rinari-" rinari-command)) nil)))


(defun anything-ruby-browser ()
  "let `anything-etags-select' do the right job

it is suitable to browse OO hierarchy"
  (interactive )
  (setq anything-etags-enable-tag-file-dir-cache t)
  (unless anything-etags-cache-tag-file-dir
    (setq anything-etags-cache-tag-file-dir (ido-completing-read "TAGS location:"
                                                               (list "~/local/src/rails/actionpack"
                                                                     "~/local/src/rails/activemodel"
                                                                     "~/local/src/rails/activerecord"
                                                                     "~/local/src/rails/railties"
                                                                     "~/local/src/rails/actionmailer"
                                                                     "~/local/src/rails/activesupport"))))
  (anything-etags-select))
  
  
(defun bartuer-ruby-load ()
  "mode hooks for ruby"

  ;; pre load to speed up
  (visit-tags-table "~/local/src/ruby/branches/ruby_1_8_6/TAGS.exuberant")
  (visit-tags-table "~/local/src/rails/TAGS.rtags")

  (setq anything-etags-cache-tag-file-dir "~/local/src/rails/")

  ;; toggle these modes
  (yas/minor-mode-auto-on)
  (ruby-electric-mode)
  (flyspell-prog-mode)
  (flymake-mode)

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
  (define-key anything-isearch-map "\C-c\C-c" 'anything-ruby-browser)

  ; only set to ruby-mode, no idea about inf-ruby-mode , for it is not TDC
  (define-key ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything)
  (define-key inf-ruby-mode-map "\C-\M-i" 'rct-complete-symbol--anything) 
  (define-key ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map "\M-=" 'bartuer-ruby-assign)
  (define-key inf-ruby-mode-map [(f7)] 'ri-ruby-show-args)
  (define-key rhtml-mode-map "\M-=" 'bartuer-ruby-assign))

(provide 'bartuer-ruby)