(setq custom-file "~/etc/el/bartuer-custom.el")
(load custom-file)

(when (>= emacs-major-version 24)
  (require 'package)
  (package-initialize)
  (add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/"))
  (add-to-list 'package-archives '("marmalade" . "https://marmalade-repo.org/packages"))
  )

(require 'phi-search)
(require 'multiple-cursors)
(global-set-key "\C-xx" 'mc/mark-all-dwim)
(global-set-key "\C-xj" 'mc/mark-all-in-region-regexp)
(global-set-key "\C-xy" 'mc/insert-numbers)
(global-set-key "\C-xp" 'mc/edit-lines)

(require 'key-chord)
(require 'space-chord)
(key-chord-mode 1)
(key-chord-define-global "jf" 'er/expand-region)
(key-chord-define-global "hg" 'er/contract-region)
(space-chord-define-global "j" 'ace-jump-mode)
(require 'expand-region)

(require 'ace-jump-mode)
(global-set-key "\C-c " 'ace-jump-mode)

(defun cygw2u (path)
  (mapconcat (lambda (x) x) (split-string (car (cdr (split-string path "C:\\\\cygwin64")) )  "\\\\") "/" )
  )

(defun cygu2w (path)
  (concat "C:\\cygwin64" (subst-char-in-string ?/ ?\\ path)) 
  )

(defun ammend-file-exists-p (file-name)
  (let ((path-util (executable-find "cygpath")))
    (if path-util
        (file-exists-p (cygw2u file-name)) 
      (file-exists-p file-name)
        ))
  )

(defun ammend-buffer-file-name (&optional name)
  (let* ((path-util (executable-find "cygpath"))
         (file-name (if (not name)
                   (buffer-file-name)
                 name)))
    (if path-util
        (cygu2w file-name)
      file-name
      )
    )
  )

(defun what-face (pos)
    (interactive "d")
      (let ((face (or (get-char-property (point) 'read-face-name)
                                        (get-char-property (point) 'face))))
            (if face (message "Face: %s" face) (message "No face at %d" pos))))

(if(fboundp 'menu-bar-mode) (menu-bar-mode -1))
(if(fboundp 'tool-bar-mode) (tool-bar-mode -1))
(if(fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(fset 'yes-or-no-p 'y-or-n-p)
(put 'set-goal-column 'disabled nil)
(setq-default source-directory (expand-file-name "~/local/src/emacs/"))
(setq-default major-mode 'text-mode)
(defalias 'n 'rename-buffer)

(defun link (file point)
  (interactive)
  (find-file-other-window file)
  (goto-char point))

(defalias ': (lambda () (interactive) (align-regexp (region-beginning) (region-end) "\\(\\s-*\\):")))
(defalias 'll (lambda ()
                (interactive)
                (kill-new (format "(link \"%s\" %d)"
                                  (replace-regexp-in-string
                                   (shell-command-to-string "printf $HOME")  "~"  (buffer-file-name))
                                  (point)))))
(defalias 'r (lambda ()
               (interactive)
               (revert-buffer t t)))
(defalias 'p 'finder-commentary)
(defalias 'c 'emacs-lisp-byte-compile)
;; (add-to-list 'load-path (expand-file-name "~/etc/el/icicles"))
(add-to-list 'load-path (expand-file-name "~/etc/el"))

(defalias 'g 'global-set-key)
(defalias 'l 'local-set-key)
(global-set-key "\C-w" 'backward-kill-word) ;for case <BS> does not mean <DEL>,anywhere
(global-set-key "\C-c\C-k" 'kill-region) ;for case <BS> does not mean <DEL>,anywhere
(global-set-key "\C-ck" 'kill-region) ;delete to the beginning "\C-x-DEL",move 1
(global-set-key "\C-xk" 'kill-whole-line) ;delete whole line, move 1

(require 'guess-style)
(autoload 'guess-style-set-variable "guess-style" nil t)
(autoload 'guess-style-guess-variable "guess-style")
(autoload 'guess-style-guess-all "guess-style" nil t)
(global-guess-style-info-mode 1)
(defun ttt()
  (interactive)
  (whitespace-mode)
  (guess-style-guess-all)
  )


(global-set-key "\r" 'newline-and-indent) ;depend on if this line is a comment
(global-set-key "\C-i" '(lambda ()
                          (interactive)
                          (if (not (window-minibuffer-p))
                              (cond ((indent-for-tab-command))
                                    (t (indent-relative-maybe))
                                    (t (indent-for-comment))))))

(require 'smart-tabs-mode)

(global-set-key "\C-z" (lambda ()
                         (interactive)
                         (recenter-top-bottom 0)))
                         
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
    (if (eq major-mode 'shell-mode)
        (scroll-other-window 10)
      (next-error))))

(global-set-key "\C-\M-n" 'ctrl-meta-n-dwim)

(defun ctrl-meta-p-dwim()
  "multiple bindings for C-M-p"
  (interactive)
  (if (windowp (car (window-tree)))
      (backward-list)
    (if (eq major-mode 'shell-mode)
        (scroll-other-window -10)
      (previous-error))))

(global-set-key "\C-\M-p" 'ctrl-meta-p-dwim)

(defalias 'f 'auto-fill-mode)

(global-set-key "\C-j" 'eval-last-sexp)
(defalias 'e 'eval-current-buffer)


(require 'powershell)
(require 'powershell-mode)
(add-to-list 'auto-mode-alist '("\.ps1$" . powershell-mode))

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
(global-set-key "\M-5" 'everything-find-file)
(global-set-key "\M-6" 'nav-toggle)

(defun call-stack-parse ()
  (interactive)
  (setq next-error-function 'compilation-next-error-function)
  (set (make-local-variable 'compilation-locs)
       (make-hash-table :test 'equal :weakness 'value))
  (compilation--ensure-parse (point))
  (setq compilation-current-error (point))
)
(defalias 'cs 'call-stack-parse)

(defun do-ql-dwim()
  (interactive)
  (let* ((proc (get-buffer-process "*Async Shell Command*")))
    (if proc
        (kill-process proc)
      (dired-do-async-shell-command
       "qlmanage -p 2>/dev/null" ""
       (dired-get-marked-files))
      ))
  )

(require 'bartuer-dired nil t)

(add-hook 'dired-load-hook (lambda ()
                             (load "dired-x")
                             ))

(add-hook 'dired-mode-hook (lambda ()
                             (define-key dired-mode-map " " 'do-ql-dwim)
                             (define-key dired-mode-map "w" 'dired-copy-filename-as-kill-fix)
                             ))

(require 'nav)

(nav-disable-overeager-window-splitting)

(defun color-print ()
  (interactive)
  (require 'htmlize nil t)
  (require 'color-theme nil t)
  (load "~/etc/el/auto-install/bartuer-theme.el")
  (color-theme-select)
  )

(global-set-key "\M-8" 'find-file)
(defalias 'ff 'find-file-at-point)

(defun clean-thing-at-point ()
  (let ((bounds (bounds-of-thing-at-point 'word)))
      (if bounds
          (buffer-substring-no-properties (car bounds) (cdr bounds)))))

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

(defun restore-frames ()
  "resort saved frame configuration at 'f'"
  (interactive)
  (let ((val (cdr (assq 102 register-alist))))
    (when (and (consp val) (frame-configuration-p (car val)))
      (set-frame-configuration (car val) t)
      (if (functionp 'gud-refresh)
          (progn
            (gud-refresh)
            (goto-char (point-max)))))))
(defalias 'rf 'restore-frames)

(defun meta-space-dwim()
  "multiple bindings for M-SPC"
  (interactive)
  (if (windowp (car (window-tree)))
      (unless (restore-frames)
        (winner-undo))
    (delete-other-windows)))
(global-set-key "\M- " 'meta-space-dwim)


(global-set-key "\M-k" 'other-window)
(defvar calc-mode-hook nil
  "Hook run when entering calc-mode.")
(add-hook 'calc-mode-hook (lambda ()
                            (interactive)
                            (define-key calc-mode-map "\M-k" 'other-window)
                            ))

(if (require 'diff-mode nil t)
    (add-hook 'diff-mode-hook
              (lambda ()
                (define-key diff-mode-map "\M-k" 'other-window)
                (define-key diff-mode-map "\M-h" 'diff-hunk-kill))))
(global-set-key "\M-o" 'kill-sentence)

(require 'binary-diff)

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

(global-set-key "\M-7" 'find-dired)
(global-set-key "\M-9" 'grep-find)
(global-set-key [(f9)] 'grep-find)
(defun match-lines (&optional arg)
  (interactive "P")
  (if (eq arg nil)
      (progn
        (let ((regexp (occur-read-primary-args))
              )
          (list-matching-lines (car regexp))
          )
        )
    (let ((bufregexp
           (let* ((default (car regexp-history))
                  (input
                   (read-from-minibuffer
                    (if current-prefix-arg
                        "List lines in buffers whose names match regexp: "
                      "List lines in buffers whose filenames match regexp: ")
                    nil
                    nil
                    nil
                    'regexp-history)))
             (if (equal input "")
                 default
               input))
           )
          (regexp (occur-read-primary-args)))
      (multi-occur-in-matching-buffers bufregexp (car regexp)))
    ))
(global-set-key "\M-0" 'match-lines)
(global-set-key "\C-\M-s" 'isearch-forward)
(global-set-key "\C-\M-r" 'isearch-backward)
(global-set-key "\C-s" 'isearch-forward-regexp)
(global-set-key "\C-r" 'isearch-backward-regexp)

(global-set-key [(f7)] 'man-follow)
(global-set-key [(f8)] 'info-lookup-symbol)
(defalias 'm 'flymake-mode)
(defalias 'a 'apropos)                  ;C-u C-h a for command and function


(require 'google-define nil t)
(defalias 'gd 'google-define)
(defalias 'x 'buddy-define)
(require 'fast-wiki nil t)
(require 'bartuer-buddy nil t)
(defalias 'bd 'buddy-minor-mode)

(if (fboundp 'server-start)
    (server-start))
(if (fboundp 'show-paren-mode)
    (show-paren-mode 1))
(if (fboundp 'winner-mode)
    (winner-mode 1))
(if (fboundp 'which-function-mode)
    (which-function-mode 1))

(require 'remember nil t)
(require 'org-remember nil t)
(org-remember-insinuate)
(setq org-directory "~/org")
(setq org-default-notes-file (concat org-directory "/note.org"))
(define-key global-map "\C-cr" 'org-remember)
(define-key global-map "\C-cc" 'org-capture)
(autoload 'bartuer-setup-capture "bartuer-org.el" "capture define" t)
(bartuer-setup-capture)
(add-hook 'remember-mode-hook (lambda ()
                                (setq remember-annotation-functions nil)))


(require 'bartuer-sql nil t)

(require 'csv-mode nil t)
(add-to-list 'auto-mode-alist '("\.csv$" . csv-mode))
(add-hook 'csv-mode-hook 'bartuer-csv-load)

(require 'sqlite-mode nil t)
(add-to-list 'auto-mode-alist '("\.db$" . sqlite-mode))
(add-to-list 'auto-mode-alist '("\.sqlite$" . sqlite-mode))
(add-hook 'sqlite-mode-hook 'bartuer-sqlite-load)

(defun postfix ()
  (interactive)
  (find-file "~/local/share/doc/postfix")
  (occur "*[12]"))


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
(global-set-key "\C-c\C-\M-n" 'flyspell-goto-next-error)

;; M-TAB do the tags and symbol complete
(defalias 'tl (quote (lambda ()
                       (interactive)
                       (list-tags (buffer-file-name)))))
(defalias 'ta 'tags-apropos)
(defalias 'ts 'tags-search)
(defalias 'tq 'tags-query-replace)
(defalias 'im 'imenu)
(global-set-key "\M-." 'anything-etags-select-from-here)
(load "~/etc/el/bartuer-etags.el")

(require 'helm-config)

(load "~/etc/el/anything-c-source-mark-ring.el")
(defun anything-imenu-jump (p)
  "(number-or-marker-p p), need move window first"
  (if (> p 100)
      (set-window-start (selected-window) (- p 100))
    (set-window-start (selected-window) 1))
  (goto-char p)
  )

(defun anything-c-imenu-kiss-action (elm)
  "The kiss action for `anything-c-source-imenu'."
  (push-mark)
  (let ((path (split-string elm anything-c-imenu-delimiter))
        (alist anything-c-cached-imenu-alist))
    (if (> (length path) 1)
        (progn
          (setq alist (last (mapcar (lambda (elem)
                                      (setq alist
                                            (assoc elem alist)))
                                    path)))
          (anything-imenu-jump (cdr
                                (assoc (car (last path)) alist)))
          )
      (let ((position (cdr
                       (assoc elm alist))))
        (anything-imenu-jump position)
        ))))

(setq anything-sources
      '(
        ((name . "Imenu Jump")
         (candidates . anything-c-imenu-candidates)
         (action . anything-c-imenu-kiss-action)
         )

        anything-c-source-complete-syntax

        ;; seems kill ring is not useful than mark ring for programming, right?
        anything-c-source-mark-ring
        anything-c-source-global-mark-ring
        
        ((name . "Kill Ring")
         (init . (lambda () (anything-attrset 'last-command last-command)))
         (candidates . (lambda ()
                         (loop for kill in kill-ring
                               unless (or (< (length kill) anything-kill-ring-threshold)
                                          (string-match "^[\\s\\t]+$" kill))
                               collect kill)))
         (action . anything-c-kill-ring-action)
         (last-command)
         (migemo)
         (multiline)
         )
        ))

(require 'anything-yasnippet)
(require 'anything-etags)
;; (require 'icicles nil t)
;; (global-set-key [(f6)] 'icicle-complete-keys)
(global-set-key "\M-'" 'advertised-undo)
;; (defun bartuer-icicle-key-map()
;;   (when icicle-mode
;;     (let ((map minibuffer-local-completion-map))
;;       (define-key map [(f1)] 'icicle-completion-help) 
;;       (define-key map "\M-." 'anything-etags-select-from-here)
;;       (define-key map "\M-'" 'advertised-undo)
;;       (define-key map "\M-o" 'icicle-erase-minibuffer-or-history-element)
;;       (define-key map "\M-v" 'icicle-switch-to-Completions-buf)
;;       (define-key map "\C-w" 'backward-kill-word)
;;       (define-key map "\C-\M-y" 'icicle-apropos-complete-and-narrow)
;;       (define-key map "\C-\M-i" 'icicle-apropos-complete)
;;       (define-key map "\C-i" 'minibuffer-complete)
;;       (define-key map " " 'minibuffer-complete-word)
;;       (define-key map "\C-j" 'exit-minibuffer)
;;       (define-key map "\C-s" 'icicle-narrow-candidates)
;;       (define-key map "\M-l" 'switch-to-buffer)
;;       (define-key map "\M-k" 'other-window)
;;       (define-key map "\C-n" 'icicle-next-apropos-candidate-action)
;;       (define-key map "\C-p" 'icicle-previous-apropos-candidate-action)
;;       (define-key map "\C-\M-n" 'icicle-help-on-next-apropos-candidate)
;;       (define-key map "\C-\M-p" 'icicle-help-on-previous-apropos-candidate))))
;; (add-hook 'icicle-mode-hook 'bartuer-icicle-key-map)
;; (when(fboundp 'icy-mode) 
;;   (defalias 'i 'icy-mode)
;;   (icy-mode))

(defadvice execute-extended-command (before icicle-m-x-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn nil))

(defadvice icicle-execute-extended-command-1 (before icicle-m-x-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn nil))

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

;; (require 'xml-augment nil t)
;; (add-hook 'sgml-mode-hook 'xml-augment-hook)

(require 'bartuer-filecache nil t)
(bartuer-filecache-load)

(require 'anything nil t)
(setq anything-candidate-number-limit nil)
(require 'anything-match-plugin nil t)
(require 'anything-complete nil t)
(require 'anything-show-completion)

(when (require 'anything-show-completion nil t)
  (progn
    (use-anything-show-completion 'anything-etags-complete-objc-message
                                  '(message-length))
    ))

(require 'json nil t)
(when (require 'anything-show-completion nil t)
  (progn
    (use-anything-show-completion 'anything-complete-js
                                  '(js-message-length))
    ))

(when (require 'anything-show-completion nil t)
  (progn
    (use-anything-show-completion 'rct-complete-symbol--anything
                                  '(length pattern))
    ))


(when (fboundp 'anything)
  (global-set-key "\C-l" 'anything))

(require 'magit nil t)
(global-set-key "\C-xg" 'magit-status)
(autoload 'bartuer-magit-load "bartuer-magit.el" "add rinari-launch in magit" t)
(add-hook 'magit-mode-hook 'bartuer-magit-load)

(require 'bartuer-sd)
(defun accumulate-rectangle (start end &optional fill)
  "add numbers up in rectangle"
  (interactive "r*\nP")
  (setq killed-rectangle (extract-rectangle start end))
  (message
   (let*
       ((formulas '("vsum" "vmin" "vmax" "vmean" "vgmean" "vcount" "vsdev" "vmeane"))
        (args (mapconcat
               (lambda (n)
                 (format "%d" n)
                 )
               (mapcar
                (lambda (str)
                  (read (substring-no-properties str)))
                killed-rectangle) ",")))
     (mapconcat
      (lambda (formula)
        (format "%6s:%s"
                formula
                (calc-eval (format "%s(%s)" formula args)))          
        ) formulas "\n")
     
     ))
  )

(global-set-key "\C-xrp" 'accumulate-rectangle)

(defun git-link (repos commit &optional graph)
  "insert link can jump to diff"
  (interactive)
  (if graph
      (shell-command (concat "cd " repos ";git difftool " commit "~" " " commit))
    (shell-command (concat "cd " repos ";git diff " commit "~" " " commit) "*git link output*"))
  (pop-to-buffer "*git link output*")
  (diff-mode)
  (diff-refine-hunk))

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

(defun html-2-txt ()
  "invoke html2text to see the downloaded html"
  (interactive)
  (shell-command-on-region (point-min) (point-max) "html2text -nobs -style pretty"
                           (get-buffer-create "html-text"))
  (with-current-buffer "html-text"
    (replace-regexp "" "'" nil (point-min) (point-max))
    (replace-regexp "" "\"" nil (point-min) (point-max))
    (replace-regexp "" "\"" nil (point-min) (point-max))
    (replace-regexp "
\\([A-Z]\\)" "

\\&" nil (point-min) (point-max))
    )
  )

(defun html-2-md ()
  "invoke html2text.py to see document in markdown"
  (shell-command-on-region (point-min) (point-max) "html2text.py"
                           (get-buffer-create "html-markdown"))
  (with-current-buffer "html-markdown"
                       (markdown-mode)
                       (setq buffer-file-name "/tmp/preview-url.md")
                       (save-buffer)
                       (flymake-mode t)
                       )
  )

(defalias 'u (lambda (url-content-insert-location)
               (interactive "surl: ")

               (shell-command  (concat "curl -n --ntlm -k " url-content-insert-location " 2>/dev/null")
                               (get-buffer-create "preview-url") (get-buffer "*Shell Command Output*"))
               (with-current-buffer "preview-url"
                 (goto-char (point-min))
                 (if (search-forward "html" (point-max) t)
                     (html-2-txt)
                     )
                 (if (search-forward "html" (point-max) t)
                     (html-2-md)
                     )
               )
               (pop-to-buffer "preview-url" t)
               (pop-to-buffer "html-text" t)
               (pop-to-buffer "html-markdown" t)
               ))

(defun macman (name)
  (u (concat "http://developer.apple.com/mac/library/documentation/Darwin/Reference/ManPages/10.5/man3/" name ".3.html?useVersion=10.5")))

(require 'cheat nil t)            
(require 'gist nil t)
(require 'pastie nil t)


(require 'yasnippet)
(yas--initialize)
(yas-load-directory "~/etc/el/vendor/yasnippet/snippets")
(global-set-key "\C-cy" (lambda ()
                               (interactive)
                               (message "load yas")
                               (yas-load-directory "~/etc/el/vendor/yasnippet/snippets")))
(add-hook 'yas-after-exit-snippet-hook (lambda ()
                                            (flymake-mode t)))

(defalias 'y (lambda () (yas-reload-all)))

(require 'rinari nil t)
(add-hook 'rinari-minor-mode-hook (lambda ()
                                    (define-key rinari-minor-mode-map "\M-r" 'rinari-ido)))

(defadvice rinari-cap (before icicle-cap-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn (lambda  (entry)
                                   "return the cap documents of entry"
                                   (let ((item (widget-princ-to-string entry)))
                                     (with-output-to-temp-buffer (format "cap -e %s" item)
                                       (princ (shell-command-to-string (concat "cap -e " item))))))))

(defadvice rinari-script (before icicle-script-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn
        (lambda  (entry)
          "return the script documents of entry"
          (let ((item (widget-princ-to-string entry)))
            (with-output-to-temp-buffer (format "%s help" item)
              (princ (shell-command-to-string
                      (concat
                       (rinari-root) "script/"
                       item
                       ((lambda ()
                          (unless (or
                                   (string-equal "performance/profiler" item)
                                   (string-equal "performance/benchmarker" item)
                                   (string-match "generate \w" item)
                                   )
                            " -h")))
                       ((lambda ()
                          (when (string-equal "browserreload" item)
                            (concat ";" (rinari-root) "script/browserreload help run")
                            )))))))
            (with-current-buffer (format "%s help" item)
              (toggle-read-only -1)
              (ansi-color-apply-on-region (point-min) (point-max))
              (copy-to-buffer "*current script help*" (point-min) (point-max)))))))


(defadvice rinari-rake (before icicle-rake-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn (lambda  (entry)
                                   "return the cap documents of entry"
                                   (let ((item (widget-princ-to-string entry)))
                                     (with-output-to-temp-buffer (format "rake help %s" item)
                                       (princ (shell-command-to-string (concat "rake -D " item))))))))

(require 'bartuer-gem nil t)            ;for gem and mongrel

(require 'apache-mode nil t)
(add-to-list 'auto-mode-alist '("httpd.conf" . apache-mode))

(require 'conf-mode nil t)
(add-to-list 'auto-mode-alist '("nginx.conf" . conf-nginx-mode))

(require 'bartuer-ruby nil t)

(require 'flymake nil t)
(require 'rcodetools nil t)
(require 'anything-rcodetools nil t)
(load "~/etc/el/vendor/ruby-mode/ruby-electric.el")
(require 'ruby-eletric-mode nil t)
(require 'ruby-mode nil t)

(autoload 'bartuer-ruby-load "~/etc/el/bartuer-ruby.el"
  "mode for ruby mode" t nil)
(add-hook 'ruby-mode-hook 'bartuer-ruby-load)

(add-to-list 'auto-mode-alist '("\.rb$" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.ru$" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.rjs$" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.builder$" . ruby-mode))
(add-to-list 'auto-mode-alist '("Rakefile" . ruby-mode))
(add-to-list 'auto-mode-alist '("\.rake$" . ruby-mode))

(load  "~/etc/el/vendor/ri/ri-ruby.el")
(require 'ri nil t)
                                        ; need check fastri-server and
                                        ; start it?

(defadvice ri-ruby-read-keyw (before icicle-ri-help activate)
  "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn 'bartuer-ruby-ri))
(defadvice inf-ruby-completions (before icicle-ri-help activate)
    "do right thing for icicle-candidate-help-fn ."
  (setq icicle-candidate-help-fn 'bartuer-ruby-ri)) 

;;; for java emacs-eclim 
(require 'eclim)
(require 'eclimd)
(setq eclim-auto-save t)
(global-eclim-mode)

(setq help-at-pt-display-when-idle t)
(setq help-at-pt-timer-delay 0.1)
(help-at-pt-set-timer)

(require 'auto-complete)
(add-to-list 'ac-dictionary-directories "~/etc/el/vendor/auto-complete/dict")
(require 'auto-complete-config)
(ac-config-default)

(require 'company)
(autoload 'company-mode "company" nil t)
(eval-after-load 'company
  '(add-to-list 'company-backends 'company-omnisharp))


(require 'company-emacs-eclim)
(company-emacs-eclim-setup)
(global-company-mode t)

(require 'ac-emacs-eclim-source)
(ac-emacs-eclim-config)

(defun enable-ac-ispell ()
      (add-to-list 'ac-sources 'ac-source-ispell))


(require 'ac-ispell)
(eval-after-load "auto-complete"
  '(progn (ac-ispell-setup))
 )

(semantic-mode 1)
(global-ede-mode 1)

(require 'bartuer-erlang nil t)
(autoload 'bartuer-erlang-load "~/etc/el/bartuer-erlang.el"
  "mode for erlang mode" t nil)
(add-hook 'erlang-mode-hook 'bartuer-erlang-load)
(add-to-list 'auto-mode-alist '("\.erl$" . erlang-mode))

(require 'bartuer-lua nil t)
(autoload 'bartuer-lua-load "~/etc/el/bartuer-lua.el"
  "mode for lua mode" t nil)
(add-hook 'lua-mode-hook 'bartuer-lua-load)
(add-to-list 'auto-mode-alist '("\.lua$" . lua-mode))

(require 'bartuer-python nil t)
(autoload 'bartuer-python-load "~/etc/el/bartuer-python.el"
  "mode for python mode" t nil)
(add-hook 'python-mode-hook 'bartuer-python-load)
(add-to-list 'auto-mode-alist '("\.py$" . python-mode))


(require 'slime)

(require 'ac-slime)
(add-hook 'slime-mode-hook 'set-up-slime-ac)
(add-hook 'slime-repl-mode-hook 'set-up-slime-ac)
(eval-after-load "auto-complete"
       '(add-to-list 'ac-modes 'slime-repl-mode))

(setq inferior-lisp-program "/usr/local/bin/sbcl")
(autoload 'bartuer-commonlisp-load "~/etc/el/bartuer-commonlisp.el"
  "mode for commonlisp mode" t nil)
(add-hook 'commonlisp-mode-hook 'bartuer-commonlisp-load)
(slime-setup '(slime-js slime-repl))

(require 'redis nil t)
(require 'css-mode nil t)
(autoload 'bartuer-css-load "~/etc/el/bartuer-css.el" t)
(add-hook 'css-mode-hook 'bartuer-css-load)
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
(add-to-list 'auto-mode-alist '("\\.erubis" . rhtml-mode))

;; (require 'mumamo-fun)
;; (setq mumamo-chunk-coloring 'submode-colored)
;; (add-to-list 'auto-mode-alist '("\\.html'" . eruby-html-mumamo))

(require 'rst-mode nil t)
(autoload 'bartuer-rst-load "~/etc/el/bartuer-rst.el" "restructured text mode modification")
(add-hook 'rst-mode-hook 'bartuer-rst-load)

(defadvice auto-revert-handler (before ansi-color activate)
  "also show ansi color in log ."
)

(add-to-list 'auto-mode-alist '("\\log$" . auto-revert-tail-mode))
(add-to-list 'auto-mode-alist '("cheat-sheet" . follow-mode))
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

;; open proper mode according to the implement file types for head file
(defun bartuer-choose-header-mode ()
  (interactive)
  (if (and (buffer-file-name)
           (string-equal (substring (buffer-file-name) -2) ".h"))
      (progn
        (let ((dot-m-file (list
                           (concat (substring (buffer-file-name) 0 -1) "m")
                           (concat (substring (buffer-file-name) 0 -1) "mm")))
              (dot-cpp-file (concat (substring (buffer-file-name) 0 -1) "cpp"))
              (dot-cc-file (concat (substring (buffer-file-name) 0 -1) "cc")))
              (if (mapcan (lambda (f)
                            (file-exists-p f)) dot-m-file)
                  (progn
                    (objc-mode)
                    )
                    (if (or (file-exists-p dot-cpp-file)
                            (file-exists-p dot-cc-file))
                        (c++-mode))))
        (if (search-forward-regexp "^#import " (point-max) t 1)
            (objc-mode)))))
(add-hook 'find-file-hook 'bartuer-choose-header-mode)

(defun bartuer-toggle-target ()
  (cond ((or (string-equal (substring (buffer-file-name) -2) ".c")
             (string-equal (substring (buffer-file-name) -2) ".m")
             )
         (concat (substring (buffer-file-name) 0 -1) "h"))
        ((string-equal (substring (buffer-file-name) -4) ".cpp")
         (concat (substring (buffer-file-name) 0 -3) "h"))
        ((or
          (string-equal (substring (buffer-file-name) -3) ".cc")
          (string-equal (substring (buffer-file-name) -3) ".mm"))
         (concat (substring (buffer-file-name) 0 -2) "h"))
        ((and (string-equal (substring (buffer-file-name) -2) ".h")
             (equal major-mode 'objc-mode))
         (list
          (concat (substring (buffer-file-name) 0 -1) "m")
          (concat (substring (buffer-file-name) 0 -1) "mm")))
        ((and (string-equal (substring (buffer-file-name) -2) ".h")
             (equal major-mode 'c-mode))
         (concat (substring (buffer-file-name) 0 -1) "c"))
        ((and (string-equal (substring (buffer-file-name) -2) ".h")
             (equal major-mode 'c++-mode))
         (list (concat (substring (buffer-file-name) 0 -1) "cpp")
               (concat (substring (buffer-file-name) 0 -1) "cc")
               ))))

(defun bartuer-toggle-header ()
  (interactive)
  (let ((target (bartuer-toggle-target)))
  (if (stringp target)
      (if (file-exists-p target)
        (find-file target))
    (if (listp target)
        (mapcar (lambda (filename)
                  (if (file-exists-p filename)
                      (find-file filename))
                  ) target)))))

(global-set-key "\C-cj" 'bartuer-toggle-header)
(global-set-key "\C-c\C-j" 'bartuer-toggle-header)

(load "~/etc/el/bartuer-objc.el")
(add-hook 'objc-mode-hook 'bartuer-objc-load)
(add-to-list 'auto-mode-alist '("\\mm$" . objc-mode))
(add-to-list 'auto-mode-alist '("\\.j$" . objc-mode))

(require 'fsharp-mode)
(load "~/etc/el/bartuer-fsharp.el")
(add-hook 'fsharp-mode-hook 'bartuer-fsharp-load)
(add-to-list 'auto-mode-alist '("\\fs$" . fsharp-mode))

(defun mac-control ()
  "insert key symbol for shift"
  (interactive)
  (insert "⌃ "))
(global-set-key "\C-c1" 'mac-control)

(defun mac-shift ()
  "insert key symbol for shift"
  (interactive)
  (insert "⇧ "))
(global-set-key "\C-c2" 'mac-shift)

(defun mac-command ()
  "insert key symbol for command"
  (interactive)
  (insert "⌘ "))
(global-set-key "\C-c3" 'mac-command)

(defun mac-option ()
  "insert key symbol for option"
  (interactive)
  (insert "⌥ "))
(global-set-key "\C-c4" 'mac-option)

(defun mac-delete ()
  "insert key symbol for delete"
  (interactive)
  (insert "⌦ "))
(global-set-key "\C-c5" 'mac-delete)

(defun mac-backspace ()
  "insert key symbol for backspace"
  (interactive)
  (insert "⌫ "))
(global-set-key "\C-c6" 'mac-backspace)

(defun mac-up ()
  "insert key symbol for arrow up"
  (interactive)
  (insert "↑"))
(global-set-key "\C-c7" 'mac-up)

(defun mac-down ()
  "insert key symbol for arrow down"
  (interactive)
  (insert "↓"))
(global-set-key "\C-c8" 'mac-down)

(defun mac-left ()
  "insert key symbol for arrow left"
  (interactive)
  (insert "← "))
(global-set-key "\C-c9" 'mac-left)

(defun mac-right ()
  "insert key symbol for arrow right"
  (interactive)
  (insert "→ "))
(global-set-key "\C-c0" 'mac-right)


(require 'paredit nil t)
(autoload 'bartuer-elisp-load "bartuer-elisp.el" "for emacs lisp" t)
(add-hook 'emacs-lisp-mode-hook 'bartuer-elisp-load)

(autoload 'bartuer-lua-load "bartuer-lua.el" "for lua language" t)
(add-to-list 'auto-mode-alist
             '("\\.lua$" . lua-mode))

(autoload 'bartuer-c-common "bartuer-c.el" "for c and c++ language" t)
(add-hook 'c-mode-common-hook 'bartuer-c-common)

(autoload 'bartuer-gdb-load "bartuer-gdb.el" "for gdb" t)
(add-hook 'gud-mode-hook 'bartuer-gdb-load)
(add-to-list 'auto-mode-alist
             '("\\.gdb$" . gdb-script-mode))

(autoload 'bartuer-read-mark "bartuer-mark.el" "for record note" t)
(require 'view nil t)
(define-key view-mode-map "j" 'bartuer-read-mark)
(define-key view-mode-map "k" 'google-define)

(require 'video nil t)

(autoload 'js2-mode "js2-mode" nil t)
(add-to-list 'auto-mode-alist '("\\.js$" . js2-mode))
(add-to-list 'auto-mode-alist '("\\.json$" . js2-mode))

(autoload 'bartuer-js-load "bartuer-js.el" nil t)
(add-hook 'js2-mode-hook 'bartuer-js-load)



(add-to-list 'auto-mode-alist '("\\.sql$" . sql-mode))
(autoload 'bartuer-sql-load "bartuer-sql.el" "for sql mode" t)
(add-hook 'sql-mode-hook 'bartuer-sql-load)

(add-to-list 'auto-mode-alist '("\\html$" . nxml-mode))
;; (autoload 'bartuer-sgml-load "bartuer-sgml.el" "for sgml" t)
;; (add-hook 'sgml-mode-hook 'bartuer-sgml-load)

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

(require 'ragel-mode nil t)
(add-to-list 'auto-mode-alist '("\\.rl$" . ragel-mode))
(autoload 'bartuer-ragel-load "bartuer-ragel.el" "for ragel-mode" t)
(add-hook 'ragel-mode-hook 'bartuer-ragel-load)

(require 'tuareg nil t)
(autoload 'bartuer-ocaml-load "bartuer-ocaml.el" "for edit ocaml" t)
(add-to-list 'auto-mode-alist '("\\.ml[iylp]?" . tuareg-mode))
(autoload 'tuareg-mode "tuareg" "Major mode for editing Caml code" t)
(autoload 'camldebug "camldebug" "Run the Caml debugger" t)
(dolist (ext '(".cmo" ".cmx" ".cma" ".cmxa" ".cmi"))
  (add-to-list 'completion-ignored-extensions ext))
(add-hook 'tuareg-mode-hook 'bartuer-ocaml-load)

(autoload 'bartuer-elisp-load "bartuer-elisp.el" "for edit elisp" t)
(add-hook 'elisp-mode-hook 'bartuer-elisp-load)
(add-hook 'lisp-interaction-mode-hook 'turn-on-eldoc-mode)
(add-hook 'ielm-mode-hook 'turn-on-eldoc-mode)


(require 'ess-site nil t)
(autoload 'bartuer-ess-load "bartuer-ess.el" "for statistic language" t)
(autoload 'bartuer-ess-help-load "bartuer-ess.el" "for statistic language" t)
(add-hook 'ess-mode-hook 'bartuer-ess-load)
(add-hook 'ess-help-mode-hook 'bartuer-ess-help-load)
(defalias 'ess 'ess-switch-to-end-of-ESS)

(require 'org-ascii nil t)
(require 'bartuer-mail nil t)
(autoload 'bartuer-org-load "bartuer-org.el" "for org mode" t)
(global-set-key "\C-cl" 'org-store-link)
(global-set-key "\C-ca" 'org-agenda)
(global-set-key "\C-cb" 'org-iswitchb)
(global-set-key "\C-cu" 'org-insert-link-global)
(global-set-key "\C-co" 'org-open-at-point-global)
(add-hook 'org-mode-hook 'bartuer-org-load)

(autoload 'bartuer-calendar-load "bartuer-calendar.el" "for calendar mode" t)
(add-hook 'calendar-mode-hook 'bartuer-calendar-load)

(autoload 'php-mode "php-mode.el" "for php mode" t)
(require 'php-mode)
(add-to-list 'auto-mode-alist '("\\.php" . php-mode))

(require 'omnisharp)
(autoload 'csharp-mode "vendor/csharp-mode/csharp-mode.el" "for csharp" t)
(require 'csharp-mode)
(add-to-list 'auto-mode-alist '("\\.cs$" . csharp-mode))
(autoload 'bartuer-csharp-load "bartuer-csharp.el" t)
(load "~/etc/el/bartuer-csharp.el")
(add-hook 'csharp-mode-hook 'bartuer-csharp-load)

(autoload 'markdown-mode "markdown-mode.el"
     "Major mode for editing Markdown files" t)
(add-to-list 'auto-mode-alist '("\\.text" . markdown-mode))
(add-to-list 'auto-mode-alist '("\\.md" . markdown-mode))
(add-to-list 'auto-mode-alist '("\\.markdown" . markdown-mode))

(autoload 'matlab-mode "matlab" "Enter MATLAB mode." t)
(setq auto-mode-alist (cons '("\\.mt\\'" . matlab-mode) auto-mode-alist))
(autoload 'matlab-shell "matlab" "Interactive MATLAB mode." t)
(autoload 'bartuer-matlab-load "bartuer-matlab.el" "for matlab/octave language" t)
(add-hook 'matlab-mode-hook 'bartuer-matlab-load)

(autoload 'haml-mode "haml" "Enter HAML mode." t)
(setq auto-mode-alist (cons '("\\.haml\\'" . haml-mode) auto-mode-alist))
(autoload 'haml-mode "haml-mode.el" "for haml language" t)

(require 'typescript)
(autoload 'typescript-mode "typescript.el"
  "Major mode for TypeScript files" t)
(setq auto-mode-alist (cons '("\\.ts\\'" . typescript-mode) auto-mode-alist))

(put 'dired-find-alternate-file 'disabled nil)

(put 'upcase-region 'disabled nil)

(put 'downcase-region 'disabled nil)

(ibuffer)
(ibuffer-switch-to-saved-filter-groups "normal")

;;; clipboard kill for mac (need fix screen, see http://www.opensource.apple.com/source/screen/screen-11/patches/)

(defun clipboard-paste ()
  (interactive)
  (when (eq (point-min) (point-max))
      (insert " ")
    )
  (let ((start (if (eq (point) (point-max))
                   (- (point) 1)
                 (point)))
        (end (if (eq (point) (point-max))
                 (point)
                 (+ (point) 1)))
        )
  (shell-command-on-region start end "pbpaste" nil t)
  ))
(global-set-key "\M-v" 'clipboard-paste)

(defun clipboard-copy-function (string &optional push)
  (get-buffer-create "pbcopy")
  (with-current-buffer "pbcopy"
    (insert string)
    (set-buffer-file-coding-system 'utf-8-dos)
     ;; cp /cygdrive/c/WINDOWS/system32/clip.exe /usr/local/bin/pbcopy.exe
     ;; even set coding-system to utf-dos copy multiple line has problem
     ;; IDE can handle it, like VS
    (call-process-region (point-min) (point-max) "pbcopy" t 0)
    )
  )

(defalias 'i (lambda ()
               (interactive)
              (let ((info-lookup-mode major-mode))
                  (call-interactively 'info-lookup-symbol))
))

;;; TODO this implement has bug, must (setq interprogram-cut-function nil)

(setq interprogram-cut-function (intern "clipboard-copy-function"))
(require 'bartuer-page)

;;; disable edit change prompt
(defun ask-user-about-supersession-threat (fn)
  "boldly ignore file changes on disk"
  )

(global-auto-revert-mode 1)

(defun hide-ctrl-M ()
  "Hides the disturbing '^M' showing up in files containing mixed UNIX and DOS line endings."
  (interactive)
  (setq buffer-display-table (make-display-table))
  (aset buffer-display-table ?\^M []))

(defun mapcar-head (fn-head fn-rest list)
  "Like MAPCAR, but applies a different function to the first element."
  (if list
      (cons (funcall fn-head (car list)) (mapcar fn-rest (cdr list)))))

(defun camelize-method (s)
  "Convert under_score string S to camelCase string."
  (mapconcat 'identity (mapcar-head
                        '(lambda (word) (downcase word))
                        '(lambda (word) (capitalize (downcase word)))
                        (split-string s "_")) ""))



(defun camelize-buffer (regexp to-expr &optional delimited start end)
  "Replace some things after point matching REGEXP with the result of TO-EXPR."
  (interactive
   (progn
   (barf-if-buffer-read-only)
   (let* ((from
	   "[a-z0-9]\\(_[a-z0-9]+\\)+")
	  (to (list (read-from-minibuffer
		     (format "Query replace regexp %s with eval: "
			     (query-replace-descr from))
		     nil nil t "(camelize-method \&)" from t))))
     (replace-match-string-symbols to)
     (list from (car to) current-prefix-arg
	   (if (and transient-mark-mode mark-active)
	       (region-beginning))
	   (if (and transient-mark-mode mark-active)
	       (region-end))))))
  (perform-replace regexp (cons 'replace-eval-replacement to-expr)
		   t 'literal delimited nil nil (point-min) (point-max))
)

(defun hacker-news ()
  (interactive)
  (require 'hackernews)
  (hackernews))

(require 'uuid)
(require 'dos)
(require 'everything)
