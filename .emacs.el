(setq custom-file "~/etc/el/bartuer-custom.el")
(load custom-file)

(if(fboundp 'menu-bar-mode) (menu-bar-mode -1))
(if(fboundp 'tool-bar-mode) (tool-bar-mode -1))
(if(fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(fset 'yes-or-no-p 'y-or-n-p)
(put 'set-goal-column 'disabled nil)
(setq-default source-directory (expand-file-name "~/src/emacs/emacs/"))
(setq-default major-mode 'text-mode)

(defalias 'p 'finder-commentary)
(defalias 'c 'emacs-lisp-byte-compile)
(add-to-list 'load-path (expand-file-name "~/etc/el/icicles"))
(add-to-list 'load-path (expand-file-name "~/etc/el"))

(defalias 'g 'global-set-key)
(defalias 'l 'local-set-key)
(global-set-key "\C-w" 'backward-kill-word) ;for case <BS> does not mean <DEL>,anywhere
(global-set-key "\C-c\C-k" 'kill-region) ;for case <BS> does not mean <DEL>,anywhere
(global-set-key "\C-ck" 'kill-region) ;delete to the beginning "\C-x-DEL",move 1
(global-set-key "\C-xk" 'kill-whole-line) ;delete whole line, move 1
(global-set-key "\r" 'newline-and-indent) ;depend on if this line is a comment

(global-set-key "\C-\M-y" 'mark-sexp)

(defun kill-whole-sexp(keep-this)
  (interactive "P")
  (if (eq keep-this '-)
      (kill-backward-up-list)
  (progn
    (backward-up-list)
    (kill-sexp))))
(global-set-key "\C-x\M-k" 'kill-whole-sexp)

(defun kill-whole-sentene()
  (interactive)
  (backward-kill-sentence)
  (kill-sentence))
(global-set-key "\C-x\C-\M-k" 'kill-whole-sentene)

(defun meta-n-dwim()
  "multiple bindings for M-n"
  (interactive)
  (if (windowp (car (window-tree)))
      (forward-paragraph)               ;M-]
    (scroll-other-window 10)))          ;C-M-v
(global-set-key "\M-n" 'meta-n-dwim)
(if(require 'info nil t)
    (add-hook
     'Info-mode-hook
     (lambda()
       (define-key Info-mode-map "\M-n" 'meta-n-dwim))))

(defun meta-p-dwim()
  "multiple bindings for M-p"
  (interactive)
  (if (windowp (car (window-tree)))
      (backward-paragraph)
    (scroll-other-window -10)))
(global-set-key "\M-p" 'meta-p-dwim)

(defun ctrl-meta-n-dwim()
  "multiple bindings for C-M-n"
  (interactive)
  (if (windowp (car (window-tree)))
      (forward-list)
    (next-error)))
(global-set-key "\C-\M-n" 'ctrl-meta-n-dwim)

(defun ctrl-meta-p-dwim()
  "multiple bindings for C-M-p"
  (interactive)
  (if (windowp (car (window-tree)))
      (backward-list)
    (previous-error)))
(global-set-key "\C-\M-p" 'ctrl-meta-p-dwim)

(defalias 'f 'auto-fill-mode)

(global-set-key "\C-j" 'eval-last-sexp)
(defalias 'e 'eval-current-buffer)

(add-hook 'shell-mode-hook
          (lambda ()
            (ansi-color-for-comint-mode-on)))
(add-hook 'comint-mode-hook
          (lambda ()
            (ansi-color-for-comint-mode-on)))
(global-set-key [(f5)] 'shell-command)
(global-set-key "\M-3" 'shell-command)
(global-set-key "\M-1" 'shell)

(add-hook 'dired-load-hook (lambda () (load "dired-x")))
(global-set-key "\M-2" 'find-file)
(defalias 'ff 'find-file-at-point)

(require 'ibuffer nil t)
(when (fboundp 'ibuffer)
  (defalias 'j 'ibuffer))
(global-set-key "\M-=" 'switch-to-buffer)
(global-set-key "\M-l" 'switch-to-buffer)
(global-set-key "\M-4" 'kill-buffer-and-window)
(global-set-key "\C-\M-j" 'save-buffer)
(global-set-key "\C-xc" 'copy-to-buffer)
(global-set-key "\C-xa" 'append-to-buffer)

(defun meta-space-dwim()
  "multiple bindings for M-SPC"
  (interactive)
  (if (windowp (car (window-tree)))
      (just-one-space)
    (delete-other-windows)))
(global-set-key "\M- " 'meta-space-dwim)
(global-set-key "\M-k" 'other-window)
(global-set-key "\M-o" 'kill-sentence)
(global-set-key [(prior)] 'scroll-other-window-down)
(global-set-key [(next)] 'scroll-other-window)

(defun f1()
  "select the first frame "
  (interactive)
  (select-frame-by-name "F1"))
(global-set-key "\C-z" 'f1)
(defun f2()
  "select frame 2"
  (interactive)
  (select-frame-by-name "F2"))
(global-set-key [(f2)] 'f2)
(defun f3()
  "select frame 3"
  (interactive)
  (select-frame-by-name "F3"))
(global-set-key [(f3)] 'f3)
(defun f4()
  "select frame 4"
  (interactive)
  (select-frame-by-name "F4"))
(global-set-key [(f4)] 'f4)
(defalias 'fr 'make-frame)

(global-set-key "\M-8" 'find-dired)
(global-set-key [(f8)] 'grep-find)
(global-set-key "\M-9" 'grep-find)
(global-set-key [(f9)] 'list-matching-lines)
(global-set-key "\M-0" 'list-matching-lines)
(global-set-key "\C-\M-s" 'isearch-forward)
(global-set-key "\C-\M-r" 'isearch-backward)
(global-set-key "\C-s" 'isearch-forward-regexp)
(global-set-key "\C-r" 'isearch-backward-regexp)
(defalias 'h 'how-many)
(defalias 'q 'query-replace-regexp)

(global-set-key [(f7)] 'man-follow)
(defalias 'm 'woman)
(defalias 'a 'apropos)                  ;C-u C-h a for command and function

(require 'dict nil t)
(defun mydict (word)
  "Lookup a WORD in the dictionary."
  (interactive (list (dict-default-dict-entry)))
  (if (string= word "")
      (error "No dict args given"))
  (dict-get-answer word))
(when (fboundp 'dict-get-answer)
  (global-set-key "\C-\M-m" 'mydict)
  (add-hook 'view-mode-hook
            (lambda ()
              (define-key view-mode-map "\M-j" 'mydict))))

(if (fboundp 'server-start)
    (server-start))
(if (fboundp 'desktop-read)
    (desktop-read))
(if (fboundp 'show-paren-mode)
    (show-paren-mode 1))

(global-set-key "\M-/" 'hippie-expand)
(global-set-key "\M-j" 'dabbrev-expand)

(require 'icicles nil t)
(global-set-key [(f6)] 'icicle-complete-keys)
(defun bartuer-icicle-key-map()
  (when icicle-mode
    (let ((map minibuffer-local-completion-map))
      (define-key map [(f1)] 'icicle-completion-help) 
      (define-key map "M-o" 'icicle-erase-minibuffer-or-history-element)
      (define-key map "\M-v" 'icicle-switch-to-Completions-buf)
      (define-key map "\C-w" 'backward-kill-word)
      (define-key map "\C-\M-y" 'icicle-apropos-complete-and-narrow)
      (define-key map "\C-\M-i" 'icicle-apropos-complete)
      (define-key map "\C-i" 'minibuffer-complete)
      (define-key map " " 'minibuffer-complete-word)
      (define-key map "\C-j" 'exit-minibuffer)
      (define-key map "\C-s" 'icicle-narrow-candidates)
      (define-key map "\M-l" 'switch-to-buffer)
      (define-key map "\M-k" 'other-window)
      (define-key map "\C-\M-n" 'icicle-retrieve-previous-input)
      (define-key map "\C-\M-p" 'icicle-retrieve-next-input)
      (define-key map "\C-n" 'icicle-help-on-next-apropos-candidate)
      (define-key map "\C-p" 'icicle-help-on-previous-apropos-candidate))))
(add-hook 'icicle-mode-hook 'bartuer-icicle-key-map)
(when(fboundp 'icy-mode) 
  (defalias 'i 'icy-mode)
  (icy-mode))

(require 'icomplete nil t)
(when (fboundp 'icomplete-mode)
  (setq-default icomplete-mode t)
  (icomplete-mode 1))

(require 'complete nil t)
(when (fboundp 'partial-completion-mode)
  (setq-default partial-completion-mode t)
  (partial-completion-mode 1))

(require 'ido nil t)
(when (fboundp 'ido-mode)
  (setq-default ido-mode 'both)
  (ido-mode 1))

(autoload 'bartuer-general-todo-list "bartuer-todo-list.el"
  "list bugs will be fixed,or wishes will be done in bartuer's
  dot emacs files, \\[bartuer-general-todo-list]," t nil)
(global-set-key "\C-h\C-b" 'bartuer-general-todo-list)

(defun bartuer-general-byte-compile-dot-file ()
  "add this function to `after-save-hook', let dot file automaticlly
  compiled when saving"
  (when (string-equal user-init-file buffer-file-name)
    ;; if compile failed, no compiled elder version exist
    (when (file-exists-p (concat user-init-file "c"))
      (delete-file (concat user-init-file "c")))
    (byte-compile-file user-init-file)
    (message "Emacs dot file compiled.")))
(add-hook 'after-init-hook (lambda ()
                             (add-hook 'after-save-hook 'bartuer-general-byte-compile-dot-file t nil)
                             ))

(autoload 'bartuer-c-common "bartuer-c.el" "for c and c++ language" t)
(add-hook 'c-mode-common-hook 'bartuer-c-common)

(autoload 'bartuer-clearcase-load "bartuer-clearcase.el" "for clearcase" t)
(defalias 'cc 'bartuer-clearcase-load)
