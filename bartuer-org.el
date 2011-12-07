(defun bartuer-org-insert-child ()
  "insert a child"
  (interactive)
  (org-insert-heading-after-current)
  (org-do-demote))

(defun convert-time-to-minutes (str)
  "convert time span string like \"[2011-01-20 Thu 02:27]--[2011-01-20 Thu 04:19] =>  1:52\" to 112 (minutes)"
  (eval (read (replace-regexp-in-string ".*?=> *\\([0-9]+\\):\\([0-9]+\\)" "(+ (* 60 \\1) \\2)" str)))
  )

(defun org-effort-allowed-property-values (property)
  "Supply allowed values for Effort properties."
  (cond
   ((equal property "Effort")
    '("2:00" "2:30" "1:30" "3:00" "1:00" "0:20" "0:30" "0:45" "4:00" "0:10" "0:15" "0:05" "5:00" "6:00" "8:00"))
   (t nil)))

(defun bartuer-capture-insert-link ()
  "for insert current stored link when capturing"
  (interactive)
  (with-current-buffer (get-buffer-create "*org-link-temp*")
    (org-insert-link)
    (setq org-currnet-link-string (buffer-substring (point-min) (point-max)))
    (kill-region (point-min) (point-max)))
  org-currnet-link-string
  )

(defun bartuer-setup-capture ()
  "capture templates"
  (interactive)
  (setq org-capture-templates
        '(("d" "Debug" entry (file+headline "~/org/next.org" "Debuging")
           "* TODO %?\n  %^{SCHEDULED}p\n  %a\n  %i\n")
          ("f" "Fix" entry (file+headline "~/org/next.org" "Fixing")
           "* TODO %?\n  %^{SCHEDULED}p\n  %i\n")
          ("$" "Buy" entry (file+headline "~/org/next.org" "Buying")
           "* TODO %?\n  %^{SCHEDULED}p\n  %i\n")
          ("b" "Build" entry (file+headline "~/org/next.org" "Building")
           "* TODO %?\n  %^{SCHEDULED}p\n  %i\n")
          ("h" "Hack" entry (file+headline "~/org/next.org" "Hacking")
           "* TODO %?\n  %^{SCHEDULED}p\n  %a\n  %i\n")
          ("m" "Meet" entry (file+headline "~/org/next.org" "Meeting")
           "* TODO %?\n %a %^{SCHEDULED}p\n  %i\n")
          ("s" "Research" entry (file+headline "~/org/next.org" "Researching")
           "* TODO %?\n  %^{SCHEDULED}p\n  %(bartuer-capture-insert-link)\n  %i\n")
          ("r" "Read" entry (file+headline "~/org/next.org" "Reading")
           "* TODO %?\n  %^{SCHEDULED}p\n  %(bartuer-capture-insert-link)\n  %i\n")
          ("w" "Watch" entry (file+headline "~/org/next.org" "Watching")
           "* TODO %?\n  %^{SCHEDULED}p\n  %(bartuer-capture-insert-link)\n  %i\n")
          ("t" "Todo" entry (file+headline "~/org/next.org" "!Category")
           "* TODO %?\n  %^{SCHEDULED}p\n  %i\n")
          ("c" "Capture" plain (file "~/org/quote.org")
           "* %?\n%U\n%c\n%i\n")
          ("j" "Journey" plain (file+datetree "~/org/diary.org")
           "      - %?\n       %U\n  %i\n")
          ("l" "Sleeping" plain (file+datetree "~/org/sleep.org") 
           "******* TODO \n  " :clock-in t)
          )))

(defun bartuer-jump-to-archive ()
  "jump from org to it's archive file"
  (interactive)
  (require 'org-archive)
  (find-file (org-extract-archive-file)))


(setq org-timestamp-format "%Y-%m-%d %a %H:%M")
(setq org-auto-schedule-break (* 60 15))
(setq org-todo-matcher "+TODO=\"TODO\"")
(setq org-default-effort "02:00")

(defun extract-clock-time (str)
  "get (clock-in-string . clock-out-string)"
  (interactive)
  (string-match org-tr-regexp-both str)
  (let ((ts1 (match-string-no-properties 1 str))
        (ts2 (match-string-no-properties 2 str)))
    (cond ((and ts1 ts2)
           (cons ts1 ts2
                 ))
          ((and ts1 (eq ts2 nil))
           (cons
            ts1 nil)
           nil)
          (t
           (cons nil nil)))))

(defun effort->secs (timestring)
  "convert org Effort string to seconds"
  (if (not (stringp timestring))
      7200
    (setq effort-minutes nil)
    (if (numberp (string-match "\\([0-9]+\\.[0-9]+\\)$" timestring))
        (setq effort-minutes
              (* 3600
                 (string-to-number
                  (match-string-no-properties 1 timestring))))
      (if (numberp (string-match "\\([0-9]+\\:[0-9]+$\\)" timestring))
          (setq effort-minutes
                (* 60
                   (org-hh:mm-string-to-minutes
                    (match-string-no-properties 1 timestring)))))))
  ) 
  

(defvar timestamp-regexp
  "[0-9]+?-[0-9]+?-[0-9]+ [A-Za-z]+ \\([0-9]+\\:[0-9]+$\\)"
  "timestamp regexp"
  )


(defun timestamp->fraction (timestamp)
  "convert org time stamp string to seconds"
  (let ((fraction 0))
    (when (numberp (string-match timestamp-regexp timestamp)) 
      (setq fraction
            (/ (round (* 100 (/ (* 60
                                   (org-hh:mm-string-to-minutes
                                    (match-string-no-properties 1 timestamp) )) 86400.0))) 100.0)))
    fraction)
  )

;;; can set these information in symbol plist 
(defun day-string-full-parse (s)
  "parse time string to code friendly structure"
  (let* ((day (org-time-string-to-absolute s))
         (weekp (calendar-iso-from-absolute day))
         (normalp (calendar-gregorian-from-absolute day))
         (day-info '(:year 2011)))
    (plist-put day-info :month (pop normalp))
    (plist-put day-info :day (pop normalp))
    (plist-put day-info :year (pop normalp))
    (plist-put day-info :week (pop weekp))
    (plist-put day-info :weekday (pop weekp))
    (plist-put day-info :absolute day)
    (copy-alist  day-info)
    )
  )

(defun absolute-day-to-that-week (d)
  "give absolute day number, return that week days string list"
  (let* ((w:wd:y (calendar-iso-from-absolute d))
         (w (nth 0 w:wd:y))
         (wd (nth 1 w:wd:y))
         (Mon
          (if (= wd 0)
              (- d 6)
            (- d (- wd 1)))
          )
         (Tue (1+ Mon)) (Wed (1+ Tue)) (Thu (1+ Wed)) (Fri (1+ Thu)) (Sat (1+ Fri)) (Sun (1+ Sat))
         )
    (mapcar
     (lambda (s)
       (let* ((date (calendar-gregorian-from-absolute (symbol-value s)))
              (m (nth 0 date))
              (d (nth 1 date))
              (y (nth 2 date)))
         (format "%04d-%02d-%02d %s" y m d (symbol-name s))))
     (list 'Mon 'Tue 'Wed 'Thu 'Fri 'Sat 'Sun))
    )
  )

(eval-and-compile
  (defconst calendar-short-month-name ["" "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"]))

(defun judge-week-to-month (w y)
  "give week name in number, string or symbol, list or vector of
that week days string is also okay, y is year number.

return which month that week should belong, the return value is
cons like (12 . Dec)"
  (let ((weekday-list
         (let ((week
                (cond ((stringp w)
                       (string-to-number w)
                       )
                      ((symbolp w)
                       (symbol-value w))
                      ((numberp w)
                       w)
                      (t
                       w))))
           (if (numberp week)
               (progn
                 (let ((day-in-week
                        (+ (* 7 (1- week))
                           (calendar-absolute-from-iso
                            (list 1 1 y)))))
                   (absolute-day-to-that-week day-in-week)))
             (if (or (listp week)
                     (vectorp week))
                 week
               (error "wrong argument")
               )
             ))))
    (let ((month
           (elt
            (mapcar
             (lambda (day-info) (plist-get day-info :month))
             (mapcar 'day-string-full-parse weekday-list)
             )
            3)))
      (cons month (elt calendar-short-month-name month))) 
    )
  )


(defun month-weeks (month year)
  (let* ((month-first-day
          (calendar-iso-from-absolute
           (calendar-absolute-from-gregorian (list month 1 year))))
         (month-last-day
          (calendar-iso-from-absolute
           (calendar-absolute-from-gregorian (list month 28 year))))
         (first-day-week (if (and 
                              (= (1- year)
                                 (nth 2 month-first-day))
                              (= (nth 0 month-first-day) 52))
                             1
                           (nth 0 month-first-day)
                           ) )
         (last-day-week (nth 0 month-last-day))
         (first-week (if (= month
                            (car
                             (judge-week-to-month first-day-week year)))
                         first-day-week
                       (1+ first-day-week)))
         (last-week (if (= month
                           (car
                            (judge-week-to-month last-day-week year)))
                        last-day-week
                      (1- last-day-week))))
    (number-sequence first-week last-week) 
    )
  )

(defun set-schedule ()
  "if next schedule time slot is too late, move it to next day morning"
  (setq new-day-time-or-last-schedule
        (seconds-to-time
         (+
          (org-time-string-to-seconds
           (let ((last-schedule-time
                  (decode-time
                   (org-time-string-to-time next-time-slot))))
             (setq new-day-time nil)
             (if (>= (nth 2 last-schedule-time) 21)
                 (progn
                   (setq new-day-time
                         (list
                          (nth 0 last-schedule-time)
                          0
                          2
                          (+ 1 (nth 3 last-schedule-time))
                          (nth 4 last-schedule-time)
                          (nth 5 last-schedule-time)
                          (nth 6 last-schedule-time)
                          (nth 7 last-schedule-time)
                          (nth 8 last-schedule-time)))
                   (format-time-string
                    org-timestamp-format
                    (apply 'encode-time new-day-time))
                   )
               next-time-slot)))
          org-auto-schedule-break
          ))))

(defun add-effort-schedule ()
  "schedule according to effort, next schedule time will be last
clock out time, if there is no clock time, next schedule time will be last schedule time plus effort time"
  (let* ((e ((lambda ()
               (unless (org-entry-get (point) "Effort")
                 (org-entry-put (point) "Effort" org-default-effort))
               (org-entry-get (point) "Effort"))))
         (s ((lambda ()
               (if next-time-slot
                   (progn
                     (org-schedule
                      nil
                      (set-schedule)))
                 (org-schedule nil schedule-start-time))
               (org-entry-get (point) "SCHEDULED"))))
         (c (org-entry-get (point) "CLOCK")))
    (setq next-time-slot
          (format-time-string
           org-timestamp-format
           (let ((clockout
                  (if c
                      (cdr
                       (extract-clock-time
                        (org-entry-get (point) "CLOCK")))
                    nil)
                  ))
             (if (stringp clockout)
                 (seconds-to-time
                  (org-time-string-to-seconds clockout)
                  )
               (seconds-to-time
                (+
                 (org-time-string-to-seconds s)
                 (effort->secs e))
                )
               )
             )
           )
          )
    )
  )

(defun schedule-tree ()
  "apply schedule policy to current subtree, skip non TODO item"
  (interactive)
  (setq next-time-slot nil)
  (setq schedule-start-time
        (org-read-date t 'totime))
  (org-map-entries
   'add-effort-schedule
   org-todo-matcher
   'tree
   'archive 'comment)
  )

(defun bartuer-focus ()
  "jump to current in clock task entry"
  (interactive)  
  (org-clock-goto)
  (org-occur (replace-regexp-in-string "\\[.*\\]" "" org-clock-current-task))
  (org-clock-goto))

(defun magit-org-commit ()
  "when one task under clock check in, also insert commit information to task entry"
  (interactive)
  (when org-clock-has-been-used
    (let* ((clock-task-string (replace-regexp-in-string " *\\[.*\\]" "" org-clock-current-task))
           (commit-string (shell-command-to-string "git log HEAD -1 --pretty=format:'%s'"))
           (git-link-string (org-trim (shell-command-to-string (concat "tag-head " clock-task-string)))))
      (when (string-equal clock-task-string commit-string)
        (save-excursion
          (bartuer-focus)
          (org-entry-put
           (point) "Commit"
           git-link-string)
          (org-clock-out)
          (org-todo 'done)
          ))
      )))

(defun org-export-table-to-html ()
  "export org table to html"
  (interactive)
  (let ((html-content (orgtbl-to-html
                       (org-table-to-lisp)
                       nil)))
    (with-current-buffer (get-buffer-create (format "%s-%s" "html-of" (buffer-name)))
      (goto-char (point-min))
      (kill-region (point-min) (point-max))
      (insert html-content)
      (pop-to-buffer (current-buffer))
      )
    )
  )

(defun org-export-table-to-csv ()
  "export org table to csv"
  (interactive)
  (let ((csv-content (orgtbl-to-csv
                      (org-table-to-lisp)
                      nil)))
    (with-current-buffer (get-buffer-create (format "%s-%s" "csv-of" (buffer-name)))
      (goto-char (point-min))
      (kill-region (point-min) (point-max))
      (insert csv-content)
      (pop-to-buffer (current-buffer))
      )
    )
  )

(defun org-export-table-to-mail-html ()
  "export to mail content"
  (interactive)
  (quoted-printable-encode-string
   (orgtbl-to-html
    (org-table-to-lisp)
    nil)))


(defun org-export-table-to-mail-csv ()
  "export to mail content"
  (interactive)
  (quoted-printable-encode-string
   (orgtbl-to-csv
    (org-table-to-lisp)
    nil)))


(defun org-export-table-to-mail-txt ()
  "export to mail content"
  (interactive)
  (quoted-printable-encode-string
   (buffer-substring-no-properties
    (org-table-begin)
    (org-table-end)
    )))

(defun org-export-table-to-sql (&optional params)
  "export table region to sql insert clause"
  (interactive)
  (let ((data (orgtbl-to-generic
               (org-table-to-lisp)
               (org-combine-plists
                '(:sep ", "
                       :fmt (lambda (s)
                              (if (string-match "^[0-9\.]+$" s)
                                  s
                                (concat "\'" (mapconcat 'identity (split-string s "\'") "\'") "\'"))
                              )
                       :lstart "INSERT INTO replace_me_with_table_name VALUES("
                       :lend ");") 
                params)))
        )
    (with-current-buffer (get-buffer-create "*orgtbl2sql*")
      (kill-region (point-min) (point-max))
      (insert data)
      (sql-mode)
      )    
    )
  (pop-to-buffer "*orgtbl2sql*")
  )

(defvar org-table-export-map
  (let ((map (make-keymap)))
    (define-key map "h" 'org-export-table-to-html)
    (define-key map "c" 'org-export-table-to-csv)
    (define-key map "s" 'org-export-table-to-sql)
    map)
  "convert org table to variant format"
    )

(defun mount-org-table-export-map ()
  "apply `org-table-export-map' to org-table-begin"
  (interactive)
  (when (org-at-table-p)
    (save-excursion
      (goto-char (org-table-begin))
      (put-text-property
       (org-table-begin)
       (+ 1 (org-table-begin))
       'keymap
       org-table-export-map
       ))
    )
  )

(defun org-export-table-to-mail ()
  "send marked node out"
  (interactive)
  (setq org-mail-body
        (let ((multipart-head "--bartuer-emacs-org-table-mail-1\n--bartuer-emacs-org-table-mail-1\nContent-Type: multipart/mixed; boundary=bartuer-emacs-org-table-mail-2\n\n\n\n")
              (attachment-head "--bartuer-emacs-org-table-mail-2\nContent-Disposition: attachment; filename=data.csv\nContent-Type: application/octet-stream; x-unix-mode=0644; name=\"data.csv\"\nContent-Transfer-Encoding: quoted-printable\n\n")
              (text-head "--bartuer-emacs-org-table-mail-2\nContent-Type: text/plain; charset=utf-8;\nContent-Transfer-Encoding: quoted-printable\n\n\n\n")
              (html-head "--bartuer-emacs-org-table-mail-2\nContent-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: quoted-printable\n\n\n\n<html><body><br></br>")
              (html-tail  "</body></html>\n")
              (tail "--bartuer-emacs-org-table-mail-2--\n--bartuer-emacs-org-table-mail-1--")
              )
          (concat
           multipart-head
           attachment-head
           (org-export-table-to-mail-csv)
           "\n\n"
           text-head
           (org-export-table-to-mail-txt)
           "\n"
           html-head
           (org-export-table-to-mail-html)
           html-tail
           tail)
          ))
  (setq org-mail-subject (org-get-heading))
  (compose-mail "m"  org-mail-subject
                (list
                 (cons "CC" "me")
                 (cons "Content-Type" "multipart/alternative; boundary=bartuer-emacs-org-table-mail-1")) nil nil nil)
  (with-current-buffer "*mail*"
    (insert org-mail-body)))

(defun get-entries-in-timeline ()
  "return all properties entries for task under current point"
  (save-excursion
    (push-mark)
    (org-agenda-switch-to)
    (let* ((entries (org-entry-properties (point)))
           (heading (cons "HEADING" (nth 4 (org-heading-components)))))
      (push heading entries)
      (pop-global-mark)
      entries
      )))

(defun org-timeline-next-line ()
  "parse one entry line in TimeLine Agenda View. \\[org-timeline]

Return List which head indicate type of line, \"DAY\", \"TASK\",
\"NULL\", data included in tail:

If current line is date line, return Property List include
keys :year, :month, :day, :week, :weekday.

If current line is task line, return Association List include
cons as (name . value).

If current line is not interesting, there is no tail part.

Bind C-n of org timeline agenda view to:

 (lambda ()
  (interactive)
  (princ (org-timeline-next-line)))
"
  (let ((path (org-agenda-next-line)))
    (cond ((org-get-at-bol 'org-agenda-date-header)
           (let* ((day-info '(:year 2011))
                  (day (org-get-at-bol 'day))
                  (weekp (calendar-iso-from-absolute day))
                  (normalp (calendar-gregorian-from-absolute day))
                  )
             (plist-put day-info :month (pop normalp))
             (plist-put day-info :day (pop normalp))
             (plist-put day-info :year (pop normalp))
             (plist-put day-info :week (pop weekp))
             (plist-put day-info :weekday (pop weekp))
             (plist-put day-info :absolute day)
             (list "DAY" day-info) ))
          ((org-get-at-bol 'org-hd-marker)
           (if path
               (let* ((entries (get-entries-in-timeline))
                      (path (org-substring-no-properties path)))
                 (push (cons "PATH" path) entries)
                 (list "TASK" entries) 
                 )
             (list "TASK" (get-entries-in-timeline)) 
             ))
          (t
           '("NULL"))
          )))

(defun org-timeline-days-bake (obj)
  (cons
   (intern "days")
   (mapcar
    (lambda (ent)
      (let* ((day (car ent)) (tasks (cdr ent)) (effort-total 0))
        (mapcar
         (lambda (e)
           (let ((effort (/ (effort->secs
                             (cdr (assoc "Effort" e)))
                            3600.0)))
             (setq effort-total
                   (+ effort-total
                      effort))))
         tasks)
        (cons
         day
         (list
          (cons
           (intern "tasks_v")
           (vconcat
            (mapcar
             (lambda (e)
               (let ((todo (cdr (assoc "TODO" e)))
                      clock l)
                 (when (and
                        (assoc "CLOCK" e)
                        (assoc "SCHEDULED" e)
                        (string-equal "DONE" todo))
                   (push (cons (intern "path") (cdr (assoc "PATH" e))) l)
                   (push (cons (intern "name") (cdr (assoc "HEADING" e))) l)
                   (push (cons (intern "schedule") (cdr (assoc "SCHEDULED" e))) l)
                   (push (cons (intern "effort")
                               (/ (effort->secs
                                   (cdr (assoc "Effort" e)))
                                  3600.0)) l)
                   (push (cons (intern "value_v")
                               (/ (cdr (assq 'effort l))
                                  effort-total)) l)
                   (setq clock (extract-clock-time
                                (cdr (assoc "CLOCK" e))))
                   (push (cons (intern "beg") (car clock)) l)
                   (push (cons (intern "end") (cdr clock)) l)
                   (push (cons (intern "beg_v") (timestamp->fraction (car clock))) l)
                   (push (cons (intern "end_v") (timestamp->fraction (cdr clock))) l)
                   (let ((clockhistory (assoc "Clockhistory" e)))
                     (when clockhistory
                       (push (cons (intern "Clockhistory")
                                   (string-to-number
                                    (cdr (assoc "Clockhistory" e)))) l)))            
                   (let ((commit (assoc "Commit" e)))
                     (when commit
                       (push (cons (intern "Commit") (cdr commit)) l))) 
                   l)))
             tasks)))
          (cons (intern "year") (get day 'y))
          (cons (intern "month") (get day 'm))
          (cons (intern "week") (get day 'w))
          (cons (intern "weekday") (get day 'wd))
          (cons (intern "day") (get day 'd))
          (cons (intern "absolute") (get day 'a))
          ))
        ))
    obj)
   ))

(defun org-timeline-weeks-bake (days-baked)
  (cons
   (cons
    (intern "weeks")
    (let ((weeks nil))
      (mapcar
       (lambda (day-ent)
         (let* (
                (day-name (car day-ent))
                (week (intern (format "%d %d" (get day-name 'y) (get day-name 'w))))
                (weekday (get day-name 'wd))
                (index (if (= weekday 0)
                           6
                         (- weekday 1)))
                (absolute (get day-name 'a)))
           (unless (assq week weeks)
             (setplist week (list 'w (get day-name 'w) 'm (get day-name 'm) 'y (get day-name 'y)))
             (push
              (cons week
                    (list
                     (cons (intern "tasks_v") (make-vector 7 0))
                     (cons (intern "values_v") (make-vector 7 0))
                     (cons (intern "days")
                           (vconcat
                            (absolute-day-to-that-week absolute)))
                     (cons (intern "month") (get day-name 'm))
                     (cons (intern "year") (get day-name 'y))
                     (cons (intern "week") (get day-name 'w))
                     ))
              weeks)
             )
           (let* ((d (cdr (assq 'tasks_v
                                (cdr day-ent))))
                  (w (cdr (assq week weeks)))
                  (ta (cdr (assq 'tasks_v w)))
                  (v (cdr (assq 'values_v w))))
             (aset ta index (length d))
             (mapcar
              (lambda (task)
                (when task
                  (let ((value_v (cdr (assq 'value_v task))))
                    (if (numberp value_v)
                        (aset v index (+  value_v (aref v index))) 
                      0)
                    )
                  )
                )
              d)
             )))
       (cdr days-baked))
      weeks))
   (list days-baked)))

(defun org-timeline-months-bake (weeks-baked)
  (cons
   (cons
    (intern "months")
    (let ((months nil)
          ;; haven't  calculate the total task
          (project-tasks 300))
      (mapcar
       (lambda (week-ent)
         (let* ((week (car week-ent))
                (year (get week 'y))
                (week-value (cdr week-ent))
                (month (judge-week-to-month (get week 'w) year))
                (month-num (car month))
                (month-name (intern (format "%d-%02d" year (car month))))
                (month-weeks (vconcat (month-weeks month-num year)))
                (index (- (get week 'w) (elt month-weeks 0)))
                (weeks-sum (length month-weeks)))
           (unless (assq month-name months)
             (setplist month-name (list 'm (car month) 'y year))
             (push
              (cons month-name
                    (list
                     (cons (intern "values_v") (make-vector weeks-sum 0))
                     (cons (intern "tasks_v") (make-vector weeks-sum 0))
                     (cons (intern "weeks")
                           (vconcat
                            (mapcar
                             (lambda (w)
                               (format "%d %d" year w)
                               )
                             (append month-weeks nil))) )
                     (cons (intern "year") year)
                     (cons (intern "month") (car month))
                     ))
              months))
           (let* ((tv (cdr (assq 'tasks_v
                                 (cdr
                                  (assq month-name months)))))
                  (vv (cdr (assq 'values_v
                                 (cdr
                                  (assq month-name months)))))
                  (ta (cdr (assq 'tasks_v week-value)))
                  (total-task 0)
                       )
                  (mapcar
                   (lambda (task-count)
                     (setq total-task
                           (+ total-task task-count)))
                   (append ta nil))
                  (aset tv index total-task)
                  (aset vv index (/ (/ total-task 1.0) project-tasks))
           ))
       )
       (reverse (cdr (assq 'weeks weeks-baked)))
      )
      months
      )
   )
   weeks-baked
  ))

(defun org-timeline-to-json ()
  "parse org in TimeLine Agenda View.
see \\[org-timeline] and `org-timeline-next-line'"
  (interactive)
  (goto-char (point-min))
  (let ((day nil)
        (tasks nil)
        (day-key nil)
        (result nil))
    (while (< (point) (point-max))
      (let* ((info (org-timeline-next-line))
             (type (car info))
             (value (if type
                        (car-safe (cdr info))
                      nil)))
        (cond ((string-equal type "DAY")
               (setq day value)
               (when tasks
                 (let ((day-value (vconcat tasks)))
                   (setq result (assq-delete-all day-key result))
                   (push (cons day-key day-value) result))
                 )
               (setq tasks nil))
              ((string-equal type "TASK")
               (let* ((day-symbol
                       (intern
                        (format "%04d-%02d-%02d %s"
                                (plist-get day :year)
                                (plist-get day :month)
                                (plist-get day :day)
                                (nth (plist-get day :weekday)
                                     '("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
                                )))
                      (has-record (assoc day-symbol result)))
                 (if has-record
                     (push value tasks)
                   (setq tasks (list value))
                   (setq day-key day-symbol)
                   (let ((yv (plist-get day :year))
                         (mv (plist-get day :month))
                         (dv (plist-get day :day))
                         (wv (plist-get day :week))
                         (wday (plist-get day :weekday))
                         (av (plist-get day :absolute)))
                     (setplist day-key (list 'd dv 'm mv 'y yv 'w wv 'wd wday 'a av)))
                   (push (cons day-symbol tasks) result)
                   )))
              (t
               (when (and
                      (= (point) (point-max))
                      tasks)
                 (let ((day-value (vconcat tasks)))
                   (setq result (assq-delete-all day-key result))
                   (push (cons day-key day-value) result)) 
                 )
               nil)
              )))
    (if (and nil
             (fboundp 'json-encode))
        (json-encode                    ; hard to create recursive dict use alist/plist/hash
         (org-timeline-months-bake
          (org-timeline-weeks-bake
           (org-timeline-days-bake result))))
      (org-timeline-months-bake
          (org-timeline-weeks-bake
           (org-timeline-days-bake result)))
      )))

(defun occur-all-org (regexp &optional nlines)
  (interactive (occur-read-primary-args))
  (let ((bufs (cons (get-file-buffer "~/org/note.org")
                    (cons (get-file-buffer "~/org/note.org_archive")
                          (mapcar 'get-file-buffer org-agenda-files)))))
    (occur-1 regexp nlines bufs))
  )

(defun clock-sum-line ()
  (let ((clockhistory (read (org-entry-get (point) "Clockhistory"))))
    (concat "#+TBLFM: $4='(convert-time-to-minutes $2)::@"
            (format "%d" (+ clockhistory 1))
            "$4=vsum(@1..@"
            (format "%d" clockhistory)
            ")/60;%.2f"
            ))
  )

(defun clockhistory-init ()
  (interactive)
  (org-entry-put (point) "Clockhistory" "1")
  (org-entry-put (point) "Clock1" (concat "|" (org-entry-get (point) "CLOCK") "|init|"))
  (search-forward ":Clock1:")
  (back-to-indentation)
  (insert "|")
  (end-of-line)
  (open-line 1)
  (forward-line)
  (insert "|||")
  (back-to-indentation)
  (indent-relative-maybe)
  (end-of-line)
  (open-line 1)
  (forward-line)
  (insert (clock-sum-line))
  (back-to-indentation)
  (indent-relative-maybe)
  (end-of-line)
  )
  
(defun org-clockhistory-insert ()
  "insert current clock record to history table"
  (interactive)
  (if (org-entry-get (point) "Clockhistory")
      (progn
        (let* ((his (org-entry-get (point) "Clockhistory"))
               (his-num (read his))
               (clock (org-entry-get (point) "CLOCK")))

          (unless (org-at-heading-p)
            (outline-previous-visible-heading 1))
          (search-forward "Clockhistory")
          (forward-line his-num)
          (end-of-line)
          (newline)
          (insert (concat
                   "| "
                   ":Clock"
                   (format "%d" (+ 1 his-num))
                   ": | "
                   clock
                   "|"
                   ))
          (yas/expand)
          (org-entry-put (point) "Clockhistory" (format "%d" (+ 1 his-num)) )
          )
        (let ((end-pos (save-excursion 
                         (search-forward ":END:" nil t 1)
                         (point)))
              )
          (unless (replace-regexp "#\\+TBLFM:.*$" (clock-sum-line) nil (point) end-pos)
            (message "%s" (clock-sum-line))
            ))  
        )
    (clockhistory-init)
    )
  )

(defun bartuer-org-load ()
  "for org mode"
  (defalias 'ar 'bartuer-jump-to-archive)
  (defalias 'clk 'org-clock-goto)
  (global-set-key "\C-cl" 'org-store-link)
  (global-set-key "\C-ca" 'org-agenda)
  (global-set-key "\C-ci" 'bartuer-focus)
  (global-set-key "\C-cb" 'org-sparse-tree)
  (global-set-key "\C-cu" 'org-insert-link-global)
  (global-set-key "\C-co" 'org-open-at-point-global)
  (turn-on-font-lock)
  (define-key org-mode-map "\C-\M-u" (lambda ()
                                       (interactive)
                                       (org-up-heading-safe)))
  (define-key org-mode-map "\C-j" 'org-meta-return)
  (define-key org-mode-map "\C-c\C-a" 'org-archive-subtree)
  (define-key org-mode-map "\C-\M-i" 'org-table-previous-field)
  (define-key org-mode-map "\C-c\C-k" 'kill-region)
  (define-key org-mode-map "\C-c\C-q" 'org-export-table-to-sql)
  (define-key org-mode-map "\C-\M-h" 'outline-mark-subtree)
  (define-key org-mode-map "\C-xm" 'mail-dwim)
  (define-key org-mode-map "\M-/" 'org-table-sort-lines)
  (define-key org-mode-map "[" (lambda ()
                                 (interactive)
                                 (insert "[ ] ")
                                 (org-update-statistics-cookies t)))
  (define-key org-mode-map "]" (lambda ()
                                 (interactive)
                                 (insert " [0/0]")
                                 (org-update-statistics-cookies t)))
  (define-key org-mode-map "<backtab>" 'org-shifttab)
  (define-key org-mode-map "\C-\M-c" 'bartuer-org-insert-child)
  ;; add a hook when saving also export to a html
  ;; setup a webserver, can quick access one page org content locally
  (setq org-link-abbrev-alist
        '(("gfcn" . "http://www.google.com/finance?fstype=ii&q=%s&gl=cn")
          ("gf" . "http://www.google.com/finance?q=%s")
          ("rt" . "http://www.reuters.com/finance/stocks/overview?symbol=%s")))
  (add-to-list 'org-property-allowed-value-functions 'org-effort-allowed-property-values)
)

(defun add-to-agenda ()
  (interactive)
  (if (and (eq 'org-mode major-mode)
           (not (eq nil (buffer-file-name)))
           )
      (progn  (add-to-list 'org-agenda-files (buffer-file-name))
             (customize-save-variable 'org-agenda-files org-agenda-files)))
  )

(provide 'bartuer-org)