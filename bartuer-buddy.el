(defun buddy-get (word)
  (let* ((timeout 8)
         (buf (current-buffer))
         )

    (unwind-protect
        (progn
          (shell-command  (concat "curl http://bartuer:3721/word/" word "  2>/dev/null|html2text -nobs -style pretty")
                          (get-buffer-create "html-text") (get-buffer "*Shell Command Output*"))
          (with-current-buffer "html-text"
            (goto-char (point-min))
            )
          (pop-to-buffer "html-text" )
          (pop-to-buffer buf)
          ))
    buf))

(defun explain-current-in-brower ()
  (interactive)
  (let ((w (thing-at-point 'word)))
    (buddy-get w)
    ))

(defalias 'bd 'explain-current-in-brower)

(defcustom buddy-minor-mode-string " bd" 
  "String to display in mode line when buddy mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  )

(define-minor-mode buddy-minor-mode
  "Minor mode query word under cursor from buddy"
  :lighter buddy-minor-mode-string
  (cond
   (buddy-minor-mode
    (add-hook 'post-command-hook 'explain-current-in-brower nil t)
    )
   (t
    (remove-hook 'post-command-hook 'explain-current-in-brower t)
  )))

  

(provide 'bartuer-buddy)