(require 'anything-yasnippet)

(defun bartuer-objc-load ()
  "mode hooks for objc"
  (interactive)
  (flyspell-prog-mode)
  (flymake-mode t)
  (define-key objc-mode-map "\C-\M-i" 'anything-etags-complete-objc-message)
)


;; anything-etags package is a good replacer for icicle-find-tag ?
;; yes, definitely                         

;; get instance and class method list depend on the context
;; no, do not need that, just type to select, show difference with + and -

;; when typing, display user the filtered function name, using ido ?
;; anything-match-plugin.el match the require ido, it is a wonderful replacement for icicle's regexp filters

;; dynamic generate yasnippet for signature
;; define the action in anything-dyasnippet.el




