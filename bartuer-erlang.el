(setq erlang-skel nil)
(require 'erlang nil t)
(require 'erlang-start nil t)
(require 'distel nil t)
(distel-setup)

(eval-and-compile
  (defconst erlang-block-keyword-regexp "[ (\[{]\\(begin\\|case\\|fun *(\\|if\\|end\\|receive\\|try\\)"
    ))

(eval-and-compile
  (defconst erlang-block-beg-regexp "\\(begin\\|case\\|fun\\|if\\|end\\|receive\\|try\\)"
    ))

(eval-and-compile
  (defconst erlang-pattern-match-end-regexp "[a-zA-Z0-9_-]"
    ))

(defun erlang-current-function-beg ()
  "get current function beginning position"
  (save-excursion
    (erlang-beginning-of-function)
    (point)
    )
  )

(defun erlang-current-function-end ()
  "get current function end position"
  (save-excursion
    (erlang-end-of-function)
    (point)
    )
  )

(defun erlang-at-comment-p ()
  "current point in a comment?"
  (let* ((from (point))
         (bol (save-excursion
                (beginning-of-line)
                (point)))
         (in-comment (search-backward-regexp "% " bol t)))
    (goto-char from)
    (integerp in-comment))
  )

(defun erlang-at-string-p ()
  "current point in a string?"
  (let* ((from (point))
         (bol (save-excursion
                (beginning-of-line)
                (point)))
         (eol (save-excursion
                (end-of-line)
                (point)))
         (string-head (search-backward-regexp "['\"]" bol t))
         (string-tail (progn
                        (goto-char from)
                        (search-forward-regexp "['\"]" eol t)
                        )))
    (goto-char from)
    (and (integerp string-head)
         (integerp string-tail)))
  )

(defun erlang-word-at-point ()
  "return erlang block keyword under point"
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (if bounds
          (buffer-substring-no-properties (car bounds) (cdr bounds))))
    )

(defun erlang-skip-blank-and-brace ()
  "backward search and find a keyword, remove outer brace at the point"
  (erlang-skip-blank)
  (when (or
         (= (following-char) 91)             ;[
         (= (following-char) 40)             ;(
         (= (following-char) 123)            ;{
         )
    (forward-char 1))
  )

(defun erlang-backdelete-invoke-brace ()
  "forward search and find a fun keyword, back delete invoke part"
  (when (= (following-char) 40)         ;(
    (backward-char)
    (while (= (following-char) 32)      ;SPACE
      (backward-char)))
  )

(defun erlang-find-block-keyword (&optional direct)
  "direct, if set, will search backward"
  (interactive)
  (setq case-setting case-fold-search)
  (setq case-fold-search nil)
  (let ((beg (point))
        (end (save-excursion
               (if direct
                   (search-backward-regexp erlang-block-keyword-regexp)
                 (search-forward-regexp erlang-block-keyword-regexp))
               (while (or
                       (erlang-at-comment-p)
                       (erlang-at-string-p)
                       )
                 (if direct
                     (search-backward-regexp erlang-block-keyword-regexp)
                   (search-forward-regexp erlang-block-keyword-regexp)))
               (if direct
                   (erlang-skip-blank-and-brace)
                 (erlang-backdelete-invoke-brace))
               (point)
               )))
    (goto-char end))
  (setq case-fold-search case-setting)
  )

(defun erlang-find-block-beg ()
  "return begin of most inner block include current position"
  (setq erlang-current-block-beg nil)
  (let ((fun-beg (erlang-current-function-beg)))
    (save-excursion
      (let ((stack nil))
        (while (and (null erlang-current-block-beg)
                    (> (point) fun-beg))
          (erlang-find-block-keyword t)
          (if (string-equal "end" (erlang-word-at-point))
              (erlang-push (erlang-word-at-point) stack)
            (if (null stack)
                (setq erlang-current-block-beg (point))
              (erlang-pop stack))
            ))
        )))
  erlang-current-block-beg)

(defun erlang-find-block-end ()
  "return end of most inner block include current position"
  (setq erlang-current-block-end nil)
  (let ((fun-end (erlang-current-function-end)))
    (save-excursion
      (when erlang-current-block-beg
        (goto-char erlang-current-block-beg)
        (let ((stack nil))
          (while (and (null erlang-current-block-end)
                      (< (point) fun-end))
            (erlang-find-block-keyword)
            (if (string-equal "end" (erlang-word-at-point))
                (if (null stack)
                    (setq erlang-current-block-end (point))
                  (erlang-pop stack))
              (erlang-push (erlang-word-at-point) stack)
              ))
          )
        )))
  erlang-current-block-end)

(defun erlang-mark-block ()
  "mark most inner block include current position"
  (interactive)
  (let ((beg (erlang-find-block-beg))
        (end (erlang-find-block-end)))
    (when (and beg end)
      (set-mark end)
      (goto-char beg)
      ))
  )

(defun erlang-find-pattern-match-beg ()
  "return begin of most meaningful pattern matching include(or behind) current position"
  (setq current-pattern-match-point nil)
  (save-excursion 
    (let ((fun-head
           (save-excursion (erlang-beginning-of-function 1)
                           (point)))
          (bol (save-excursion (beginning-of-line)
                               (point))))
      (end-of-line)
      (search-backward-regexp " ->" fun-head)
      (setq current-pattern-match-point (point))
      )
    (backward-sexp)
    (setq erlang-pattern-match-beg (point)))
  erlang-pattern-match-beg
  )

(defun erlang-pattern-match-data-end-p ()
  "left of current position is atom/var/number/macro?
see `erlang-pattern-match-end-regexp' "
  (let ((word-at-point (erlang-word-at-point)))
    (if (null word-at-point)
        nil 
      (and (stringp word-at-point)
           (eq (string-match
                erlang-pattern-match-end-regexp word-at-point
                ) 0)))))

;;; cases covered
;;; YES cases
;; atom    end.
;;         end;
;;         end
;; var     Error.
;;         Error;
;;         Error
;; number  0.
;;         1;
;;         19
;; macro   ?MAX_INT.
;;         ?MAX_INT;
;;         ?MAX_INT
;; list    [].
;;         [];
;;         []
;; tuple   {}.
;;         {};
;;         {}
;; call    ().
;;         ();
;;         ()
;; string  "".
;;         "";
;;         ""
;;         ''.
;;         '';
;;         ''
;;; NO cases
;; not end (end.)
;; ,       end,
(defun erlang-pattern-match-end-p ()
  "current position at pattern match end?"
  (setq erlang-current-at-pattern-match-end nil) 
  (let* ((char-at-point (following-char))
         (maybe-end (or
                     (and
                      (= (save-excursion
                           (forward-char)
                           (following-char))
                         10)
                      (= char-at-point 46)) ;.
                     (and
                      (= (save-excursion
                           (forward-char)
                           (following-char))
                         10)
                      (= char-at-point 59)) ;;
                     (= char-at-point 10) ;\n
                     )
                    ))
    (if maybe-end
        (let* ((word-like-list (save-excursion
                                 (backward-char)
                                 (= (following-char) 93) ;]
                                 ))
               (word-like-tuple (save-excursion
                                  (backward-char)
                                  (= (following-char) 125) ;}
                                  ))
               (word-like-call (save-excursion
                                 (backward-char)
                                 (= (following-char) 41) ;)
                                 ))
               (word-like-string (save-excursion
                                   (backward-char)
                                   (or 
                                    (= (following-char) 34)       ;"
                                    (= (following-char) 39))      ;'
                                   ))
               ;; var, atom, number, macro
               (word-like-data (erlang-pattern-match-data-end-p))
               )
          (setq erlang-current-at-pattern-match-end (or
                                                     word-like-list
                                                     word-like-tuple
                                                     word-like-call
                                                     word-like-string
                                                     word-like-data
                                                     )))
      (setq erlang-current-at-pattern-match-end nil)
      )
    )
  erlang-current-at-pattern-match-end
  )

(defun erlang-at-block-beg-p ()
  "current position just behind block begin keyword?"
  (let ((word-at-point (erlang-word-at-point)))
    (if (null word-at-point)
        nil
      (and (stringp word-at-point)
           (eq 0
               (string-match
                erlang-block-beg-regexp
                word-at-point))
           (not (string-equal "Fun" word-at-point)))))
  )

(defun erlang-find-pattern-match-end ()
  "return end of most meaningful pattern match include(or behind) current position"
  (setq erlang-pattern-match-end nil)
  (let ((fun-end (erlang-current-function-end)))
    (save-excursion
      (when current-pattern-match-point
        (goto-char current-pattern-match-point)
        (while (and (not (erlang-pattern-match-end-p))
                    (< (point) fun-end)) 
          (forward-sexp)
          (when (erlang-at-block-beg-p)
            (goto-char (erlang-find-block-beg))
            (goto-char (erlang-find-block-end))
            )
          )
        (setq erlang-pattern-match-end (point))
        )))
  erlang-pattern-match-end
  )

(defun erlang-mark-pattern-match ()
  "mark current pattern match"
  (interactive)
  (let ((beg (erlang-find-pattern-match-beg))
        (end (erlang-find-pattern-match-end)))
    (when (and beg end)
      (set-mark end)
      (goto-char beg)
      )
    )
  )


(defun erlang-mark-sexp ()
  "select most inner pattern match expression or block to mark"
  (interactive)
  (let ((block-beg (erlang-find-block-beg))
        (block-end (erlang-find-block-end))
        (pattern-beg (erlang-find-pattern-match-beg))
        (pattern-end (erlang-find-pattern-match-end)))
    (cond
     ((or (and block-beg
               block-end
               (null pattern-beg)
               (null pattern-end))
          (and (< block-beg (point))
               (> block-end (point))
               (or (> pattern-beg (point))
                   (< pattern-end (point))))) ; block only
      (erlang-mark-block)
      )
     ((or (and pattern-beg
               pattern-end
               (null block-beg)
               (null block-end))
          (and (< pattern-beg (point))
               (> pattern-end (point))
               (or (> block-beg (point))
                   (< block-end (point))))) ; pattern match only
      (erlang-mark-pattern-match))
     ((and (null block-beg)
           (null block-end)
           (null pattern-beg)
           (null pattern-end))
      (message "can not find anything to mark; point: %d block: (%d, %d) pattern matching: (%d, %d)"
               (point) block-beg block-end pattern-beg pattern-end))
     ((and (<= block-beg pattern-beg)
           (>= block-end pattern-end)) ; mark pattern first, second, outer block, third, outer pattern...
      (if (and mark-active
               (= (point) pattern-beg))
          (erlang-mark-block)
        (erlang-mark-pattern-match)))
     ((and (<= pattern-beg block-beg)
           (>= pattern-end block-end)) ; press mark binding again will automatically mark outer pattern match
      erlang-mark-block)
     (t
      (message "point: %d block: (%d, %d) pattern matching: (%d, %d)"
               (point) block-beg block-end pattern-beg pattern-end)))
    )
  )

(defun erlang-forward-sexp ()
  "pick suitable unit from sexp, block and pattern matching, forward to end"
  (interactive)
  (cond
   ((erlang-at-block-beg-p)
    (forward-sexp)
    (let ((block-beg (erlang-find-block-beg))
          (block-end (erlang-find-block-end))
          )
      (goto-char block-end))
    ) 
   ((= (point) (erlang-find-pattern-match-beg))
    (goto-char (erlang-find-pattern-match-end))
    )
   (t
    (forward-sexp)))
  )

(defun erlang-backward-sexp ()
  "pick suitable unit from sexp, block and pattern matching, backward to beginning"
  (interactive)
  (cond
   ((string-equal "end" (erlang-word-at-point))
    (backward-sexp)
    (let ((block-beg (erlang-find-block-beg))
          (block-end (erlang-find-block-end))
          )
      (goto-char block-beg))
    ) 
   ((erlang-pattern-match-end-p)
    (backward-char)
    (let ((pattern-beg (erlang-find-pattern-match-beg))
          (pattern-end (erlang-find-pattern-match-end)))
      (goto-char pattern-beg)
      )
    )
   (t
    (backward-sexp)))
  )

(defun erlang-backward-up-list ()
  (interactive)
  )

(defun has-ect-in-region-p (beg end)
  "search %# => in region beg end
"
  (goto-char beg)
  (if (search-forward-regexp "%#=>" end t)
      t
    nil)
  )

(defun ect-dwim ()
  "if there is %# =>, remove it, otherwise insert it

2 + 3 %
docstring as fixture, try above line.
"
  (setq current-pos (point))
  (setq beg (progn (beginning-of-line) (point)))
  (setq end (progn (end-of-line) (point)))
  (if (has-ect-in-region-p beg end)
      (progn
        (goto-char beg)
        (search-forward "%")
        (backward-char)
        (kill-line))
    (goto-char current-pos)
    (insert "#=>"))
  )

(defadvice comment-dwim (around jct-hack activate)
  "If comment-dwim is successively called, add //#=> mark."
  (if (and (eq major-mode 'erlang-mode)
           (eq last-command 'comment-dwim)
           )
      (ect-dwim)
    ad-do-it))

(defun otp-grep (command-args)
  "Run grep over otp documents"
  (interactive
   (progn
     (grep-compute-defaults)
     (list (read-shell-command "grep otp docs: "
                               "find ~/local/share/doc/erlang/OTP13B04_TEXT -type f  |grep -vE \"BROWSE|TAGS|.svn|drw|Binary|.bzr|svn-base|*.pyc\" |xargs grep -niHE " 'grep-find-history))))
  (when command-args              
    (let ((null-device nil))		; see grep
      (grep command-args))))

(defun erl-choose-emacs-node ()
  "set default nodename emacs@bartuer ."
  (interactive)
  (let* ((nodename-string (if erl-nodename-cache
			      (symbol-name erl-nodename-cache)
			    nil))
	 (name-string "emacs@bartuer")
         (name (intern (if (string-match "@" name-string)
                           name-string
			 (concat name-string
				 "@" (erl-determine-hostname))))))
    (setq erl-nodename-cache name)
    (pushnew erl-nodename-cache erl-nodes) 
    (setq distel-modeline-node name-string)
    (force-mode-line-update))
  erl-nodename-cache)

(defun inferior-erlang-without-switch-buffer ()
  "Run an inferior Erlang.

This is just like running Erlang in a normal shell, except that
an Emacs buffer is used for input and output.
\\<comint-mode-map>
The command line history can be accessed with  \\[comint-previous-input]  and  \\[comint-next-input].
The history is saved between sessions.

Entry to this mode calls the functions in the variables
`comint-mode-hook' and `erlang-shell-mode-hook' with no arguments.

The following commands imitate the usual Unix interrupt and
editing control characters:
\\{erlang-shell-mode-map}"
  (interactive)
  (require 'comint)
  (let ((opts inferior-erlang-machine-options))
    (cond ((eq inferior-erlang-shell-type 'oldshell)
	   (setq opts (cons "-oldshell" opts)))
	  ((eq inferior-erlang-shell-type 'newshell)
	   (setq opts (append '("-newshell" "-env" "TERM" "vt100") opts))))
    (setq inferior-erlang-buffer
	  (apply 'make-comint
		 inferior-erlang-process-name inferior-erlang-machine
		 nil opts)))
  (setq inferior-erlang-process
	(get-buffer-process inferior-erlang-buffer))
  (if (> 21 erlang-emacs-major-version)	; funcalls to avoid compiler warnings
      (funcall (symbol-function 'set-process-query-on-exit-flag) 
	       inferior-erlang-process nil)
    (funcall (symbol-function 'process-kill-without-query) inferior-erlang-process))
  (with-current-buffer inferior-erlang-buffer

    (if (and (not (eq system-type 'windows-nt))
             (eq inferior-erlang-shell-type 'newshell))
        (setq comint-process-echoes t))
    ;; `rename-buffer' takes only one argument in Emacs 18.
    (condition-case nil
        (rename-buffer inferior-erlang-buffer-name t)
      (error (rename-buffer inferior-erlang-buffer-name)))
    (erlang-shell-mode))
  )

(defun start-default-emacs-node ()
  "start node for distel"
  (interactive)
  (if (null (inferior-erlang-running-p))
      (progn
        (inferior-erlang-without-switch-buffer) 
        (sleep-for 0.5)
        (erl-choose-emacs-node)
        (erl-ping erl-nodename-cache)
        )
    (erl-ping erl-nodename-cache))  
  )

(defun bartuer-erlang-load ()
  "for erlang language"
  (setq erlang-root-dir "/usr/local/otp")
  (setq inferior-erlang-machine-options '("-sname" "emacs"))
  (add-hook 'erlang-shell-mode-hook (lambda ()
                                      (define-key erlang-shell-mode-map "\C-\M-i" 'erl-complete)
                                      (define-key erlang-shell-mode-map "\M-." 'erl-find-source_under-point)
                                      (define-key erlang-shell-mode-map "\M-," 'erl-find-source_unwind)
                                      ))
  (define-key erlang-mode-map "\C-c\C-e" 'erl-eval-expression)
  (define-key erlang-mode-map "\C-c\C-i" 'erl-session-minor-mode)
  (define-key erlang-mode-map "\M-a" 'erlang-beginning-of-clause)
  (define-key erlang-mode-map "\M-e" 'erlang-end-of-clause)
  (define-key erlang-mode-map "\C-\M-f" 'erlang-forward-sexp)
  (define-key erlang-mode-map "\C-\M-b" 'erlang-backward-sexp)
  (define-key erlang-mode-map "\C-\M-u" 'backward-up-list)
  (define-key erlang-mode-map "\M-h" 'erlang-mark-sexp)
  (define-key erlang-mode-map "\M-q" (lambda ()
                                       (erlang-indent-function)
                                       (erlang-align-arrows)))
  (define-key erlang-mode-map "\C-\M-h" 'erlang-mark-function)
  (define-key erlang-mode-map "\C-\M-e" 'erlang-end-of-function)
  (define-key erlang-mode-map "\C-\M-a" 'erlang-beginning-of-function)
  (define-key erlang-mode-map "\M--" (lambda ()
                                       (interactive)
                                       (insert " -> ")) )

  (save-excursion
    (start-default-emacs-node)
    )
  (flymake-mode t)
  (sleep-for 0.5)
  (erl-ie-ensure-registered erl-nodename-cache)
  (erl-session-minor-mode t)
  )


(provide 'bartuer-erlang)