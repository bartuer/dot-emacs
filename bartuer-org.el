(defun bartuer-org-load ()
  "for org mode"
  (global-set-key "\C-cl" 'org-store-link)
  (global-set-key "\C-ca" 'org-agenda)
  (global-set-key "\C-cb" 'org-iswitchb)
  (turn-on-font-lock)
  (define-key org-mode-map "\C-j" 'org-meta-return)
  (define-key org-mode-map "<backtab>" 'org-shifttab)
  (define-key org-mode-map "\C-\M-c" 'first-child)
  ;; add a hook when saving also export to a html
  ;; setup a webserver, can quick access one page org content locally
)