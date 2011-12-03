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
           (fields (nthcdr 0 (org-split-string head_line ","))))
      (shell-command (message
                      (if (file-exists-p database_name)
                          (format "sqlite3 %s 'drop table %s;create table %s(%s);'"
                                  database_name table_name table_name (mapconcat (lambda (f)
                                                                                   (concat f " TEXT")
                                                                                   ) fields ","))
                        (format "sqlite3 %s 'create table %s(%s);'"
                                database_name table_name (mapconcat (lambda (f)
                                                                      (concat f " TEXT")
                                                                      ) fields ","))
                        )))
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

(defun convert-sqlite3-to-org-table-annoted-by-record-list (&optional database_name) ; TODO convenient debug, remove option later
  (interactive)
  (let* ((database_name (if (stringp database_name)
                            database_name
                          "/tmp/orgsql/data.db"))
         (table_name (file-name-sans-extension (file-name-nondirectory database_name)))
         (txt (shell-command-to-string
               (message "%s"
                        (format "sqlite3 -line %s '%s'"
                                database_name
                                (read-from-minibuffer " SQL : "
                                                      (format "select * from %s;" table_name)))
                        )))
         (paras (nthcdr 0 (org-split-string txt "\n\n")))
         )
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

    (with-current-buffer (get-buffer-create (concat table_name ".view"))
      (kill-region (point-min) (point-max))
      (goto-char (point-min))
      (save-excursion
        (let ((table-head-record "|"))
          (add-text-properties 0 1 (cons 'sqlite3-table-head (list table_head)) table-head-record)
          (insert (concat
                   table-head-record
                   (mapconcat (lambda (x)
                                x
                                ) table_head "|")
                   )
                  "\n|-\n")
          (setq sqlite3-table-head table_head)
          )
        
        (insert content)
        (org-table-align-patched)
        )
      (pop-to-buffer (concat table_name ".view"))
      (org-mode)
      ;; (database-view-mode t) this will mess convert
      )
    )
  )

(defalias 'sql 'convert-sqlite3-to-org-table-annoted-by-record-list)

(defun sqlite3-inspect (&optional field)
  (interactive)
  (let ((max_field_name (reduce 'max
                                (mapcar 'length
                                        (mapcar 'car
                                                (get-text-property
                                                 (line-beginning-position)
                                                 'sqlite3-db-record))))))
    
    (message "%s" (mapconcat (lambda (entry)
                               (format (concat  "%" (format "%d" max_field_name) "s : %s") (car entry) (cdr entry))
                               )
                             (get-text-property (line-beginning-position) 'sqlite3-db-record) "\n"))  
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
             (org-table-align-patched)
             (pop-to-buffer (concat filename ".view"))
             (deactivate-mark)
             (org-mode)
             data_view
      ))))

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

(defun convert-sqlite3-minor-modeto-org-lisp (database_name)
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
             (unchanged t)
             )
        (if database
            (unless (equal database current)
              (sqlite-sync-mark-as-change bol)
              (setq unchanged nil)
              )
          (progn
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

(defvar database-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\M-?" 'sqlite3-inspect)
    map)
  "Minor mode keymap for database-view-mode")

(define-minor-mode database-view-mode
  :group 'fundamental :lighter " db-view " :keymap database-view-mode-map
  (cond (database-view-mode
         (add-hook 'after-change-functions 'mark-different-with-sqlite3-record t t)
         (compare-org-table-with-record-list-and-mark)
         (remove-hook 'before-change-functions 'org-before-change-function t)
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

(setq database-view-mode nil)
(defun exe-record-list-as-sql-insert ()
                                        ; need guess field data type
                                        ; need insert Unique ID if unavailable
                                        ; need generate SQL and execute it as transaction
    )

(defalias  'org-table-align-patched 'org-table-align)

(defun org-table-align ()
  "Align the table at point by aligning all vertical bars."
  (interactive)
  (message "org table align\n")
  
  (let* (
	 ;; Limits of table
	 (beg (org-table-begin))
	 (end (org-table-end))
	 ;; Current cursor position
	 (linepos (org-current-line))
	 (colpos (org-table-current-column))
	 (winstart (window-start))
	 (winstartline (org-current-line (min winstart (1- (point-max)))))
	 lines (new "") lengths l typenums ty fields maxfields i
	 column
	 (indent "") cnt frac
	 rfmt hfmt
	 (spaces '(1 . 1))
	 (sp1 (car spaces))
	 (sp2 (cdr spaces))
	 (rfmt1 (concat
		 (make-string sp2 ?\ ) "%%%s%ds" (make-string sp1 ?\ ) "|"))
	 (hfmt1 (concat
		 (make-string sp2 ?-) "%s" (make-string sp1 ?-) "+"))
	 emptystrings links dates emph raise narrow
	 falign falign1 fmax f1 len c e space)
    (untabify beg end)
    (remove-text-properties beg end '(org-cwidth t org-dwidth t display t))
    ;; Check if we have links or dates
    (goto-char beg)
    (setq links (re-search-forward org-bracket-link-regexp end t))
    (goto-char beg)
    (setq emph (and org-hide-emphasis-markers
		    (re-search-forward org-emph-re end t)))
    (goto-char beg)
    (setq raise (and org-use-sub-superscripts
                     (re-search-forward org-match-substring-regexp end t)))
    (goto-char beg)
    (setq dates (and org-display-custom-times
		     (re-search-forward org-ts-regexp-both end t)))
    ;; Make sure the link properties are right
    (when links (goto-char beg) (while (org-activate-bracket-links end)))
    ;; Make sure the date properties are right
    (when dates (goto-char beg) (while (org-activate-dates end)))
    (when emph (goto-char beg) (while (org-do-emphasis-faces end)))
    (when raise (goto-char beg) (while (org-raise-scripts end)))

    ;; Check if we are narrowing any columns
    (goto-char beg)
    (setq narrow (and org-table-do-narrow
		      org-format-transports-properties-p
		      (re-search-forward "<[rl]?[0-9]+>" end t)))
    (goto-char beg)
    (setq falign (re-search-forward "<[rl][0-9]*>" end t))
    (goto-char beg)
    ;; Get the rows
    (setq lines (org-split-string
		 (buffer-substring beg end) "\n"))
    ;; Store the indentation of the first line
    (if (string-match "^ *" (car lines))
	(setq indent (make-string (- (match-end 0) (match-beginning 0)) ?\ )))
    ;; Mark the hlines by setting the corresponding element to nil
    ;; At the same time, we remove trailing space.
    (setq lines (mapcar (lambda (l)
			  (if (string-match "^ *|-" l)
			      nil
			    (if (string-match "[ \t]+$" l)
				(substring l 0 (match-beginning 0))
			      l)))
			lines))
    ;; Get the data fields by splitting the lines.
    (setq fields (mapcar
		  (lambda (l)
                    (org-split-string l " *| *"))
		  (delq nil (copy-sequence lines))))
    ;; How many fields in the longest line?
    (condition-case nil
	(setq maxfields (apply 'max (mapcar 'length fields)))
      (error
       (kill-region beg end)
       (org-table-create org-table-default-size)
       (error "Empty table - created default table")))
    ;; A list of empty strings to fill any short rows on output
    (setq emptystrings (make-list maxfields ""))
    ;; Check for special formatting.
    (setq i -1)
    (while (< (setq i (1+ i)) maxfields)   ;; Loop over all columns
      (setq column (mapcar (lambda (x) (or (nth i x) "")) fields))
      ;; Check if there is an explicit width specified
      (setq fmax nil)
      (when (or narrow falign)
	(setq c column fmax nil falign1 nil)
	(while c
	  (setq e (pop c))
	  (when (and (stringp e) (string-match "^<\\([rl]\\)?\\([0-9]+\\)?>$" e))
	    (if (match-end 1) (setq falign1 (match-string 1 e)))
	    (if (and org-table-do-narrow (match-end 2))
		(setq fmax (string-to-number (match-string 2 e)) c nil))))
	;; Find fields that are wider than fmax, and shorten them
	(when fmax
	  (loop for xx in column do
		(when (and (stringp xx)
			   (> (org-string-width xx) fmax))
		  (org-add-props xx nil
		    'help-echo
		    (concat "Clipped table field, use C-c ` to edit. Full value is:\n" (org-no-properties (copy-sequence xx))))
		  (setq f1 (min fmax (or (string-match org-bracket-link-regexp xx) fmax)))
		  (unless (> f1 1)
		    (error "Cannot narrow field starting with wide link \"%s\""
			   (match-string 0 xx)))
		  (add-text-properties f1 (length xx) (list 'org-cwidth t) xx)
		  (add-text-properties (- f1 2) f1
				       (list 'display org-narrow-column-arrow)
				       xx)))))
      ;; Get the maximum width for each column
      (push (apply 'max (or fmax 1) 1 (mapcar 'org-string-width column))
	    lengths)
      ;; Get the fraction of numbers, to decide about alignment of the column
      (if falign1
	  (push (equal (downcase falign1) "r") typenums)
	(setq cnt 0 frac 0.0)
	(loop for x in column do
	      (if (equal x "")
		  nil
		(setq frac ( / (+ (* frac cnt)
				  (if (string-match org-table-number-regexp x) 1 0))
			       (setq cnt (1+ cnt))))))
	(push (>= frac org-table-number-fraction) typenums)))
    (setq lengths (nreverse lengths) typenums (nreverse typenums))

    ;; Store the alignment of this table, for later editing of single fields
    (setq org-table-last-alignment typenums
	  org-table-last-column-widths lengths)

    ;; With invisible characters, `format' does not get the field width right
    ;; So we need to make these fields wide by hand.
    (when (or links emph raise)
      (loop for i from 0 upto (1- maxfields) do
	    (setq len (nth i lengths))
	    (loop for j from 0 upto (1- (length fields)) do
		  (setq c (nthcdr i (car (nthcdr j fields))))
		  (if (and (stringp (car c))
			   (or (text-property-any 0 (length (car c))
						  'invisible 'org-link (car c))
			       (text-property-any 0 (length (car c))
						  'org-dwidth t (car c)))
			   (< (org-string-width (car c)) len))
		      (progn
			(setq space (make-string (- len (org-string-width (car c))) ?\ ))
			(setcar c (if (nth i typenums)
				      (concat space (car c))
				    (concat (car c) space))))))))

    ;; Compute the formats needed for output of the table
    (setq rfmt (concat indent "|") hfmt (concat indent "|"))
    (while (setq l (pop lengths))
      (setq ty (if (pop typenums) "" "-")) ; number types flushright
      (setq rfmt (concat rfmt (format rfmt1 ty l))
	    hfmt (concat hfmt (format hfmt1 (make-string l ?-)))))
    (setq rfmt (concat rfmt "\n")
	  hfmt (concat (substring hfmt 0 -1) "|\n"))

    (setq new (mapconcat
	       (lambda (l)
		 (if l
                     (progn (let ((formatted_line (apply 'format rfmt (append (pop fields) emptystrings))))
                              (add-text-properties 0 1 (text-properties-at 0 l) formatted_line)
                              formatted_line
                              )
                            )
		   hfmt))
	       lines ""))
    (if (equal (char-before) ?\n)
	;; This hack is for org-indent, to force redisplay of the
	;; line prefix of the first line. Apparently the redisplay
	;; is tied to the newline, which is, I think, a bug.
	;; To force this redisplay, we remove and re-insert the
	;; newline, so that the redisplay engine thinks it belongs
	;; to the changed text.
	(progn
	  (backward-delete-char 1)
	  (insert "\n")))
    (move-marker org-table-aligned-begin-marker (point))
    (insert new)
    ;; Replace the old one
    (delete-region (point) end)
    (move-marker end nil)
    (move-marker org-table-aligned-end-marker (point))
    (when (and orgtbl-mode (not (org-mode-p)))
      (goto-char org-table-aligned-begin-marker)
      (while (org-hide-wide-columns org-table-aligned-end-marker)))
    ;; Try to move to the old location
    (org-goto-line winstartline)
    (setq winstart (point-at-bol))
    (org-goto-line linepos)
    (set-window-start (selected-window) winstart 'noforce)
    (org-table-goto-column colpos)
    (and org-table-overlay-coordinates (org-table-overlay-coordinates))
    (setq org-table-may-need-update nil)
    )
  (when (equal "view" (file-name-extension (buffer-name)))
    (compare-org-table-with-record-list-and-mark)
    )
  )

