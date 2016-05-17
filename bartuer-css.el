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
  (add-hook 'before-save-hook 'web-beautify-css-buffer t t)
  )
