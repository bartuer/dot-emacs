(require 'ruby-compilation)

(defun pcmpl-gem-commands ()
  "Return a list of all the gem commands"
  (delq nil
        (mapcar '(lambda(line)
                   (if (string-match "^    \\([a-z_]+\\).*$" line) (match-string 1 line)))
                (split-string (shell-command-to-string "gem help commands") "[\n]"))))

(defun ruby-compilation-gem (&optional edit task env-vars)
  "Run a gem process dumping output to a ruby compilation buffer."
  (interactive "P")
  (let* ((task (concat
		(or task (if (stringp edit) edit)
		    (completing-read "Gem: " (pcmpl-gem-commands)))
		" "
		(mapconcat (lambda (pair)
			     (format "%s=%s" (car pair) (cdr pair)))
			   env-vars " ")))
	 (gem-args
          ((lambda (command)
             (pop-to-buffer
              (concat "gem help "
                      ((lambda  (s)
                         "Remove whitespace at beginning and end of string."
                         (if (string-match "\\`[ \t\n\r]+" s) (setq s (replace-match "" t t s)))
                         (if (string-match "[ \t\n\r]+\\'" s) (setq s (replace-match "" t t s)))
                         s) command)))
             (read-from-minibuffer "Edit Gem Command: " (concat task " "))) task)))
    (pop-to-buffer (ruby-compilation-do
                    "gem" (cons "gem"
                                (split-string gem-args))))))


(defun bartuer-gem (&optional task edit-cmd-args)
  "issue gem command, see help from completion and icicle's
candidate help, get result from ruby compilation mode"
  (interactive "P")
  (ruby-compilation-gem task edit-cmd-args
			(if rinari-rails-env (list (cons "RAILS_ENV" rinari-rails-env)))))


(defadvice bartuer-gem (before icicle-gem-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn
        (lambda  (entry)
          "return the gem commands documents of entry"
          (let ((item (widget-princ-to-string entry)))
            (with-output-to-temp-buffer (format "gem help %s" item)
              (princ (shell-command-to-string (concat "gem help " item))))))))

(defun pcmpl-mongrel-commands ()
  "Return a list of all the mongrel commands"
  (delq nil
        (mapcar '(lambda(line)
                   (if (string-match "^ - \\([a-z:]+\\).*$" line) (match-string 1 line)))
                (split-string (shell-command-to-string "mongrel_rails") "[\n]"))))

(defun ruby-compilation-mongrel (&optional edit task env-vars)
  "Run a mongrel process dumping output to a ruby compilation buffer."
  (interactive "P")
  (let* ((task (concat
		(or task (if (stringp edit) edit)
		    (completing-read "Mongrel: " (pcmpl-mongrel-commands)))
		" "
		(mapconcat (lambda (pair)
			     (format "%s=%s" (car pair) (cdr pair)))
			   env-vars " ")))
	 (mongrel-args
          ((lambda (command)
             (pop-to-buffer
              (concat "mongrel help "
                      ((lambda  (s)
                         "Remove whitespace at beginning and end of string."
                         (if (string-match "\\`[ \t\n\r]+" s) (setq s (replace-match "" t t s)))
                         (if (string-match "[ \t\n\r]+\\'" s) (setq s (replace-match "" t t s)))
                         s) command)))
             (read-from-minibuffer "Edit Mongrel Command: " (concat task " "))) task)))
    (pop-to-buffer (ruby-compilation-do
                    "mongrel" (cons "mongrel_rails"
                                (split-string mongrel-args))))))


(defun bartuer-mongrel (&optional task edit-cmd-args)
  "issue mongrel command, see help from completion and icicle's
candidate help, get result from ruby compilation mode"
  (interactive "P")
  (ruby-compilation-mongrel task edit-cmd-args
			(if rinari-rails-env (list (cons "RAILS_ENV" rinari-rails-env)))))


(defadvice bartuer-mongrel (before icicle-mongrel-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn
        (lambda  (entry)
          "return the mongrel commands documents of entry"
          (let ((item (widget-princ-to-string entry)))
            (with-output-to-temp-buffer (format "mongrel help %s" item)
              (princ (shell-command-to-string (concat "mongrel_rails " item " -h"))))))))

(provide 'bartuer-gem)