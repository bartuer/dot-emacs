(defun buddy-get (word)
  "show definition of word from buddy system"
  (let* ((buf (current-buffer))
         (defination (concat  "buddy-" word))
         (process (apply 'start-process-shell-command
                         defination
                         (get-buffer-create defination)
                         "word-define"
                         (list word)))
         )
    (setq buddy-jump-back-buf buf)
    (set-process-sentinel process (lambda (proc state)
                                    (cond ((equal state "finished
")
                                           (let ((defination-buf (process-buffer proc)))
                                             (with-current-buffer defination-buf
                                               (goto-char (point-min))
                                               (pop-to-buffer defination-buf)
                                               (pop-to-buffer buddy-jump-back-buf)
                                               )    
                                             )
                                           
                                           )
                                          )
                                    ))
    defination
    ))

(defun explain-current-in-brower ()
  (interactive)
  (let ((w (thing-at-point 'word))
         )
    (buddy-get w)
    )
  )

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