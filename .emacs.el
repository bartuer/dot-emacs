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
(global-set-key "\C-i" '(lambda ()
                          (interactive)
                          (if (not (window-minibuffer-p))
                              (cond ((indent-for-tab-command))
                                    (t (indent-relative-maybe))
                                    (t (indent-for-comment))))))

(defun mark-whole-sexp(&optional arg)
  "Mark sexp contain the point, \\[mark-whole-sexp]

If give a positive ARG, mark sexp ARG levels outside from point.
  Using \\[repeat] mark one level once.

If give a negative ARG, will undo the last mark action, thus the
  inner level sexp is marked.  There is no difference between
  negative variant.  "
  (interactive "p")
  (unless arg (setq arg 1))
  (cond ((> arg 0)
         (progn
           (unless (eq (syntax-class (syntax-after (point))) 4)
             (backward-up-list arg))
           (mark-sexp 1)))
        ((< arg 0)
         (when (not (and transient-mark-mode mark-active))
           (error "Cannot cancel sexps mark without marked sexp"))
         (set-mark-command 0)
         (set-mark-command 0)
         (backward-sexp)
         (down-list)
         (when (scan-lists (point) 1 -1)
           (mark-whole-sexp)))))

(global-set-key "\C-cc" 'mark-whole-sexp)
(global-set-key "\C-c\C-c" 'mark-whole-sexp)
(global-set-key "\C-cp" 'mark-whole-sexp)
(global-set-key "\C-c\C-p" 'mark-whole-sexp)

(defun mark-whole-sentence (&optional arg)
  "\\[mark-whole-sentence], Steal from `mark-paragraph'"
  (interactive "p")
  (unless arg (setq arg 1))
  (when (zerop arg)
    (error "Cannot mark zero sentences"))
  (cond ((or (and (eq last-command this-command) (mark t))
		  (and transient-mark-mode mark-active))
	 (set-mark
	  (save-excursion
	    (goto-char (mark))
	    (forward-sentence arg)
	    (point))))
	(t
	 (forward-sentence arg)
	 (push-mark nil t t)
	 (backward-sentence arg))))
(global-set-key "\C-cs" 'mark-whole-sentence)
(global-set-key "\C-x\M-s" 'mark-whole-sentence)

(defun kill-whole-sexp(keep-this)
  (interactive "P")
  (if (eq keep-this '-)
      (kill-backward-up-list)
  (progn
    (backward-up-list)
    (kill-sexp))))
(global-set-key "\C-x\C-\M-k" 'kill-whole-sexp)

(defun kill-whole-sentence()
  (interactive)
  (backward-kill-sentence)
  (kill-sentence))
(global-set-key "\C-x\M-k" 'kill-whole-sentence)

(global-set-key "\C-x\M-t" 'transpose-sentences)
(global-set-key "\C-x\C-\M-t" 'transpose-paragraphs) ;\C-\M-t bind transpose-sexps

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
            (ansi-color-for-comint-mode-on)
            (define-key shell-mode-map "\C-\M-i"
              'shell-dynamic-complete-environment-variable)
            ))
(add-hook 'comint-mode-hook
          (lambda ()
            (ansi-color-for-comint-mode-on)))
(global-set-key [(f5)] 'compile)
(global-set-key "\M-3" 'shell-command)
(global-set-key "\M-1" 'shell)

(add-hook 'dired-load-hook (lambda () (load "dired-x")))
(global-set-key "\M-8" 'find-file)
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

(require 'winner nil t)
(defun meta-space-dwim()
  "multiple bindings for M-SPC"
  (interactive)
  (if (windowp (car (window-tree)))
      (winner-undo)
    (delete-other-windows)))
(global-set-key "\M- " 'meta-space-dwim)

(global-set-key "\M-k" 'other-window)
(if (require 'diff-mode nil t)
    (add-hook 'diff-mode-hook
              (lambda ()
                (define-key diff-mode-map "\M-k" 'other-window)
                (define-key diff-mode-map "\M-h" 'diff-hunk-kill))))
(global-set-key "\M-o" 'kill-sentence)

(global-set-key [(prior)] 'scroll-other-window-down)
(global-set-key [(next)] 'scroll-other-window)

(defun f1()
  "select the first frame "
  (interactive)
  (select-frame-by-name "F1"))

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

(global-set-key "\M-9" 'grep-find)
(global-set-key [(f9)] 'grep-find)
(global-set-key "\M-0" 'list-matching-lines)
(global-set-key "\C-\M-s" 'isearch-forward)
(global-set-key "\C-\M-r" 'isearch-backward)
(global-set-key "\C-s" 'isearch-forward-regexp)
(global-set-key "\C-r" 'isearch-backward-regexp)
(defalias 'q 'query-replace-regexp)

(global-set-key [(f7)] 'man-follow)
(global-set-key [(f8)] 'info-lookup-symbol)
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
(if (fboundp 'winner-mode)
    (winner-mode 1))
(if (fboundp 'which-function-mode)
    (which-function-mode 1))

(require 'auto-install nil t)

(require 'ispell nil t)
(if (fboundp 'ispell-region)
    (progn
     (ispell-region (point-min) (point-min))
     (global-set-key "\C-x\C-\M-i" 'ispell-complete-word)
     ))

(global-set-key "\M-i" 'hippie-expand)
(global-set-key "\M-j" 'dabbrev-expand)
(global-set-key "\M-/" 'tab-to-tab-stop)

;; if the major mode has bind M-TAB to complete symbol, then
;; flyspell-auto-correct-word will bind to C-c M-TAB , if major mode not
;; using M-TAB, then M-TAB is flyspell-auto-correct-word
(autoload 'bartuer-flyspell-load "bartuer-flyspell.el" "flyspell modification")
(add-hook 'flyspell-mode-hook 'bartuer-flyspell-load)

;; M-TAB do the tags and symbol complete
(defalias 'tl (quote (lambda ()
                       (interactive)
                       (list-tags (buffer-file-name)))))
(defalias 'ta 'tags-apropos)
(defalias 'ts 'tags-search)
(defalias 'tq 'tags-query-replace)
(defalias 'im 'imenu)

(require 'icicles nil t)
(global-set-key [(f6)] 'icicle-complete-keys)
(defun bartuer-icicle-key-map()
  (when icicle-mode
    (let ((map minibuffer-local-completion-map))
      (define-key map [(f1)] 'icicle-completion-help) 
      (define-key map "\M-o" 'icicle-erase-minibuffer-or-history-element)
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
      (define-key map "\C-n" 'icicle-next-apropos-candidate-action)
      (define-key map "\C-p" 'icicle-previous-apropos-candidate-action)
      (define-key map "\C-\M-n" 'icicle-help-on-next-apropos-candidate)
      (define-key map "\C-\M-p" 'icicle-help-on-previous-apropos-candidate))))
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

(autoload 'file-cache-ido-read "bartuer-filecache.el" "prompt to ido filecache" t nil)
(autoload 'file-cache-ido-find-file "bartuer-filecache.el" "using ido find filecache" t nil)
(autoload 'file-cache-add-this-file "bartuer-filecache.el" "when kill buffer, add to filename cache" t nil)
(autoload 'bartuer-filecache-load "bartuer-filecache.el" "for access file cache" t)
(bartuer-filecache-load)

(require 'anything nil t)
(global-set-key "\C-z" 'anything)

(require 'magit nil t)
(global-set-key "\C-xg" 'magit-status)
(autoload 'bartuer-magit-load "bartuer-magit.el" "add rinari-launch in magit" t)
(add-hook 'magit-mode-hook 'bartuer-magit-load)

(defun git-grep (command-args)
  "Run grep over git documents"
  (interactive
   (progn
     (grep-compute-defaults)
     (list (read-shell-command "grep git docs: "
                               "find ~/local/share/doc/git-doc -type f  |grep -vE \"BROWSE|TAGS|.svn|drw|Binary|.bzr|svn-base|*.pyc\" |xargs grep -niHE " 'grep-find-history))))
   (when command-args              
     (let ((null-device nil))		; see grep
       (grep command-args))))

(require 'cheat nil t)            
(require 'gist nil t)
(require 'pastie nil t)

(require 'yasnippet)
(yas/initialize)
(yas/load-directory "~/etc/el/vendor/yasnippet/snippets")

(require 'rinari nil t)

(require 'flymake nil t)
(require 'rcodetools nil t)
(require 'anything-rcodetools)
(load "~/etc/el/vendor/ruby-mode/ruby-electric.el")
(require 'ruby-eletric-mode nil t)
(require 'ruby-mode nil t)
(push '(".+\\.rb$" flymake-ruby-init)
      flymake-allowed-file-name-masks)
(push '("Rakefile$" flymake-ruby-init)
      flymake-allowed-file-name-masks)
(push '("^\\(.*\\):\\([0-9]+\\): \\(.*\\)$" 1 2 nil 3)
      flymake-err-line-patterns)

(autoload 'bartuer-ruby-load "~/etc/el/bartuer-ruby.el"
  "mode for ruby mode" t nil)
(autoload 'flymake-ruby-init "~/etc/el/bartuer-ruby.el"
  "using ruby -c check syntax" t nil)
(add-hook 'ruby-mode-hook 'bartuer-ruby-load)


(add-to-list 'auto-mode-alist '("\.rb$" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.rjs$" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.builder$" . ruby-mode))
(add-to-list 'auto-mode-alist '("Rakefile" . ruby-mode))

(load  "~/etc/el/vendor/ri/ri-ruby.el")
(require 'ri nil t)
                                        ; need check fastri-server and
                                        ; start it?

(autoload 'css-mode "css-mode-simple.el"
  "mode for css file" t nil)
(require 'css-mode nil t)
(add-to-list 'auto-mode-alist '("\.css$" . css-mode))

(autoload 'yaml-mode "~/etc/el/vendor/yaml-mode/trunk/yaml-mode.el"
  "mode for yaml file" t nil)
(require 'yaml-mode nil t)
(add-to-list 'auto-mode-alist '("\.yml$" . yaml-mode))

(autoload 'bartuer-rhtml-load "~/etc/el/bartuer-rhtml.el" "mode for rhtml" nil t)
(require 'rhtml-mode nil t)
(add-hook 'rhtml-mode-hook
     	  (lambda ()
            (rinari-launch)
            (bartuer-rhtml-load)))
(add-to-list 'auto-mode-alist '("\\.rhtml" . rhtml-mode))
(add-to-list 'auto-mode-alist '("\\.erb" . rhtml-mode))

;; (require 'mumamo-fun)
;; (setq mumamo-chunk-coloring 'submode-colored)
;; (add-to-list 'auto-mode-alist '("\\.html'" . eruby-html-mumamo))

(add-to-list 'auto-mode-alist '("\\.log" . auto-revert-mode))
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

(autoload 'bartuer-gdb-load "bartuer-gdb.el" "for gdb" t)
(add-hook 'gud-mode-hook 'bartuer-gdb-load)
(add-to-list 'auto-mode-alist
             '("\\.gdb$" . gdb-script-mode))

(autoload 'bartuer-read-mark "bartuer-mark.el" "for record note" t)
(define-key view-mode-map "\C-j" 'bartuer-read-mark)

(autoload 'js2-mode "js2" nil t)
(add-to-list 'auto-mode-alist '("\\.js$" . js2-mode))

(autoload 'bartuer-js-load "bartuer-js" nil t)
(add-hook 'js2-mode-hook 'bartuer-js-load)

(autoload 'bartuer-txt-load "bartuer-txt.el" "for text mode" t)
(add-hook 'text-mode-hook 'bartuer-txt-load)

(autoload 'bartuer-scheme-load "bartuer-scheme.el" "for scheme mode" t)
(autoload 'start-scheme "xscheme.el" "start scheme interaction buffer" t)
(add-hook 'scheme-mode-hook 'bartuer-scheme-load)
(add-to-list 'auto-mode-alist '("\\.scm$" . scheme-mode))
(defun scheme (buffer-name)
  (interactive
   (list (read-buffer "Scheme interaction buffer: "
		      "*scheme-scratch*"
		      nil)))
  (if (not (fboundp 'bartuer-scheme-load))
      (progn
        (autoload  'bartuer-scheme-load "bartuer-scheme.el" "for scheme mode" t)
        (bartuer-scheme-load)
        (start-scheme buffer-name))
    (start-scheme buffer-name)))

(autoload 'bartuer-elisp-load "bartuer-elisp.el" "for edit elisp" t)
(add-hook 'elisp-mode-hook 'bartuer-elisp-load)

(require 'ess-site nil t)
(autoload 'bartuer-ess-load "bartuer-ess.el" "for statistic language" t)
(add-hook 'ess-mode-hook 'bartuer-ess-load)
(global-set-key "\C-cl" 'org-store-link)
(global-set-key "\C-ca" 'org-agenda)
(global-set-key "\C-cb" 'org-iswitchb)
(global-set-key "\C-cu" 'org-insert-link-global)
(global-set-key "\C-co" 'org-open-at-point-global)

(autoload 'bartuer-org-load "bartuer-org.el" "for org mode" t)
(add-hook 'org-mode-hook 'bartuer-org-load)

(put 'dired-find-alternate-file 'disabled nil)

(put 'upcase-region 'disabled nil)

(put 'downcase-region 'disabled nil)
