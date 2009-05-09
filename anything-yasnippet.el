(require 'anything)
(require 'yasnippet)

(defvar anything-objc-parameter-define-re "\\(:([a-zA-Z_0-9_-\\<\\>,()\\*\\ ]*)[a-zA-Z0-9_-]+\\|\\.\\.\\.\\)"
  "(type)name")

(setq objc-message-length 0)

(defun message-length ()
  objc-message-length)

(defun yasnippet-complete-objc-message (msg)
  "constructure an snippet according to the objc signature string"
  (flymake-mode nil)
  (setq objc-message-length (length msg))
  (setq para-fun '(lambda (para)
                    (setq count (1+ count))
                    (format ":${%d%s}" count para)))
  (setq signature-template ((lambda (signature)
                              (let ((count 0))
                                (replace-regexp-in-string
                                 anything-objc-parameter-define-re
                                 para-fun
                                 signature))
                              ) msg))
  (insert "anything")
  (yas/define 'objc-mode
              "anything"
              signature-template)
  (message (format "objc-complete:%s" msg))
  (yas/expand))
              

(defvar anything-objc-message-re "\\(\\(^[-+]?\\ *([a-zA-Z_0-9<>\\ \\*]*)\\)\\([a-zA-Z0-9_+:()<>,\\ \\.\\*]*\\).*\177\\(.*\\)\001.*$\\)"
  "1:return type 2:signature\177 3:message name\001")


(defun anything-objc-etags-parser (candidate)
  "parse the etags candidate, return (lable . signature)"
  (when (string-match anything-objc-message-re candidate)
    (let* ((lable
            (concat
             (match-string 2 candidate) "\t"
             (match-string 4 candidate)))
           (signature
            (match-string 3 candidate)))
      (cons lable signature)))
  )


(setq anything-yasnippet-completion-table nil)

(setq anything-c-source-complete-etags-objc
      '((name . "Etags Method Completion")
        (candidates 
         .
         (lambda () anything-yasnippet-completion-table)) ;to using completion show , must using a function
        (init
         . 
         (lambda ()
           (condition-case x
               (setq anything-yasnippet-completion-table (mapcar 'anything-objc-etags-parser
                                                             (split-string (shell-command-to-string "cat ~/Documents/TAGS|grep ^[+-].*") "\n")))
             (error (setq anything-yasnippet-completion-table nil))
             )
           )
         )
        (action
         ("Completion" . yasnippet-complete-objc-message))
        ))


(defun anything-etags-complete-objc-message ()
  "using anything framework search iphone cocoa etags, select one signature feed to yasnippet "
  (interactive)
  (let ((anything-sources (list anything-c-source-complete-etags-objc)))
    (anything)))


(defun yasnippet-complete-syntax-expand (msg)
  "constructure an snippet according to the syntax signature string"
  (flymake-mode nil)
  (insert msg)
  (yas/expand))

(setq anything-yasnippet-completion-table nil)

(setq snippet-dot-re "\\(^[a-z0-9+-]*\\)\\.\\(.*$\\)")

(defun anything-syntax-parser ()
  "return (lable . expand-short-cut)"
  (setq current-mode-snippet-directory
        (concat "~/etc/el/vendor/yasnippet/snippets/text-mode/"
                (prin1-to-string major-mode)))
  (let* ((syntax-expand-list nil))
    (when (file-directory-p current-mode-snippet-directory)
      (progn 
        (dolist (file (yas/directory-files current-mode-snippet-directory t))
          (when (file-readable-p file)
            (let* ((lable
                    (concat
                     (file-name-nondirectory file) "\t"
                     (with-temp-buffer
                       (insert-file-contents file nil nil nil t)
                       (when 
                           (string-match "\\(name *: *\\)\\(.*\n\\).*"
                                         (buffer-substring-no-properties (point-min) (point-max)))
                         (match-string 2)))))
                   (stub
                    (let ((filename (file-name-nondirectory file)))
                      (if (string-match snippet-dot-re filename)
                          (match-string 1 filename)
                        (substring filename 0)))
                    ))
              (push (cons lable stub)
                    syntax-expand-list))))))
    (mapcar (lambda (x) x) syntax-expand-list)
    ))

(setq anything-c-source-complete-syntax
      '((name . "Syntax Completion")
        (candidates 
         .
         (lambda () anything-yasnippet-completion-table))
        (init
         . 
         (lambda ()
           (condition-case x
               (setq anything-yasnippet-completion-table (anything-syntax-parser))
             (error (setq anything-yasnippet-completion-table nil))
             )
           )
         )
        (action
         ("Completion" . yasnippet-complete-syntax-expand))
        ))

(defun anything-complete-syntax-expand ()
  "finish using current mode's syntax snippet "
  (interactive)
  (let ((anything-sources (list anything-c-source-complete-syntax)))
    (anything)))

(provide 'anything-yasnippet)
