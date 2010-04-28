(defun page-reload ()
  (unless (eq 0 (shell-command (concat
                                "push "
                                "'window.location.reload(true)'") nil))
    (message "update failed")
    )
  )

(defcustom reload-minor-mode-string " Reload"
  "String to display in mode line when reload mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  )

(define-minor-mode reload-mode
  "Minor mode to reload browser"
  :lighter reload-minor-mode-string
  (cond
   (reload-mode
    (add-hook 'after-save-hook 'page-reload nil t)
    )
   (t
    (remove-hook 'after-save-hook 'page-reload t)))
  )

(defalias  're (lambda () (interactive)
                 (reload-mode)))

(provide 'bartuer-page)