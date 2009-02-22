(defun bartuer-ess-load ()
  "for statistic language
"
  (require 'ess-site nil t)
  ;; match three part (function keyword, the arglist, beginning of
  ;; clauses) of a function define at the functin begin line
  ;; now the move by function method does not work well, basically it
  ;; can be resolved a bit by this hack or better method show below ,
  ;; using the ess-eval-function-or-paragraph-and-step
  (setq ess-function-pattern "\\(^ ?function\\|^.*<- function\\)\\( ?([^)]*)\\)\\( ?[^{].*$\\|{.*}\\)")
  (flyspell-mode)
  (define-key ess-mode-map "\C-j" 'ess-eval-line)
  (define-key ess-mode-map "\C-u\C-j" 'ess-eval-line-and-step)
  (define-key ess-mode-map "\C-c\C-c" 'ess-eval-function-or-paragraph-and-step)
  (define-key ess-mode-map "\C-\M-x" 'ess-eval-region)
  (define-key ess-mode-map "\C-u\C-\M-x" 'ess-eval-region-and-go)
  (define-key ess-mode-map "\C-\M-i" 'ess-list-object-completions)
  (define-key ess-help-mode-map "\C-j" 'ess-eval-line)
  (define-key ess-help-mode-map "\C-u\C-j" 'ess-eval-line-and-step)
  (define-key ess-help-mode-map "\C-\M-x" 'ess-eval-region)
  (define-key ess-help-mode-map "\C-u\C-\M-x" 'ess-eval-region-and-go)
  (define-key ess-mode-map [(f7)] 'ess-display-help-on-object))
