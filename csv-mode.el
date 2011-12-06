(defun bartuer-csv-load ()
  (interactive)
  (convert-csv-to-org-table)
  (orgtbl-mode t)
  )

(defun csv-mode ()
  "Major mode for csv"
  (interactive)
  (kill-all-local-variables)
  (add-hook 'before-save-hook 'convert-org-table-to-csv nil t)
  (setq mode-name "csv")
  (run-hooks 'csv-mode-hook))

(provide 'csv-mode)