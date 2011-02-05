(setq erlang-skel nil)
(require 'erlang nil t)
(require 'erlang-start nil t)
(require 'distel nil t)
(distel-setup)

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