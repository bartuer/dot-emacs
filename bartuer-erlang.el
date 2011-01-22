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
  (flymake-mode t)
  )


(provide 'bartuer-erlang)