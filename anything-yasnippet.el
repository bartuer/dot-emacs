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

(defvar anything-js-parameter-define-re "\\([a-zA-Z0-9_-]+\\)"
  "name")

(setq js-message-length 0)

(defun js-message-length ()
  js-message-length)

(defun yasnippet-complete-js (msg)
  "constructure an snippet according to the js signature string"
  (flymake-mode nil)
  (setq js-message-length (length msg))
  (setq para-fun '(lambda (para)
                    (setq count (1+ count))
                    (format "${%d:%s}" count para)))
  (setq signature-template ((lambda (signature)
                              (let ((count 0))
                                (replace-regexp-in-string
                                 anything-js-parameter-define-re
                                 para-fun
                                 signature))
                              ) msg))
  (insert "anythingetagsjs")
  (yas/define 'js2-mode
              "anythingetagsjs"
              signature-template)
  (message (format "js-complete:%s" msg))
  (yas/expand))


(defvar anything-js-message-re "\\(\\(.*\\)\177\\(.*\\)\001.*$\\)"
  "1:occurence\177 2:message\001")

(defun anything-js-etags-parser (candidate)
  "parse the etags candidate, return (lable . signature)"
  (when (string-match anything-js-message-re candidate)
    (let* ((lable
             (match-string 3 candidate))
           (signature
            ;; cut last part of label
            (when (string-match "\\(^.*\\.\\(.*\\)\\)" lable)
                (match-string 2 lable))))
      (cons lable signature)))
  )


(setq anything-yasnippet-completion-table nil)

(setq anything-c-source-complete-etags-js 
      '((name . "Etags Method Completion")
        (candidates 
         .
         (lambda () anything-yasnippet-completion-table)) 
        (init
         . 
         (lambda ()
           (condition-case x
               (setq anything-yasnippet-completion-table (mapcar 'anything-js-etags-parser
                                                             (split-string (shell-command-to-string "cat ~/etc/el/js/TAGS|grep ^[a-zA-Z0-9_].* |sed 's+\.<definition-[0-9]*>++g'|uniq") "\n")))
             (error (setq anything-yasnippet-completion-table nil))
             )
           )
         )
        (action
         ("Completion" . yasnippet-complete-js))
        ))

(defvar anything-js-introspect-re "\\(\\(.*\\)|\\(.*\\)\\)"
  "1:label | 2:property ")

(defun anything-js-introspect-parser (candidate)
  "parse the introspect candidate, return (lable . property)"
  (when (string-match anything-js-introspect-re candidate)
    (let* ((lable
             (match-string 2 candidate))
           (property
            (match-string 3 candidate))
           )
      (cons lable property)))
  )

(setq anything-yasnippet-introsepct-table nil)

(setq anything-c-source-complete-introspect-js 
      '((name . "Introspect Completion")
        (candidates 
         .
         (lambda () anything-yasnippet-introspect-table)) 
        (init
         . 
         (lambda ()
           (condition-case x
               (setq anything-yasnippet-introspect-table (mapcar
                                                          'anything-js-introspect-parser
                                                          (split-string
                                                          (shell-command-to-string
                                                           (format "jxmpfilter -c --line %d %s"
                                                                   (jct-current-line) (buffer-file-name))) "__JCT_NEWLINE__")
                                                          )) 
             (error (setq anything-yasnippet-introspect-table nil))
             )
           )
         )
        (action
         ("Completion" . yasnippet-complete-js))
        ))

(defun anything-complete-js ()
  "complete js methods and properties
from static imenu->etags index and dynamically generated properties via introspection"
  (interactive)
  (let ((anything-sources (list anything-c-source-complete-introspect-js
                                anything-c-source-complete-etags-js
                                )))
    (anything)))

(defun yasnippet-complete-syntax-expand (msg)
  "constructure an snippet according to the syntax signature string"
  (flymake-mode nil)
  (insert msg)
  (yas/expand))

(setq anything-yasnippet-completion-table nil)

(setq snippet-dot-re "\\(^.*\\)\\.\\(.*$\\)")

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
                          filename
                        ))
                    ))
              (push (cons lable stub)
                    syntax-expand-list))))))
                    syntax-expand-list
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


(defun yas/p (k &optional v)
  "define parameter expand when expand function

K is key parameter's key
V is key parameter's value
"
  (if v
      (yas/define major-mode k
              (format "%s => ${1:%s}" k v))
    (yas/define major-mode k k))
  k
  )

(setq yas-parameter-define-re "\\([a-z_:]*\\), \\([a-zA-Z0-9_':-]*\\) \\([a-zA-Z0-9_':-=>{} ]*\\)")

(defun yas/c (l)
  "compile the list into a yas template use `yas/p'

L is a string list, first element is function name, each key
value or key nil follow it"
  (setq para-fun '(lambda (para)
                    (string-match yas-parameter-define-re para)
                    (setq key-yas (match-string 2 para))
                    (setq val-yas (match-string 3 para))
                    (setq count (1+ count))
                    (if (> count 1)
                        (format ", ${%d:`(yas/p \"%s\" \"%s\")`}"
                                count
                                key-yas 
                                val-yas)
                      (format ", ${%d:`(yas/p \"%s\" \"%s\")`}$0"
                              count
                              key-yas 
                              val-yas))
                    ))
  (setq signature-template ((lambda (signature)
                              (let ((count 0))
                                (replace-regexp-in-string 
                                 yas-parameter-define-re
                                 para-fun
                                 signature
                                 ))
                              ) l))
  (string-match yas-parameter-define-re l)
  (insert (concat (match-string 1 l) signature-template))
  )

(defun yas/tap ()
  "thing-at-point yas/c => yas template"
  (interactive)
  (set-mark (point))
  (beginning-of-line)
  (setq beg (point))
  (search-forward ") ")
  (setq cur (point))
  (setq yas-line (substring (thing-at-point 'line) (- cur beg)))
  (search-forward "# --")
  (forward-line)
  (beginning-of-line)
  (setq beg (point))
  (end-of-buffer)
  (setq end (point))
  (kill-region beg end)
  (yas/c yas-line)
  (set-mark-command -1))

(provide 'anything-yasnippet)
