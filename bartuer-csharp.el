;; omnisharp--jump-to-enclosing-func
;; omnisharp-current-type-information-to-kill-ring

;; omnisharp-run-code-action-refactoring
;; omnisharp-fix-usings

;; omnisharp-start-omnisharp-server
;; omnisharp-stop-server
;; omnisharp-check-alive-status
;; omnisharp-check-ready-status
;; omnisharp-reload-solution

(defun csharp-imenu-create-index ()
  (omnisharp-imenu-create-index))

(defun bartuer-csharp-load ()
  (interactive)
  (eldoc-mode t)
  (omnisharp-mode t)
  (yas-minor-mode-on)
  (omnisharp--init-imenu-support) 
  (setq indent-tabs-mode t)
  (smart-tabs-mode-enable)
  (smart-tabs-advice bartuer-c-indent c-basic-offset)
  (c-set-style "c#")
  (define-key csharp-mode-map "\C-\M-m" 'omnisharp-navigate-to-solution-member)
  (define-key csharp-mode-map "\C-\M-i" 'omnisharp-add-dot-and-auto-complete)
  (define-key csharp-mode-map "\C-j" 'omnisharp-build-in-emacs)
  (key-chord-define csharp-mode-map "uu" 'omnisharp-helm-find-usages)
  (key-chord-define csharp-mode-map "ss" 'omnisharp-helm-find-symbols)
  (key-chord-define csharp-mode-map "mm" 'helm-imenu)
  (key-chord-define csharp-mode-map "ff" 'omnisharp-navigate-to-solution-file-then-file-member)
  (key-chord-define csharp-mode-map "dd" 'omnisharp-go-to-definition-other-window)
  (key-chord-define csharp-mode-map "rr" 'omnisharp-add-reference)
  (key-chord-define csharp-mode-map "ii" 'omnisharp-current-type-documentation)
  (key-chord-define csharp-mode-map "tt" 'omnisharp-navigate-to-type-in-current-file)
  (key-chord-define csharp-mode-map "oo" 'omnisharp-show-overloads-at-point)
  (key-chord-define csharp-mode-map "cc" 'omnisharp-fix-code-issue-at-point)

  (key-chord-define csharp-mode-map "mv" 'omnisharp-rename)
  (key-chord-define csharp-mode-map "ts" 'omnisharp-unit-test-single)
  (key-chord-define csharp-mode-map "ta" 'omnisharp-unit-test-all)
  (key-chord-define csharp-mode-map "tf" 'omnisharp-unit-test-fixture)
  (key-chord-define csharp-mode-map "af" 'omnisharp-add-to-solution-current-file)
  (key-chord-define csharp-mode-map "rf" 'omnisharp-remove-from-project-current-file)
)

(provide 'bartuer-csharp)