;;; TODO
; fix company completion :
; bind omnisharp-helm-find-usages :
; bind omnisharp-helm-find-symbols :
; add other navigation bindings chord + anything + helm? :

;; omnisharp--jump-to-enclosing-func
;; omnisharp--popup-to-ido
;; omnisharp-add-dot-and-auto-complete 	omnisharp-add-reference
;; omnisharp-add-to-solution-current-file
;; omnisharp-add-to-solution-dired-selected-files
;; omnisharp-auto-complete
;; omnisharp-auto-complete-overrides
;; omnisharp-build-in-emacs
;; omnisharp-check-alive-status
;; omnisharp-check-ready-status
;; omnisharp-code-format
;; omnisharp-current-type-documentation
;; omnisharp-current-type-information
;; omnisharp-current-type-information-to-kill-ring
;; omnisharp-find-implementations
;; omnisharp-find-usages
;; omnisharp-fix-code-issue-at-point
;; omnisharp-fix-usings
;; omnisharp-go-to-definition
;; omnisharp-go-to-definition-other-window
;; omnisharp-helm-find-symbols
;; omnisharp-helm-find-usages
;; omnisharp-imenu-create-index
;; omnisharp-mode
;; omnisharp-mode-menu
;; omnisharp-navigate-to-current-file-member
;; omnisharp-navigate-to-current-file-member-other-window
;; omnisharp-navigate-to-region
;; omnisharp-navigate-to-region-other-window
;; omnisharp-navigate-to-solution-file
;; omnisharp-navigate-to-solution-file-then-file-member
;; omnisharp-navigate-to-solution-member
;; omnisharp-navigate-to-type-in-current-file
;; omnisharp-reload-solution
;; omnisharp-remove-from-project-current-file
;; omnisharp-remove-from-project-dired-selected-files
;; omnisharp-rename
;; omnisharp-rename-interactively
;; omnisharp-run-code-action-refactoring
;; omnisharp-show-last-auto-complete-result
;; omnisharp-show-overloads-at-point
;; omnisharp-start-omnisharp-server
;; omnisharp-stop-server
;; omnisharp-unit-test-all
;; omnisharp-unit-test-fixture
;; omnisharp-unit-test-single

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
  )

(provide 'bartuer-csharp)