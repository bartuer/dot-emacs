;;; jcodetools.el -- annotation / accurate completion / browsing documentation

;;; steel it from:
;;; Copyright (c) 2006-2008 rubikitch <rubikitch@ruby-lang.org> 
;;;
;;; see rcodetool at http://rubyforge.org/projects/rcodetools


(defvar jxmpfilter-command-name "ruby -S jxmpfilter "
  "The xmpfilter command name.")
(defvar jct-complete-command-name "ruby -S jxmpfilter --completion  "
  "The jct-complete command name.")
(defvar jct-option-history nil)
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

(defun jct-debuglog (logmsg)
  "if `jct-debug' is non-nil, output LOGMSG into *Messages*. Returns LOGMSG."
  (if jct-debug
      (message "%s" logmsg))
  logmsg)

(defun jct-shell-command (command &optional buffer)
  "Replacement for `(shell-command-on-region (point-min) (point-max) command buffer t' because of encoding problem."
  (let ((input-js (concat (make-temp-name "jxmptmp-in") ".js"))
        (output-js (concat (make-temp-name "jxmptmp-out") ".js"))
        (coding-system-for-read buffer-file-coding-system))
    (write-region (point-min) (point-max) input-js nil 'nodisp)
;;;     (message (format "invoke debugger like this:\n%s --dump=/tmp/jct_filter_debug copy.js\nset break (link \"~/etc/el/jcodetools/lib/jcodetools/xmpfilter.rb\" 3190) get annotated code or see dump, then invoke \nrhino -f dumped_code.js" command))
    (shell-command
     (jct-debuglog (format "%s %s > %s" command input-js output-js))
     t "*jct-error*")
    (with-current-buffer (or buffer (current-buffer))
      (insert-file-contents output-js nil nil nil t))
    (delete-file input-js)
    (delete-file output-js)))

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

(provide 'jcodetools)
