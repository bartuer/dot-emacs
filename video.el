(defun subtitle-timer (&optional restart)
  "Insert a H:MM:SRT string from the timer into the buffer.
1
00:00:03,001 --> 00:00:07,001
三国演义

2
0:00:07,000 --> 0:00:15,000
吕布
"
  (interactive "P")
  (if (equal restart '(4)) (org-timer-start))
  (or org-timer-start-time (org-timer-start))
  (insert (format "\n%d\n" subtitle-seq))
  (insert (format "%s,000 --> %s,000\n"
                  (org-timer-secs-to-hms (floor (org-timer-seconds)))
                  (org-timer-secs-to-hms (floor (+ (org-timer-seconds)
                                                   3)))))
  (setq subtitle-seq (+ 1 subtitle-seq)))
  

(defun video-note ()
  "write down video comment"
  (interactive)
  (org-timer-pause-or-continue)
  (if org-timer-pause-time
      (progn
        (shell-command "/Users/bartuer/scripts/pause")
        (subtitle-timer))
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
    (define-key text-mode-map "\C-j" 'video-note)
    (setq subtitle-seq 1)
    (shell-command "/Users/bartuer/scripts/play")
    (org-timer-start)
    )
   (t
    (define-key text-mode-map "\C-j" 'org-meta-return)
    (org-timer-stop)
    )))

(provide 'video)
