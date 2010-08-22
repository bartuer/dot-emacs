(defun bartuer-org-insert-child ()
  "insert a child"
  (interactive)
  (org-insert-heading-after-current)
  (org-do-demote))

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
        )))

(defun bartuer-jump-to-archive ()
  "jump from org to it's archive file"
  (interactive)
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
          (git-link-string (shell-command-to-string (concat "tag-head " clock-task-string))))
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
  (define-key org-mode-map "\C-\M-h" 'outline-mark-subtree)
  (define-key org-mode-map "[" (lambda ()
                                 (interactive)
                                 (insert "[ ] ")))
  (define-key org-mode-map "]" (lambda ()
                                 (interactive)
                                 (insert " [0/0]")))
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

(provide 'bartuer-org)