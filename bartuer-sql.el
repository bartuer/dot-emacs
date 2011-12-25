;;; need replace this version
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

(defun sqlite3-migrate-package (database_name)
  (let ((table_name (file-name-sans-extension (file-name-nondirectory database_name)))
        (dir (file-name-directory database_name)))
    (shell-command
     (message "%s" (format "echo '.dump' | sqlite3 %s | gzip -c > %s.sql.gz" database_name (concat dir table_name)))
     nil "*Messages*")
    )
  )

(defvar data-field-timestamp-regexp
  "[0-9]+?-[0-9]+?-[0-9]+ [A-Za-z]* \\([0-9]+\\:[0-9]+\\(:[0-9]+)*$\\)"
  "timestamp regexp"
  )

(defun convert-csv-to-sqlite3 (filename)
  (with-current-buffer (get-buffer-create (find-file filename))
    (let* ((table_name (file-name-sans-extension (file-name-nondirectory (buffer-file-name))))
           (database_name (concat table_name ".db"))
           (dir (file-name-directory filename))
           (head_line (save-excursion
                        (goto-char (point-min))
                        (buffer-substring-no-properties (save-excursion
                                                          (beginning-of-line 1) (point))
                                                        (save-excursion
                                                          (end-of-line) (point)))))
           (fields (nthcdr 0 (org-split-string head_line ",")))
           (first_data_line (save-excursion
                              (goto-line 2)
                              (buffer-substring-no-properties (save-excursion
                                                                (beginning-of-line 1) (point))
                                                              (save-excursion
                                                                (end-of-line) (point)))))
           (samples (nthcdr 0 (org-split-string first_data_line ",")))
           (schemas (mapcar (lambda (field_pair)
                              (let ((default "TEXT")
                                    (f (cdr field_pair))
                                    (n (car field_pair)))
                                (cond ((numberp (string-match ".*ID\\|_id\\|^id" (org-trim n)))
                                       (cons n "INTEGER PRIMARY KEY")
                                       )
                                      ((numberp (string-match org-table-number-regexp (org-trim f)))
                                       (cons n "NUMERIC")
                                       )
                                      ((numberp (string-match "<?xml\\|^{\\|^\\[\\|data:image/" (org-trim f))) 
                                       (cons n "BLOB")
                                       )
                                      (t
                                       (cons n default)
                                       ))
                                )
                              )
                            (mapcar (lambda (i)
                                      (cons (nth i fields)
                                            (nth i samples)
                                            )
                                      ) (number-sequence 0 (- (length fields) 1)))
                            ))
           (schema-str (let ((guess_result
                              (mapconcat
                               (lambda (entry)
                                 (concat (car entry) " " (cdr entry))
                                 ) schemas ",")))
                         (if (numberp (string-match ".*PRIMARY KEY" guess_result))
                             guess_result
                           (concat "id INTEGER PRIMARY KEY," guess_result))
                         )))
      (shell-command (message "echo drop table exit code %d; %s"
                              (shell-command (format "sqlite3 %s 'drop table %s;'" database_name table_name))
                              (format "sqlite3 %s 'create table %s(%s);'"
                                database_name table_name schema-str)
                      ))
      (goto-char (point-min))
      (forward-line)
      (let ((tmp (make-temp-file nil)))
        (write-region (point) (point-max) tmp)
        (shell-command
         (message (format "echo '.import %s %s' | sqlite3 -csv %s" tmp table_name (concat dir database_name))) nil "*Messages*")
        ))))

(defun convert-csv-to-org-lisp (&optional filename)
  (interactive)
  (with-current-buffer (find-file (if filename
                                      filename
                                    (buffer-file-name)))

    (save-excursion
      (goto-char (point-min))
      (org-table-convert-region (point-min) (point-max) '(4))
      (org-table-to-lisp)))
  )

(defun parse-schema (str)
  (let ((schemas_maybe_with_index
          (org-split-string
           str "CREATE INDEX"))
         )
    (mapcar
     (lambda (field)
       (let* ((name_and_type (org-split-string (org-trim field)  " "))
              (name (car name_and_type))
              (type (mapconcat (lambda (x) x) (cdr name_and_type) " "))
              )
         (cons name type)
         )
       )
     (progn
       (string-match "\\.*(\\(.*)\\)" (car schemas_maybe_with_index))
       (org-split-string
        (replace-regexp-in-string
         "`"
         ""
         (substring
          (match-string 0 (car schemas_maybe_with_index)) 1 -1)) ",")
       )
     )) 
  )


(defalias 'sql 'convert-sqlite3-to-org-table-annoted-by-record-list)

(defun sqlite3-inspect (&optional field)
  (interactive)
  (let* ((property_sym (if (equal (line-beginning-position) (org-table-begin))
                            'sqlite3-table-head
                          'sqlite3-db-record
                          ))
         (max_field_name (reduce 'max
                                 (mapcar 'length
                                         (mapcar 'car
                                                 (get-text-property
                                                  (line-beginning-position)
                                                  property_sym))))))
    
    (message "%s" (mapconcat (lambda (entry)
                               (format (concat  "%" (format "%d" max_field_name) "s : %s") (car entry) (cdr entry))
                               )
                             (get-text-property (line-beginning-position) property_sym) "\n"))  
    ))


(defun convert-csv-to-record-list (&optional filename query)
  (interactive "P")
  (setq convert-csv-where "")
  (let* ((query (if (or query (eq 4 (prefix-numeric-value filename)))
                         t
                       nil))
         (filename (if (stringp filename)
                       filename
                     (read-from-minibuffer "file : " (buffer-file-name))))
                  (table_name (file-name-sans-extension (file-name-nondirectory filename)))
         (database_name (concat table_name ".db"))
         (dir (file-name-directory filename))
         )
    (convert-csv-to-sqlite3 filename)
    (with-current-buffer
        (get-buffer-create (concat filename ".view"))
      (shell-command-on-region
       (point-min)
       (point-max)
       (message "%s" (concat (format "sqlite3 -line %s 'select %s from %s "
                                 (concat dir database_name)
                                 (if query
                                     (progn
                                       (setq convert-csv-where (read-from-minibuffer "where (field like \"%str\"): " ""))
                                       (read-from-minibuffer "select (fields seperate by ,) : " "*"))
                                   "*")
                                 table_name
                                 )
                        (if (string-equal convert-csv-where "")
                            ""
                          (concat "where " convert-csv-where) 
                          )
                        ";'")
                ) nil t)
      (let* ((beg (point-min))
             (end (point-max))
             (txt (buffer-substring-no-properties beg end))
             (paras (nthcdr 0 (org-split-string txt "\n\n")))
             (data_view (mapcar (lambda (para)
                  (let ((record (list))
                        (lines (org-split-string para "\n")))
                    (mapcar (lambda (line)
                              (when (string-match "\\([a-zA-Z0-9-_]+\\)\s=\s\\(.*\\)" line)
                                (push (cons (match-string-no-properties 1 line)
                                            (match-string-no-properties 2 line)) record))          
                              ) lines)
                    (reverse record)))
                paras)
             )
             (table_head (mapcar
                          (lambda (r) (car r))
                          (car data_view))))
             (kill-region (point-min) (point-max))
             (insert "|")
             (mapcar (lambda (column_name)
                       (insert column_name)
                       (insert "|")
                       ) table_head)
             (insert "\n|-\n")
             (mapcar (lambda (record)
                       (insert "|")
                       (mapcar (lambda (value)
                                 (insert value)
                                 (insert "|")
                                 ) (mapcar (lambda (r) (cdr r)) record))
                       (insert "\n")
                       ) data_view)
             (goto-char (point-min))
             (org-table-align)
             (pop-to-buffer (concat filename ".view"))
             (deactivate-mark)
             (org-mode)
             data_view
      ))))

(defun convert-csv-to-org-table (&optional filename)
  (interactive)
  (with-current-buffer (find-file (if filename
                                      filename
                                    (buffer-file-name)))

    (save-excursion
      (goto-char (point-min))
      (org-table-convert-region (point-min) (point-max) '(4))
      (forward-line)
      (open-line 1)
      (insert "|-")
      (org-table-align)
      ))
  )

(defun convert-org-table-to-csv (&optional filename)
  (interactive)
  (with-current-buffer (find-file (if filename
                                      filename
                                    (buffer-file-name)))

    (save-excursion
      (let ((content (orgtbl-to-csv
                      (org-table-to-lisp)
                      nil)))
        (kill-region (point-min) (point-max))
        (goto-char (point-min))
        (insert content))))
  )

(defun list-table-name (database_name)
  (interactive)
    (let* ((schemas_maybe_with_index
            (org-split-string
             (shell-command-to-string
              (message
               "%s"
               (format "echo '.schema'| sqlite3  %s|tr '\n' ' '" database_name)
               )) "CREATE INDEX"))
           (schemas
            (org-split-string
             (car schemas_maybe_with_index)
             "CREATE TABLE"))
         (tables
          (mapcar
           (lambda (str)
             (let ((table
                    (replace-regexp-in-string
                      "`"
                      ""
                      (progn
                      (string-match "\\(.*?\\)(.*" str)
                      (org-trim (match-string 1 str))
                      ))
                    )
                   (column
                    (parse-schema str)
                    )
                   )
               (cons table column)
               )
             )
           schemas))
         )
    tables)
  )

(defun convert-sqlite3-to-org-table-annoted-by-record-list (&optional database_name update) ; TODO convenient for debug, remove option later
  (interactive)
  (let* ((database_name (if (stringp database_name)
                            database_name
                          "/tmp/orgsql/data.db"))
         (tables (list-table-name database_name))
         (table_name (if (eq (length tables) 1)
                         (caar tables)
                       (ido-completing-read
                        "select table:" 
                        (mapcar 'car tables) nil t)
                       ))
         (column (org-trim
                  (mapconcat
                  (lambda (table)
                    (if (eq (car table) table_name)
                      (mapconcat
                       'car
                       (cdr table) ",")
                      ""
                      )
                    )
                  tables  " ")))
         (txt (shell-command-to-string
               (message "%s"
                        (format "sqlite3 -line %s '%s'"
                                database_name
                                (if update
                                    sqlite3-select-clause
                                  (setq sqlite3-select-clause
                                        (read-from-minibuffer
                                         (format " SQL column(%s) : " column) 
                                         (format "select * from %s;" table_name)))
                                  )
                                )
                        )))
         (schema (parse-schema (shell-command-to-string
                                (message "%s"
                                         (format "echo '.schema %s'| sqlite3  %s|tr '\n' ' '"
                                                 table_name database_name 
                                                 )
                                         ))))
         (count (org-trim (shell-command-to-string
                           (message "%s"
                                    (format "sqlite3  %s 'select count(*) from %s;'"
                                            database_name table_name
                                            )
                                    ))))
         (paras (nthcdr 0 (org-split-string txt "\n\n")))
         (view_name (concat database_name "." table_name ".view"))
         )
   (setq sqlite-mode-database-name database_name)
   (setq sqlite-mode-table-name table_name)
   (setq content "")
    (setq data_view (mapcar (lambda (para)
                              (let ((record (list))
                                    (lines (org-split-string para "\n")))
                                (mapcar (lambda (line)
                                          (when (string-match "\\([a-zA-Z0-9-_]+\\)\s=\s\\(.*\\)" line)
                                            (push (cons (match-string-no-properties 1 line)
                                                        (match-string-no-properties 2 line)) record))          
                                          ) lines)
                                (reverse record)))
                            paras)
          )
    (setq table_head (mapcar 'car (car data_view)))
    (setq content (mapconcat (lambda (record)
                               (let ((first "|")) 
                                 (add-text-properties 0 1 (cons 'sqlite3-db-record (list (copy-alist record))) first)
                                 (concat first (mapconcat 'cdr record "|"))
                                 )
                               ) data_view "\n"))
    (let ((view_name (concat table_name ".view")))
      (when (bufferp (get-buffer view_name)) 
        (kill-buffer view_name)
        )
      ) 
    (with-current-buffer (or (get-buffer view_name)
                             (get-buffer-create view_name))
      (kill-region (point-min) (point-max))
      (goto-char (point-min))
      (save-excursion
        (let ((table-head-record "|"))
          (add-text-properties 0 1
                               (cons
                                'sqlite3-table-head
                                (list
                                 (append
                                  schema
                                  (list
                                   (cons "query" sqlite3-select-clause)
                                   (cons "count" count)
                                   (cons "database" database_name)
                                   )))) table-head-record)
          (insert (concat
                   table-head-record
                   (mapconcat (lambda (x)
                                x
                                ) table_head "|")
                   "\n|-\n"
                   ))
          (setq sqlite3-table-head table_head)
          )
        (insert content)
        )
      (unless (eq (current-buffer)
                  (get-buffer view_name))
        (pop-to-buffer view_name)
        )
      (org-mode)
      (org-table-align)
      (dbview-mode t)
      )
    )
  )

(defun convert-sqlite3-to-org-lisp (database_name)
  (let* ((table_name (file-name-sans-extension (file-name-nondirectory database_name)))
         (dump_lines (shell-command-to-string
                      (message "%s" (format "sqlite3 -line %s 'select * from %s'" database_name table_name))
                      ))
         (paras (nthcdr 0 (org-split-string dump_lines "\n\n")))
         (table_head ((lambda (para)
                         (let ((record (list))
                               (lines (org-split-string para "\n")))
                           (mapcar (lambda (line)
                                     (when (string-match "\\([a-zA-Z0-9-_]+\\)\s=\s\\(.*\\)" line)
                                       (push (match-string-no-properties 1 line) record))          
                                     ) lines)
                           (reverse record))
                         ) (car paras))))
    (cons table_head (mapcar (lambda (para)
                               (let ((record (list))
                                     (lines (org-split-string para "\n")))
                                 (mapcar (lambda (line)
                                           (when (string-match "\\([a-zA-Z0-9-_]+\\)\s=\s\\(.*\\)" line)
                                             (push (match-string-no-properties 2 line) record))          
                                           ) lines)
                                 (reverse record)))
                             paras))
    )
  )

(defun convert-sqlite3-to-csv (database_name)
  (orgtbl-to-generic (convert-sqlite3-to-org-lisp database_name) '(:sep ","))
  )

(defun query-org-table-line-record-list (&optional x)
  (interactive)
  (let ((line (if x
                  x
                (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))
    (unless (string-match org-table-hline-regexp line)
      (let ((values (org-split-string (org-trim line) "\\s-*|\\s-*")))
        (mapcar (lambda (i)
                  (cons
                   (nth i sqlite3-table-head)
                   (nth i values))
                  )
                (number-sequence 0 (- (safe-length sqlite3-table-head) 1)))
        )
      )
    )
  )

(defun compare-org-table-with-record-list-and-mark ()
  (interactive)
  (unless (org-at-table-p)
    (error "No table at point"))
  (save-excursion
    (goto-char (org-table-begin))
    (forward-line)
    (while (org-at-table-p)
      (check-org-table-line-with-record-list)
      (forward-line)
      )
    )
  )

(defvar sqlite3-table-head-it)
(defvar sqlite3-table-head)
(defvar sqlite3-db-record)
(defvar org-line-record)


(defface sqlite-sync-change
  '((((class color)) (:background "magenta"))
    (t (:bold t)))
  "Face used for marking sqlite-sync-change."
  :group 'sqlite-sync)

(defface sqlite-sync-insert
  '((((class color)) (:background "green"))
    (t (:bold t)))
  "Face used for marking sqlite-sync-insert."
  :group 'sqlite-sync)

(defun sqlite-sync-mark-as-change (&optional pos)
  (interactive)
  (save-excursion
    (let* ((pos (if pos
                    pos
                  (point)))
           (ov (make-overlay pos (+ pos 1) nil t t))
           )
      (overlay-put ov 'face 'sqlite-sync-change)
      (overlay-put ov 'sqlite-sync-overlay t)
      ov))
  
  )

(defun sqlite-sync-mark-as-insert (&optional pos)
  (interactive)
  (let* ((pos (if pos
                 pos
               (point)))
         (ov (make-overlay pos (+ pos 1) nil t t))
        )
    (overlay-put ov 'face 'sqlite-sync-insert)
    (overlay-put ov 'sqlite-sync-overlay t)
    ov)
  )

(defun sqlite-sync-mark-as-unchange (&optional pos)
  (interactive)
  (let ((pos (if pos
                 pos
               (point))))
    (dolist (ol (overlays-in pos (+ pos 1)))
        (delete-overlay ol))
    ))

(defun check-org-table-line-with-record-list (&optional line)
  (let ((line (if line
                  line
                (buffer-substring (line-beginning-position) (line-end-position))) ))
    (unless (string-match org-table-hline-regexp line)
      (let* ((bol (line-beginning-position))
             (current (query-org-table-line-record-list line))
             (database (get-text-property 0 'sqlite3-db-record line))
             (head (get-text-property 0 'sqlite3-table-head line))
             (unchanged t)
             )
        (if database
            (unless (equal database current)
              (sqlite-sync-mark-as-change bol)
              (setq unchanged nil)
              )
          (unless head
            (sqlite-sync-mark-as-insert bol)
            (setq unchanged nil)
            )
          
          )
        (when unchanged
          (sqlite-sync-mark-as-unchange bol)
          )
        )
      )
    )
  )

(defun mark-different-with-sqlite3-record (start end len)
  (let (
        (check_start (save-excursion
                       (goto-char start)
                       (line-beginning-position)
                       ))
        (check_end (save-excursion
                     (goto-char end)
                     (line-end-position)
                     ))
        )
    (save-excursion
      (goto-char check_start)
      (while (and (<= (point) check_end) (org-at-table-p)) 
        (check-org-table-line-with-record-list (buffer-substring (line-beginning-position) (line-end-position)))
        (forward-line 1)
        )
      )
    )
  )

(defvar dbview-mode-map (make-keymap)
  "Minor mode keymap for `dbview-mode'")

(define-minor-mode dbview-mode 
  "minor mode for view sqlite database rows"
  nil :lighter " db-view" :keymap dbview-mode-map
  (cond (dbview-mode
         (add-hook 'after-change-functions 'mark-different-with-sqlite3-record t t)
         (compare-org-table-with-record-list-and-mark)
         (remove-hook 'before-change-functions 'org-before-change-function t)
         (define-key dbview-mode-map "\C-\M-j" 'commit-data-view-to-sqlite3)
         (define-key dbview-mode-map "\M-?" 'sqlite3-inspect)
         )
        (t
         (remove-hook 'after-change-functions 'mark-different-with-sqlite3-record t)
         (dolist (ol (overlays-in (point-min) (point-max)))
           (when (overlay-get ol 'sqlite-sync-overlay)
             (delete-overlay ol)
             ))
         (add-hook 'before-change-functions 'org-before-change-function nil t)
         ))
  )

(defun quote-value (field, field_types)
  (cond
   ((and
     (equal
      (cdr
       (assoc
        (car c)
        head_record))
      "TEXT")
     (not (eq ?\" (string-to-char (cdr c)))))
    (concat "\"" (cdr c) "\"")
    )
   (t
    (cdr c)
    )
   )
  )

(defun export-change-to-sql-clause ()
  (interactive)
  (goto-char (org-table-begin))
  (setq clause "BEGIN TRANSACTION;")
  (let ((table_name (file-name-sans-extension (file-name-nondirectory (buffer-name))))
        (id_field_name (car (rassoc
                             "INTEGER PRIMARY KEY"
                             (get-text-property (line-beginning-position) 'sqlite3-table-head))))
        )
    (while (and (< (point) (org-table-end)) (org-at-table-p))
      (let* ((bol (line-beginning-position))
             (line (buffer-substring (line-beginning-position) (line-end-position)))
             (current (query-org-table-line-record-list line))
             (database (get-text-property 0 'sqlite3-db-record line))
             (head (get-text-property 0 'sqlite3-table-head line))
             )
        (unless (string-match org-table-hline-regexp line)
          (if database
              (unless (equal database current)
                (let* ((id (cdr (assoc id_field_name current)))
                       (update_clause (format
                                       "UPDATE %s SET %s WHERE %s = %s;"
                                       table_name
                                       (mapconcat (lambda (c)
                                                    (format "%s = %s"
                                                            (car c)
                                                            (quote-value c head_record)
                                                            )
                                                    )
                                                  current ",")
                                       id_field_name
                                       id
                                       )))
                  (setq clause (concat clause (substring-no-properties update_clause)))
                  )
                )
            (if  head
                (setq head_record head)
              (let ((insert_clause (format
                                    "INSERT INTO %s (%s) VALUES(%s);"
                                    table_name
                                    (mapconcat (lambda (c)
                                                 (car c)
                                                 ) current ",")
                                    (mapconcat (lambda (c)
                                                 (quote-value c head_record)
                                                 ) current ",")
                                    )))
                (setq clause (concat clause (substring-no-properties insert_clause)))
                )
              )
            )
          )
        )
      (forward-line)
      )
    (if (> (length clause) 18)
        (progn (setq clause (concat clause "COMMIT;"))
               (message clause )
               )
      nil
      )
    )
  )

(defun commit-data-view-to-sqlite3 ()
  (interactive)
  (let ((commit (export-change-to-sql-clause))
          (buffer (current-buffer))
          (database_name (save-excursion
                           (goto-char (org-table-begin))
                           (cdr
                            (assoc
                             "database"
                             (get-text-property
                              (line-beginning-position)
                              'sqlite3-table-head))))))


      (if (and (comint-check-proc "*SQL*")
               (equal 'sqlite sql-interactive-product)
               (equal database_name sql-database)
               )
          (progn
            (sql-send-string commit)
            (dbview-mode nil)
            (convert-sqlite3-to-org-table-annoted-by-record-list database_name)
            (let* ((dir_name (file-name-directory database_name))
                   (table_name (file-name-sans-extension
                               (file-name-nondirectory
                                database_name)))
                   (csv_name
                    (concat
                     dir_name
                     table_name
                     ".csv"
                     ))
                   (csv_buffer_name
                    (concat
                     table_name
                     ".csv")))
              (when (file-exists-p
                     csv_name)
                (find-file-other-window csv_name)
                (with-current-buffer (get-buffer csv_buffer_name)
                  (kill-region (point-min) (point-max))
                  (insert-string
                   (convert-sqlite3-to-csv
                    database_name))
                  (save-buffer)
                  )
                )
              )
            )
        (sql-sqlite)
        )
      )
  )

(provide 'bartuer-sql)