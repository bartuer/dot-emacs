
(easy-mmode-defmap bartuer-note-mode-map
  `(("\C-c\C-c" . bartuer-note-done)
    ("\C-cc" . bartuer-note-done))
  "Keymap for the `bartuer-note-mode' (to edit version control log messages).")

(define-derived-mode bartuer-note-mode text-mode "Note"
  "Major mode for editing note .
     \\{bartuer-note-mode-map}
     Turning on Note mode runs the normal hook `bartuer-note-mode-hook'."
  (make-local-variable 'bartuer-note-mode-variant)
  (make-local-variable 'note-buffer)
  (make-local-variable 'mark-buffer)
  (setq bartuer-note-mode-variant t))

(defun bartuer-check-mark-mode-line ()
  (goto-char (point-min))
  (let ((first-endline (search-forward "\n" nil t)))
    (goto-char (point-min))
    (unless (search-forward "mode:grep"
                          first-endline
                          t)
      (goto-char (point-min))
      (insert-string "-*- mode:grep -*-\n"))))

(defun bartuer-note-done ()
  (interactive)
  (set-buffer (car mark-buffer))
  (toggle-read-only -1)
  (goto-char (point-max))
  (insert-string "\n")
  (set-buffer (car note-buffer))
  (let ((start (point-min))
        (end (point-max)))
  (append-to-buffer (car mark-buffer) start end)
  (set-buffer (car mark-buffer))
  (basic-save-buffer)
  (set-buffer (car note-buffer))
  (message "note added")
  (kill-buffer-and-window)))

(defun bartuer-read-mark () 
  (interactive)
   (setq mark-buffer
          (list (find-file-noselect
           (format "%s-marks" (bookmark-buffer-name)))))
   (let ((target-file-name (buffer-file-name))
         (target-line-number (line-number-at-pos))
         (target-buffer (current-buffer))
         (start (region-beginning))
         (end (region-end)))
     (save-excursion
       (set-buffer (car mark-buffer))
       (bartuer-check-mark-mode-line)
       (grep-mode)
       (toggle-read-only -1)
       (goto-char (point-max))
       (insert-string (format "\n\n%s:%d: \n["
                              target-file-name
                              target-line-number))
       (insert-buffer-substring target-buffer start end)
       (insert-string "]"))
     (setq note-buffer
            (list (switch-to-buffer-other-window "bartuer-note")))
     (set-buffer (car note-buffer))
     (bartuer-note-mode)))

