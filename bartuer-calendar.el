(defun bartuer-calendar-load ()
  "for calendar mode"
  (define-key calendar-mode-map "\M-f" 'calendar-forward-month)
  (define-key calendar-mode-map "\M-b" 'calendar-backward-month)
  (define-key calendar-mode-map "\C-\M-f" 'calendar-forward-year)
  (define-key calendar-mode-map "\C-\M-b" 'calendar-backward-year)
  (define-key calendar-mode-map "C-u-." 'calendar-goto-date)
  )