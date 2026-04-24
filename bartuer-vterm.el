;;; bartuer-vterm.el --- vterm configuration (vendored, Arcadia devcontainer)

;;; Commentary:
;; emacs-libvterm is built and vendored into ~/etc/el/vendor/vterm/ by the
;; Arcadia Dockerfile:
;;   build/emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/Dockerfile
;; See plan: .github/REPL/01.vterm.tui.org.txt
;;
;; Two files are shipped by the tarball:
;;   ~/etc/el/vendor/vterm/vterm.el
;;   ~/etc/el/vendor/vterm/vterm-module.so
;;
;; The module requires an Emacs built with --with-modules.  The Arcadia
;; Emacs Dockerfile sets that flag explicitly.

;;; Code:

(let ((vterm-dir (expand-file-name "~/etc/el/vendor/vterm")))
  (when (file-directory-p vterm-dir)
    (add-to-list 'load-path vterm-dir)))

(autoload 'vterm "vterm" "Launch vterm in the current buffer." t)
(autoload 'vterm-other-window "vterm" "Launch vterm in another window." t)

(with-eval-after-load 'vterm
  ;; Big scrollback so Copilot CLI / other TUI output isn't truncated.
  (setq vterm-max-scrollback 100000
        ;; Lower redraw latency — matters a lot for Ink-based TUIs
        ;; (ghcp CLI, ink-react apps) where the default 0.1 causes
        ;; visible repaint stalls.
        vterm-timer-delay 0.01
        ;; Kill the buffer (don't keep dead prompt) when the shell exits.
        vterm-kill-buffer-on-exit t)

  ;; Use system kill-ring yank inside vterm — otherwise C-y sends the
  ;; literal keystroke to the underlying shell.
  (define-key vterm-mode-map (kbd "C-y") #'vterm-yank)
  (define-key vterm-mode-map (kbd "M-y") #'vterm-yank-pop)
  ;; C-c C-t is the canonical vterm-copy-mode toggle; keep it bound.
  (define-key vterm-mode-map (kbd "C-c C-t") #'vterm-copy-mode))

(provide 'bartuer-vterm)
;;; bartuer-vterm.el ends here
