(require 'anything)
(require 'yasnippet)

(defvar anything-objc-parameter-define-re "\\(:([a-zA-Z_0-9_-\\<\\>,()\\*\\ ]*)[a-zA-Z0-9_-]+\\|\\.\\.\\.\\)"
  "(type)name")


(setq test ":(int32_t)integer :(NSInteger (*)(id, id, void *))comparator :(id <NSDecimalNumberBehaviors>)behavior :(const char *)types, ...")
((lambda (signature)
   (let ((count 0))
     (replace-regexp-in-string
      anything-objc-parameter-define-re
      (lambda (para)
        (setq count (1+ count))
        (format " :${%d%s}" count para))
        signature))) test)

  
(defun yasnippet-complete-obj-message (msg)
  "constructure an snippet according to the objc signature string"
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
  ;; TODO:need hooks disable/endable flymake
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

(setq anything-c-source-complete-etags-objc
  '((name . "Etags Method Completion")
    (candidates
     . (lambda ()
         (mapcar 'anything-objc-etags-parser
               (split-string
                (shell-command-to-string "cat ~/Documents/TAGS|grep ^[+-].*") "\n"))) ;TODO: if I have more TAGS?
     )
    (action
     ("Completion" . yasnippet-complete-obj-message))
    (persistent-action . yasnippet-complete-obj-message)))

(defun anything-etags-complete-objc-message ()
  "using anything framework search iphone cocoa etags, select one signature feed to yasnippet "
  (interactive)
  (let ((anything-sources (list anything-c-source-complete-etags-objc)))
    (anything)))
