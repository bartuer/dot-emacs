(require 'lua-mode nil t)

(defun bartuer-lua-load ()
  "for lua languaage"
  (interactive)
  (add-hook 'before-save-hook (lambda ()
                                (when (eq major-mode 'lua-mode)
                                  (indent-region (point-min) (point-max))
                                  )
                                ))
  )

(provide 'bartuer-lua)