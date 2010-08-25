(defun video-note ()
  "write down video comment:"
  (interactive)
  (org-timer-pause-or-continue)
  (if org-timer-pause-time
      (progn
        (shell-command "/Users/bartuer/scripts/pause")
        (org-timer))
    (shell-command "/Users/bartuer/scripts/play")
    (insert "\n")
    )
)

(defcustom video-minor-mode-string " video" 
  "String to display in mode line when video note mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  )

(define-minor-mode video-minor-mode
  "Minor mode take note when see video"
  :lighter video-minor-mode-string
  (cond
   (video-minor-mode
    (define-key org-mode-map "\C-j" 'video-note)
    (shell-command "/Users/bartuer/scripts/play")
    (org-timer-start)
    )
   (t
    (define-key org-mode-map "\C-j" 'org-meta-return)
    (org-timer-stop)
    )))

(provide 'video)