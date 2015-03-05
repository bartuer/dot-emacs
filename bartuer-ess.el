
(eval-and-compile
  (defconst ess-help-section-regexp "^\\([A-Z][A-Za-z0-9 /-:]+\\)$"
    ))

(defun bartuer-ess-load ()
  "for statistic language
"
  (interactive)
  (require 'ess-site nil t)
  ;; match three part (function keyword, the arglist, beginning of
  ;; clauses) of a function define at the functin begin line
  ;; now the move by function method does not work well, basically it
  ;; can be resolved a bit by this hack or better method show below ,
  ;; using the ess-eval-function-or-paragraph-and-step

  ;; just M-x R, start inferior R process
  (setq ess-function-pattern "\\(^ ?function\\|^.*<- function\\)\\( ?([^)]*)\\)\\( ?[^{].*$\\|{.*}\\)")
  (flyspell-mode)
  (define-key ess-mode-map "\C-j" 'ess-eval-line-and-step)
  (define-key ess-mode-map "\C-u\C-j" 'ess-eval-line)
  (define-key ess-mode-map "\C-c\C-c" 'ess-eval-function-or-paragraph-and-step)
  (define-key ess-mode-map "\C-\M-x" 'ess-eval-region)
  (define-key ess-mode-map "\C-u\C-\M-x" 'ess-eval-region-and-go)
  (define-key ess-mode-map "\C-\M-i" 'ess-list-object-completions)
  (define-key ess-mode-map "\M--" 'ess-smart-underscore)
  (define-key ess-mode-map [(f7)] 'ess-display-help-on-object)
  )

(defun bartuer-ess-help-load ()
  "for ess help buffer"
  (interactive)
  (setq imenu-generic-expression (list (list nil ess-help-section-regexp 0)))
  (define-key ess-help-mode-map "A" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "a" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "N" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "d" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "D" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "e" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "E" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "e" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "R" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "r" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "S" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "s" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "U" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "u" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "V" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "v" 'ess-skip-to-help-section)
  (define-key ess-help-mode-map "\C-j" 'ess-eval-line)
  (define-key ess-help-mode-map "\C-u\C-j" 'ess-eval-line-and-step)
  (define-key ess-help-mode-map "\C-\M-x" 'ess-eval-region)
  (define-key ess-help-mode-map "\C-u\C-\M-x" 'ess-eval-region-and-go)
  )

