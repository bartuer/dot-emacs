(defun octave-setting ()
  (autoload 'octave-mode "octave-mod" nil t)
  (setq auto-mode-alist
        (cons '("\\.mt$" . octave-mode) auto-mode-alist))
  (add-hook 'octave-mode-hook
            (lambda ()
              (abbrev-mode 1)
              (auto-fill-mode 1)
              (if (eq window-system 'x)
                  (font-lock-mode 1))))
  )
(defun bartuer-octave-help ()
  "search info get function document"
  (interactive)
  (octave-help)
  )

(defun bartuer-matlab-load ()
  "for matlab/octave language"
  (interactive)
  (let ((map matlab-mode-map))
    (define-key map "\C-c\C-s" (lambda ()
                                 (interactive)
                                 (if (bufferp (get-buffer "*Inferior Octave*"))
                                     (octave-show-process-buffer)
                                   (run-octave)
                                   )
                                 ))
    (define-key map "\C-ch" 'bartuer-octave-help)
    (define-key inferior-octave-mode-map "\C-ch" 'bartuer-octave-help)
    (define-key map "\C-cl" 'octave-send-line)
    (define-key map "\C-cb" 'octave-send-block)
    (define-key map "\C-cf" 'octave-send-defun)
    (define-key map "\C-cr" 'octave-send-region)
    (define-key map "\C-cs" 'octave-show-process-buffer)
    (define-key map "\C-ck" 'octave-kill-process)
    (define-key map "\C-c\C-l" 'octave-send-line)
    (define-key map "\C-c\C-b" 'octave-send-block)
    (define-key map "\C-c\C-f" 'octave-send-defun)
    (define-key map "\C-c\C-r" 'octave-send-region)
    (define-key map "\C-c\C-k" 'octave-kill-process)
    )
  )

(provide 'bartuer-matlab)