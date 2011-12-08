(defun bartuer-csv-load ()
  (interactive)
  (convert-csv-to-org-table)
  (orgtbl-mode t)
  )

(defun switch-to-dbview ()
  "convert file to sqlite and change to dbview buffer"
  (interactive)
  (save-buffer)
  (convert-csv-to-sqlite3 (buffer-file-name))
  (let* ((table_name
         (file-name-sans-extension
          (file-name-nondirectory
           (buffer-file-name))))
         (database_name (concat table_name ".db"))
         (view_name (concat table_name ".view")))
    (convert-sqlite3-to-org-table-annoted-by-record-list database_name)
    (pop-to-buffer view_name))
  )

(defvar csv-mode-map
  (let ((map (make-keymap)))
    (define-key map "\C-j" 'switch-to-dbview)
    map)
  "mode map for csv-mode"
  )

(defun csv-mode-before-save ()
  "if there is db backend, save through it, if not, save directly"
  (interactive)
  (let* ((table_name
          (file-name-sans-extension
           (file-name-nondirectory
            (buffer-file-name))))
         (database_name
          (concat
           (file-name-directory
            (buffer-file-name))
            table_name ".db"))
         )
    ;; maybe modified both in view and csv buffer, how to resolve conflict ?
    ;; should save through when save db
    (if (file-exists-p
         database_name)   
        (convert-sqlite3-to-csv
         database_name)
      (progn
        (goto-char (point-min))      
        (convert-org-table-to-csv)
        )
      )
    )
  )

(defun csv-mode ()
  "Major mode for csv"
  (interactive)
  (kill-all-local-variables)
  (add-hook 'before-save-hook 'csv-mode-before-save nil t)
  (setq mode-name "csv")
  (use-local-map csv-mode-map)
  (run-hooks 'csv-mode-hook))

(provide 'csv-mode)