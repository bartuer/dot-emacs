(defun wiki-this ()
  "Ask wikipedia for the definition of a word.
borrowed from google-define.el"
  (interactive)
  (let* ((search-word
          (read-from-minibuffer
           "wiki: "
           (thing-at-point 'word)))
         )
    (message (shell-command-to-string (concat "wiki " search-word)))
    ))
(defalias 'wk 'wiki-this)

(defun fast-wiki ()
  (let ((word (thing-at-point 'word)))
        (when word
          (message (shell-command-to-string (concat "wiki " word))))))

(defcustom fast-wiki-minor-mode-string " wk" 
  "String to display in mode line when fast-wiki mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  )

(define-minor-mode fast-wiki-minor-mode
  "Minor mode query word under cursor from wikipedia"
  :lighter fast-wiki-minor-mode-string
  (cond
   (fast-wiki-minor-mode
    (add-hook 'post-command-hook 'fast-wiki nil t)
    )
   (t
    (remove-hook 'post-command-hook 'fast-wiki t)
  )))

(provide 'fast-wiki)