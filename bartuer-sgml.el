(require 'emmet nil t)


(defun web-beautify-format-region-html (beg end)
  "By PROGRAM, format each line in the BEG .. END region."
  (let* ((program (locate-file  "html-beautify.js" (list "~/etc/el/vendor/node_modules/js-beautify/js/bin/"))))
    (save-excursion
      (apply 'call-process-region beg end program t
             (list t nil) t web-beautify-args))))

(defun bartuer-sgml-load ()
  "html mode modification"
  (flyspell-mode-off)
  (emmet-mode)
  (setq indent-region-function nil)
  (define-key sgml-mode-map "\C-\M-f" 'sgml-skip-tag-forward)
  (define-key sgml-mode-map "\C-\M-b" 'sgml-skip-tag-backward)
  (define-key sgml-mode-map "\C-\M-k" 'sgml-delete-tag)
  (define-key sgml-mode-map "\C-\M-v" 'sgml-validate)
  (define-key sgml-mode-map "\C-c\C-ct" 'sgml-close-tag)
  (add-hook 'before-save-hook 'web-beautify-html-buffer t t)
  (set (make-local-variable 'indent-region-function) 'web-beautify-format-region-html)
  )

(provide 'bartuer-sgml)

