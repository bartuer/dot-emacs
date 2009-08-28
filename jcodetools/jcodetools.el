;;; jcodetools.el -- annotation / accurate completion / browsing documentation

;;; steel it from:
;;; Copyright (c) 2006-2008 rubikitch <rubikitch@ruby-lang.org> 
;;;
;;; see rcodetool at http://rubyforge.org/projects/rcodetools


(defvar jxmpfilter-command-name "ruby -S jxmpfilter --no-warnings  --fork "
  "The xmpfilter command name.")
(defvar jct-doc-command-name "ruby -S jct-doc --fork "
  "The jct-doc command name.")
(defvar jct-complete-command-name "ruby -S jxmpfilter --completion --no-warnings --fork "
  "The jct-complete command name.")
(defvar js-toggle-file-command-name "ruby -S js-toggle-file"
  "The ruby-toggle-file command name.")
(defvar jct-fork-command-name "ruby -S jct-fork")
(defvar jct-option-history nil)                ;internal
(defvar jct-option-local nil)     ;internal
(make-variable-buffer-local 'jct-option-local)
(defvar jct-debug nil
  "If non-nil, output debug message into *Messages*.")
;; (setq jct-debug t)

(defun has-jct-in-region-p (beg end)
  "search //# => in region beg end
"
  (goto-char beg)
  (if (search-forward-regexp "//# *=>" end t)
      t
    nil)
)

(defun jct-dwim ()
  "if there is //# =>, remove it, otherwise insert it

2 + 3 //
docstring as fixture, try above line.
"
  (setq current-pos (point))
  (setq beg (progn (beginning-of-line) (point)))
  (setq end (progn (end-of-line) (point)))
  (if (has-jct-in-region-p beg end)
      (progn
        (goto-char beg)
        (search-forward "//")
        (kill-line))
    (goto-char current-pos)
    (insert "#=>"))
  )

(defadvice comment-dwim (around jct-hack activate)
  "If comment-dwim is successively called, add //#=> mark."
  (if (and (eq major-mode 'js2-mode)
           (eq last-command 'comment-dwim)
           ;; TODO =>check
           )
      (jct-dwim)
    ad-do-it))
;; To remove this advice.
;; (progn (ad-disable-advice 'comment-dwim 'around 'jct-hack) (ad-update 'comment-dwim)) 

(defun jct-current-line ()
  "Return the vertical position of point..."
  (+ (count-lines (point-min) (point))
     (if (= (current-column) 0) 1 0)))

(defun jct-save-position (proc)
  "Evaluate proc with saving current-line/current-column/window-start."
  (let ((line (jct-current-line))
        (col  (current-column))
        (wstart (window-start)))
    (funcall proc)
    (goto-char (point-min))
    (forward-line (1- line))
    (move-to-column col)
    (set-window-start (selected-window) wstart)))

(defun jct-interactive ()
  "All the jcodetools-related commands with prefix args read rcodetools' common option. And store option into buffer-local variable."
  (list
   (let ((option (or jct-option-local "")))
     (if current-prefix-arg
         (setq jct-option-local
               (read-from-minibuffer "jcodetools option: " option nil nil 'jct-option-history))
       option))))  

(defun jct-shell-command (command &optional buffer)
  "Replacement for `(shell-command-on-region (point-min) (point-max) command buffer t' because of encoding problem."
  (let ((input-rb (concat (make-temp-name "xmptmp-in") ".rb"))
        (output-rb (concat (make-temp-name "xmptmp-out") ".rb"))
        (coding-system-for-read buffer-file-coding-system))
    (write-region (point-min) (point-max) input-rb nil 'nodisp)
    (shell-command
     (jct-debuglog (format "%s %s > %s" command input-rb output-rb))
     t " *jct-error*")
    (with-current-buffer (or buffer (current-buffer))
      (insert-file-contents output-rb nil nil nil t))
    (delete-file input-rb)
    (delete-file output-rb)))

(defvar jxmpfilter-command-function 'jxmpfilter-command)

(defun jxmp (&optional option)
  "Run xmpfilter for annotation/test/spec on whole buffer.
See also `jct-interactive'. "
  (interactive (jct-interactive))
  (jct-save-position
   (lambda ()
     (jct-shell-command (funcall jxmpfilter-command-function option)))))

(defun jxmpfilter-command (&optional option)
  "The jxmpfilter command line, DWIM."
  (setq option (or option ""))
  (flet ((in-block (beg-re)
                   (save-excursion
                     (goto-char (point-min))
                     (re-search-forward beg-re nil t)
                     )))
    (cond ((in-block "\\(JSpec.describe\\)")
           (if (string-match "--completion" option)
               (format "%s --use_spec %s" jct-complete-command-name option)
             (format "%s --spec %s" jxmpfilter-command-name option)))
          (t
           (if (string-match "--completion" option)
               (format "%s  %s" jct-complete-command-name option)
             (format "%s %s" jxmpfilter-command-name option))
           )   
           )
    )
  )

;;;; Completion
(defvar jct-method-completion-table nil) ;internal
(defvar jct-complete-symbol-function 'jct-complete-symbol--normal
  "Function to use jct-complete-symbol.")
;; (setq jct-complete-symbol-function 'jct-complete-symbol--icicles)
(defvar jct-use-test-script t
  "Whether jct-complete/jct-doc use test scripts.")

(defun jct-complete-symbol (&optional option)
  "Perform ruby method and class completion on the text around point.
This command only calls a function according to `jct-complete-symbol-function'.
See also `jct-interactive', `jct-complete-symbol--normal', and `jct-complete-symbol--icicles'."
  (interactive (jct-interactive))
  (call-interactively jct-complete-symbol-function))

(defun jct-complete-symbol--normal (&optional option)
  "Perform ruby method and class completion on the text around point.
See also `jct-interactive'."
  (interactive (jct-interactive))
  (let ((end (point)) beg
	pattern alist
	completion)
    (setq completion (jct-try-completion)) ; set also pattern / completion
    (save-excursion
      (search-backward pattern)
      (setq beg (point)))
    (cond ((eq completion t)            ;sole completion
           (message "%s" "Sole completion"))
	  ((null completion)            ;no completions
	   (message "Can't find completion for \"%s\"" pattern)
	   (ding))
	  ((not (string= pattern completion)) ;partial completion
           (delete-region beg end)      ;delete word
	   (insert completion)
           (message ""))
	  (t
	   (message "Making completion list...")
	   (with-output-to-temp-buffer "*Completions*"
	     (display-completion-list
	      (all-completions pattern alist)))
	   (message "Making completion list...%s" "done")))))

;; (define-key ruby-mode-map "\M-\C-i" 'jct-complete-symbol)

(defun jct-debuglog (logmsg)
  "if `jct-debug' is non-nil, output LOGMSG into *Messages*. Returns LOGMSG."
  (if jct-debug
      (message "%s" logmsg))
  logmsg)

(defun jct-exec-and-eval (command opt)
  "Execute jct-complete/jct-doc and evaluate the output."
  (let ((eval-buffer  (get-buffer-create " *jct-eval*")))
    ;; copy to temporary buffer to do completion at non-EOL.
    (jct-shell-command
     (format "%s %s %s --line=%d --column=%d %s"
             command opt (or jct-option-local "")
             (jct-current-line)
             ;; specify column in BYTE
             (string-bytes
              (encode-coding-string
               (buffer-substring (point-at-bol) (point))
               buffer-file-coding-system))
             (if jct-use-test-script (jct-test-script-option-string) ""))
     eval-buffer)
    (message "")
    (eval (with-current-buffer eval-buffer
            (goto-char 1)
            (unwind-protect
                (read (current-buffer))
              (unless jct-debug (kill-buffer eval-buffer)))))))

(defun jct-test-script-option-string ()
  (if (null buffer-file-name)
      ""
    (let ((test-buf (jct-find-test-script-buffer))
          (bfn buffer-file-name)
          bfn2 t-opt test-filename)
      (if (and test-buf
               (setq bfn2 (buffer-local-value 'buffer-file-name test-buf))
               (file-exists-p bfn2))
          ;; pass test script's filename and lineno
          (with-current-buffer test-buf
            (setq t-opt (format "%s@%s" buffer-file-name (jct-current-line)))
            (format "-t %s --filename=%s" t-opt bfn))
        ""))))

(require 'cl)

(defun jct-find-test-script-buffer (&optional buffer-list)
  "Find the latest used Ruby test script buffer."
  (setq buffer-list (or buffer-list (buffer-list)))
  (dolist (buf buffer-list)
    (with-current-buffer buf
      (if (and buffer-file-name (string-match "test.*\.rb$" buffer-file-name))
          (return buf)))))

;; (defun jct-find-test-method (buffer)
;;   "Find test method on point on BUFFER."
;;   (with-current-buffer buffer
;;     (save-excursion
;;       (forward-line 1)
;;       (if (re-search-backward "^ *def *\\(test_[A-Za-z0-9?!_]+\\)" nil t)
;;           (match-string 1)))))

(defun jct-try-completion ()
  "Evaluate the output of jct-complete."
  (jct-exec-and-eval jct-complete-command-name "--completion-emacs"))

;;;; TAGS or Ri
(autoload 'ri "ri-ruby" nil t)
(defvar jct-find-tag-if-available t
  "If non-nil and the method location is in TAGS, go to the location instead of show documentation.")
(defun jct-ri (&optional option)
  "Browse Ri document at the point.
If `jct-find-tag-if-available' is non-nil, search the definition using TAGS.

See also `jct-interactive'. "
  (interactive (jct-interactive))
  (jct-exec-and-eval
   jct-doc-command-name
   (concat "--ri-emacs --use-method-analyzer "
           (if (buffer-file-name)
               (concat "--filename=" (buffer-file-name))
             ""))))

(defun jct-find-tag-or-ri (fullname)
  (if (not jct-find-tag-if-available)
      (ri fullname)
    (condition-case err
        (let ()
          (visit-tags-table-buffer)
          (find-tag-in-order (concat "::" fullname) 'search-forward '(tag-exact-match-p) nil  "containing" t))
      (error
       (ri fullname)))))

;;;; toggle buffer
(defun js-toggle-buffer ()
  "Open a related file to the current buffer. test<=>impl."
  (interactive)
  (find-file (shell-command-to-string
              (format "%s %s" ruby-toggle-file-command-name buffer-file-name))))

;;;; jct-fork support
(defun jct-fork (options)
  "Run jct-fork.
Jct-fork makes xmpfilter and completion MUCH FASTER because it pre-loads heavy libraries.
When jct-fork is running, the mode-line indicates it to avoid unnecessary run.
To kill jct-fork process, use \\[jct-fork-kill].
"
  (interactive (list
                (read-string "jct-fork options (-e CODE -I LIBDIR -r LIB): "
                             (jct-fork-default-options))))
  (jct-fork-kill)
  (jct-fork-minor-mode 1)
  (start-process-shell-command
   "jct-fork" "*jct-fork*" jct-fork-command-name options))

(defun jct-fork-default-options ()
  "Default options for jct-fork by collecting requires."
  (mapconcat
   (lambda (lib) (format "-r %s" lib))
   (save-excursion
     (goto-char (point-min))
     (loop while (re-search-forward "\\<require\\> ['\"]\\([^'\"]+\\)['\"]" nil t)
           collect (match-string-no-properties 1)))
   " "))

(defun jct-fork-kill ()
  "Kill jct-fork process invoked by \\[jct-fork]."
  (interactive)
  (when jct-fork-minor-mode
    (jct-fork-minor-mode -1)
    (interrupt-process "jct-fork")))
(define-minor-mode jct-fork-minor-mode
  "This minor mode is turned on when jct-fork is run.
It is nothing but an indicator."
  :lighter " <jct-fork>" :global t)

;;;; unit tests
(when (and (fboundp 'expectations))
  (require 'ruby-mode)
  (require 'el-mock nil t)
  (expectations
    (desc "comment-dwim advice")
    (expect "# =>"
      (with-temp-buffer
        (ruby-mode)
        (setq last-command nil)
        (call-interactively 'comment-dwim)
        (setq last-command 'comment-dwim)
        (call-interactively 'comment-dwim)
        (buffer-string)))
    (expect (regexp "^1 +# =>")
      (with-temp-buffer
        (ruby-mode)
        (insert "1")
        (setq last-command nil)
        (call-interactively 'comment-dwim)
        (setq last-command 'comment-dwim)
        (call-interactively 'comment-dwim)
        (buffer-string)))

    (desc "jct-current-line")
    (expect 1
      (with-temp-buffer
        (jct-current-line)))
    (expect 1
      (with-temp-buffer
        (insert "1")
        (jct-current-line)))
    (expect 2
      (with-temp-buffer
        (insert "1\n")
        (jct-current-line)))
    (expect 2
      (with-temp-buffer
        (insert "1\n2")
        (jct-current-line)))

    (desc "jct-save-position")
    (expect (mock (set-window-start * 7) => nil)
      (stub window-start => 7)
      (with-temp-buffer
        (insert "abcdef\nghi")
        (jct-save-position #'ignore)))
    (expect 2
      (with-temp-buffer
        (stub window-start => 1)
        (stub set-window-start => nil)
        (insert "abcdef\nghi")
        (jct-save-position #'ignore)
        (jct-current-line)))
    (expect 3
      (with-temp-buffer
        (stub window-start => 1)
        (stub set-window-start => nil)
        (insert "abcdef\nghi")
        (jct-save-position #'ignore)
        (current-column)))

    (desc "jct-interactive")
    (expect '("read")
      (let ((current-prefix-arg t))
        (stub read-from-minibuffer => "read")
        (jct-interactive)))
    (expect '("-S ruby19")
      (let ((current-prefix-arg nil)
            (jct-option-local "-S ruby19"))
        (stub read-from-minibuffer => "read")
        (jct-interactive)))
    (expect '("")
      (let ((current-prefix-arg nil)
            (jct-option-local))
        (stub read-from-minibuffer => "read")
        (jct-interactive)))

    (desc "jct-shell-command")
    (expect "1+1 # => 2\n"
      (with-temp-buffer
        (insert "1+1 # =>\n")
        (jct-shell-command "xmpfilter")
        (buffer-string)))

    (desc "xmp")

    (desc "xmpfilter-command")
    (expect "xmpfilter --rails"
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "class TestFoo < Test::Unit::TestCase\n")
          (xmpfilter-command "--rails"))))
    (expect "xmpfilter "
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "context 'foo' do\n")
          (xmpfilter-command))))
    (expect "xmpfilter "
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "describe Array do\n")
          (xmpfilter-command))))
    (expect "xmpfilter --unittest --rails"
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "class TestFoo < Test::Unit::TestCase\n"
                  "  def test_0\n"
                  "    1 + 1 # =>\n"
                  "  end\n"
                  "end\n")
          (xmpfilter-command "--rails"))))
    (expect "xmpfilter --spec "
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "context 'foo' do\n"
                  "  specify \"foo\" do\n"
                  "    1 + 1 # =>\n"
                  "  end\n"
                  "end\n")
          (xmpfilter-command))))
    (expect "xmpfilter --spec "
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "describe Array do\n"
                  "  it \"foo\" do\n"
                  "    [1] + [1] # =>\n"
                  "  end\n"
                  "end\n")
          (xmpfilter-command))))
    (expect "xmpfilter "
      (let ((xmpfilter-command-name "xmpfilter"))
        (with-temp-buffer
          (insert "1 + 2\n")
          (xmpfilter-command))))

    (desc "jct-fork")
    (expect t
      (stub start-process-shell-command => t)
      (stub interrupt-process => t)
      (jct-fork "-r activesupport")
      jct-fork-minor-mode)
    (expect nil
      (stub start-process-shell-command => t)
      (stub interrupt-process => t)
      (jct-fork "-r activesupport")
      (jct-fork-kill)
      jct-fork-minor-mode)
    ))

(provide 'jcodetools)
