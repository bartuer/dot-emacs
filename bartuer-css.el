(defun css-min ()
  "invoke yuicompress minimize current buffer"
  (let ((file-name (replace-regexp-in-string ".css" "_min.css"  (buffer-file-name))))
        (unless (eq 0 (shell-command (concat
                                      "~/etc/el/vendor/yui/css-min "
                                      (buffer-file-name)  " " file-name) nil))
          (message "minimize css failed")
          )
  ))

(defun bartuer-css-load ()
  "css mode modification

mainly minimize css file by `css-min', for css validation see
`flymake-css-init', for css document query, see `css-find', for
css imenu build see `css-extract-keyword-list'
"
  (interactive)
  (flymake-mode t)
  (define-key css-mode-map "{" 'css-mode-electric-insert-close-brace)
  )

(require 'bartuer-page nil t)