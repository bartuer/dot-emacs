(defun sql-to-orgtbl ()
  (interactive)
  (message "has insert select clause at end of sql-mode buffer?")
  (with-current-buffer (get-buffer-create "*sql2orgtbl*")
    (kill-region (point-min) (point-max)))
  (shell-command-on-region (point-min) (point-max) "rm -f /tmp/sqlite-org-convert.db && sqlite3 -csv /tmp/sqlite-org-convert.db"
                           "*sql2orgtbl*" nil (get-buffer-create "*sql2orgtbl-error"))
  (with-current-buffer "*sql2orgtbl*"
    (org-table-convert-region (point-min) (point-max) '(4))
    (org-mode)
    (goto-char (point-min)))
  (pop-to-buffer "*sql2orgtbl*")
  )

(defun connect-sqlite-i-buffer ()
  (interactive)
  (sql-sqlite)
  (sql-set-sqli-buffer-generally)
  )

(defun sql-send-buffer-dwim ()
  (interactive)
  (if (buffer-live-p sql-buffer)
      (sql-send-buffer)
    (shell-command-on-region (point-min) (point-max)
                             (concat "sqlite3 "
                                     (replace-regexp-in-string "sql" "db" (buffer-file-name)))))
  )

(defun bartuer-sql-load ()
  "for sql mode"
  (define-key sql-mode-map "\C-c\C-s" 'connect-sqlite-i-buffer)
  (define-key sql-mode-map "\C-c\C-e" 'sql-send-string)
  (define-key sql-mode-map "\C-c\C-t" 'sql-to-orgtbl)
  (define-key sql-mode-map "\C-c\C-b" 'sql-send-buffer-dwim))

