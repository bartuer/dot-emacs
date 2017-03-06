(require 'lua-mode nil t)

(defun bartuer-lua-load ()
  "for lua languaage"
  (interactive)
  (add-hook 'before-save-hook (lambda ()
                                (indent-region (point-min) (point-max))))
  )

(provide 'bartuer-lua)