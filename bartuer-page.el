(defun page-reload ()
  (shell-command "~/scripts/update_cache_manifest")
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



(defun page-reload-save ()
  (interactive)
  (shell-command "~/scripts/update_cache_manifest")
  (unless (buffer-modified-p)
    (shell-command (concat
                    "push "
                    "'window.location.reload(true)'") nil))
  (save-buffer))

(define-minor-mode reload-mode
  "Minor mode to reload browser"
  :lighter reload-minor-mode-string
  (cond
   (reload-mode
    (add-hook 'after-save-hook 'page-reload t t)
    (define-key global-map "\C-\M-j" 'page-reload-save)
    )
   (t
    (remove-hook 'after-save-hook 'page-reload t)
    (define-key global-map "\C-\M-j" 'save-buffer)
    ))
  )

(defalias  're (lambda () (interactive)
                 (reload-mode)))

(provide 'bartuer-page)