(defun web-beautify-css-buffer-win ()
  "Format the current buffer according to the css-beautify command."
  (web-beautify-format-buffer (locate-file  "css-beautify.bat" (list "~/etc/el/vendor/node_modules/js-beautify/js/bin/")) "css"))

(defun bartuer-css-load ()
  "css mode modification

mainly minimize css file by `css-min', for css validation see
`flymake-css-init', for css document query, see `css-find', for
css imenu build see `css-extract-keyword-list'
"
  (interactive)
  (flymake-mode nil)
  (emmet-mode)
  (define-key css-mode-map "{" 'css-mode-electric-insert-close-brace)
  (add-hook 'before-save-hook (if (string= system-type "windows-nt")
                                  'web-beautify-css-buffer-win
                                  'web-beautify-css-buffer) t t)
  )
