(defun connect-sqlite-i-buffer ()
  (interactive)
  (sql-sqlite)
  (sql-set-sqli-buffer-generally)
)

(defun bartuer-sql-load ()
  "for sql mode"
  (define-key sql-mode-map "\C-c\C-s" 'connect-sqlite-i-buffer)
  (define-key sql-mode-map "\C-c\C-e" 'sql-send-string)
  )
