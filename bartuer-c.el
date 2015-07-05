(defun bartuer-c-indent ()
  (interactive)
  (if (not (window-minibuffer-p))
      (cond ((indent-for-tab-command))
            (t (indent-relative-maybe))
            (t (indent-for-comment)))))

(defun c-load-etags (reset)
  (interactive "P")
  (setq anything-etags-enable-tag-file-dir-cache t)
  (if reset
      (setq anything-etags-cache-tag-file-dir nil))
  (unless anything-etags-cache-tag-file-dir
    (setq anything-etags-cache-tag-file-dir
          (concat (file-name-directory (buffer-file-name))
                  (ido-completing-read
                   "TAGS location:"
                   (list "."
                         "../src/"
                         "../../src"
                         "../../src"
                         "../../../src"
                         ".."
                         "../.."
                         "../../.."
                         ))) )
    )
  (anything-etags-select)
  )

(defun bartuer-c-common ()
  "for c and C++ language
"
  (require 'make-mode)
  ;; (c-subword-mode 1)
  ;; is it possible to guess the code style ?
  ;; now I using the c-file-style in file varible
  (define-key c-mode-base-map "\C-i" 'bartuer-c-indent)
  (define-key c-mode-base-map "\M-j" 'dabbrev-expand)
  (define-key c-mode-base-map "\C-m" 'c-context-line-break)
  (define-key makefile-mode-map "\C-j" 'recompile)
  (define-key c-mode-base-map "\C-c\C-c" 'anything-etags-select)
  (define-key c-mode-base-map "\M-j" 'dabbrev-expand)
  (define-key c-mode-base-map "\C-j" 'recompile)
  (define-key c-mode-base-map "\C-c\C-c" 'c-load-etags)

  (hs-minor-mode t)
  (add-to-list 'ac-sources 'ac-source-gtags)
  (add-to-list 'ac-sources 'ac-source-semantic)
  )

(defun that-line-end (n)
  "track region end"
  (save-excursion
    (goto-char 0)
    (forward-line n)
    (end-of-line)
    (point)
    )
  )

(defun c-var-table ()
  "try to align variant table"
  (interactive)
  (let  ((s (region-beginning))
         (l (line-number-at-pos (region-end))))
    (replace-regexp "[ 	]+" " " nil  s (region-end))
    (org-table-convert-region s (that-line-end l))
    (replace-regexp "^|" "" nil s (that-line-end l))
    (replace-regexp "|$" "" nil s (that-line-end l))
    (replace-regexp " | " "    " nil s (that-line-end l))
    )
  )

(defun bartuer-c-load ()
  "mode hooks for c/cc"
  (interactive)
  (define-key c-mode-base-map (kbd "RET") 'newline-and-indent)
  (define-key c-mode-base-map "\C-\M-i" 'ac-complete-clang)
  )