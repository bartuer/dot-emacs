(require 'go-mode nil t)
(require 'go-guru nil t)

(defun bartuer-go-load ()
  "for go languaage"
  (interactive)
  (add-hook 'before-save-hook (lambda ()
                                (when (eq major-mode 'go-mode)
                                  (indent-region (point-min) (point-max))
                                  )
                                ))
  )

(provide 'bartuer-go)