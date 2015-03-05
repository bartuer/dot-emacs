;; This buffer is for notes you don't want to save, and for Lisp evaluation.
;; If you want to create a file, visit that file with C-x C-f,
;; then enter the text in that file's own buffer.

(setq gdb-locals-font-lock-keywords
  '(;; var = type value
    ("\\(\\((.*)\\) \\(.*?\\) =\\)"
      (2 font-lock-variable-name-face)
      (3 font-lock-constant-face))))
  ;; "Font lock keywords used in `gdb-local-mode'.")

(defun gdb-local-invisible-overlay-bounds (&optional pos)
  "Return cons cell of bounds of folding overlay at POS.
Returns nil if not found."
  (let ((overlays (overlays-at (or pos (point))))
        o)
    (while (and overlays
                (not o))
      (if (overlay-get (car overlays) 'invisible)
          (setq o (car overlays))
        (setq overlays (cdr overlays))))
    (if o
        (cons (overlay-start o) (overlay-end o)))))

(defun gdb-local-flag-region (flag)
  "Hide or show text from FROM to TO, according to FLAG.
If FLAG is nil then text is shown, while if FLAG is t the text is hidden.
Returns the created {...} overlay if FLAG is non-nil."
  (beginning-of-line)
  (let* ((from (re-search-forward "{" (line-end-position) t)))
    (when from
      (progn
        (let ((to (- (scan-sexps (- from 2) 1) 1)))
          (remove-overlays from to 'invisible 'gdb-locals-outline)
          (when flag
            (let ((o (make-overlay from to)))
              (overlay-put o 'invisible 'gdb-locals-outline)
              o)))))))

(defun gdb-local-toggle ()
  "toggle current line's data structure show"
  (interactive)
  (if (gdb-local-invisible-overlay-bounds)
      (gdb-local-flag-region nil)
    (gdb-local-flag-region t)))

(defun gdb-locals-mode ()
  "Major mode for gdb locals.

\\{gdb-locals-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (setq major-mode 'gdb-locals-mode)
  (setq mode-name (concat "Locals:" gdb-selected-frame))
  (use-local-map gdb-locals-mode-map)
  (setq buffer-read-only t)
  (buffer-disable-undo)
  (setq header-line-format gdb-locals-header)
  (gdb-thread-identification)
  (set (make-local-variable 'font-lock-defaults)
       '(gdb-locals-font-lock-keywords))
  (run-mode-hooks 'gdb-locals-mode-hook)
  (add-to-invisibility-spec '(gdb-locals-outline . t))
  (if (and (eq (buffer-local-value 'gud-minor-mode gud-comint-buffer) 'gdba)
	   (string-equal gdb-version "pre-6.4"))
      'gdb-invalidate-locals
    'gdb-invalidate-locals-1)
  )

(defun gdb-edit-locals-value (&optional event)
  "Assign a value to a variable displayed in the locals buffer."
  (interactive (list last-input-event))
  (save-excursion
    (if event (posn-set-point (event-end event)))
    (setq value-name
          (cond ((re-search-backward "\\w = " (line-beginning-position) t)
           (current-word))
          ((re-search-backward " \[[0-9]+\] = " (line-beginning-position) t)
           (let ((num (current-word))
                  (array (progn (backward-up-list)
                                (re-search-backward "\\w = " (line-beginning-position) t)
                                (current-word))))
              (concat array "[" num "]")))
          (t (current-word))))
    (let* ((var value-name)
	   (value (read-string (format "New value (%s): " var))))
      (gdb-enqueue-input
       (list (concat  gdb-server-prefix "set variable " var " = " value "\n")
	     'ignore)))))

(setq gdb-locals-regex "\\(^[^ }]+\\)\\( = *\\)\\(.*\\)")
(defun gdb-info-locals-handler-1 ()
  (setq gdb-pending-triggers (delq 'gdb-invalidate-locals-1
                                   gdb-pending-triggers))
  (setq gdb-locals-list '())
  (let ((buf (gdb-get-buffer 'gdb-partial-output-buffer)))
    (with-current-buffer buf
      (goto-char (point-min))
      (while (re-search-forward gdb-locals-regex nil t)
        (let* ((name (match-string 1))
               (type "type")
               (value (match-string 3))
               (beg3 (- (point) (string-width value)))
               (pos (string-match "{" (match-string 3)))
               )
          (if pos
              (progn
                (let* ((begin (+ beg3 pos))
                       (end (scan-sexps begin 1)))
                  (add-to-list
                   'gdb-locals-list
                   (cons name (cons type
                                    (buffer-substring-no-properties begin end))))))
            (add-to-list 'gdb-locals-list (cons name (cons type value))))
          )
        )
      ))
  (run-hooks 'gdb-info-locals-hook))

(defun gdb-stack-list-locals-handler-2 ()
  (setq gdb-pending-triggers (delq 'gdb-invalidate-locals-2
				  gdb-pending-triggers))
  (goto-char (point-min))
  (if (re-search-forward gdb-error-regexp nil t)
      (let ((err (match-string 1)))
	(with-current-buffer (gdb-get-buffer 'gdb-locals-buffer)
	  (let ((buffer-read-only nil))
	    (erase-buffer)
	    (insert err)
	    (goto-char (point-min)))))
    (let (local)
      (goto-char (point-min))
      (while (re-search-forward gdb-stack-list-locals-regexp nil t)
	(let ((name (match-string 1))
              (type (match-string 2)))
	  (setcar (cdr (assoc name gdb-locals-list)) type)))
      (let ((buf (gdb-get-buffer 'gdb-locals-buffer)))
	(and buf (with-current-buffer buf
		   (let* ((window (get-buffer-window buf 0))
			  (start (window-start window))
			  (p (if window (window-point window) (point)))
			  (buffer-read-only nil) (name) (value))
		     (erase-buffer)
		     (dolist (local gdb-locals-list)
		       (setq name (car local))
		       (setq value (cddr local))
		       (unless (or (not value)
		               (string-match "^\\0x" value))
		         (add-text-properties 0 (length value)
		              `(mouse-face highlight
		                help-echo "mouse-2: edit value"
		                local-map ,gdb-edit-locals-map-1)
		              value))
                       (insert
			(concat "(" (nth 1 local) ") " name 
				" = " value "\n")))
		     (if window
			 (progn
			   (set-window-start window start)
			   (set-window-point window p))
		       (goto-char p)))))))))

(defun gdb-post-prompt (ignored)
  "An annotation handler for `post-prompt'.
This begins the collection of output from the current command if that
happens to be appropriate."
  ;; Don't add to queue if there outstanding items or gdb-version is not known
  ;; yet.
  (unless (or gdb-pending-triggers gdb-first-post-prompt)
    (gdb-get-selected-frame)
    (gdb-invalidate-frames)
    ;; Regenerate breakpoints buffer in case it has been inadvertantly deleted.
    (gdb-get-buffer-create 'gdb-breakpoints-buffer)
    (gdb-invalidate-breakpoints)
    ;; Do this through gdb-get-selected-frame -> gdb-frame-handler
    ;; so gdb-pc-address is updated.
    ;; (gdb-invalidate-assembler)

    (if (string-equal gdb-version "pre-6.4")
	(gdb-invalidate-registers)
      (gdb-get-changed-registers)
      (gdb-invalidate-registers-1))

    (gdb-invalidate-memory)
    (gdb-invalidate-locals-1)
    (gdb-invalidate-locals-2)

    (gdb-invalidate-threads)
    (unless (or (null gdb-var-list)
	     (eq system-type 'darwin)) ;Breaks on Darwin's GDB-5.3.
      ;; FIXME: with GDB-6 on Darwin, this might very well work.
      ;; Only needed/used with speedbar/watch expressions.
      (when (and (boundp 'speedbar-frame) (frame-live-p speedbar-frame))
	(if (string-equal gdb-version "pre-6.4")
	    (gdb-var-update)
	  (gdb-var-update-1)))))
  (setq gdb-first-post-prompt nil)
  (let ((sink gdb-output-sink))
    (cond
     ((eq sink 'user) t)
     ((eq sink 'pre-emacs)
      (setq gdb-output-sink 'emacs))
     (t
      (gdb-resync)
      (error "Phase error in gdb-post-prompt (got %s)" sink)))))

(def-gdb-auto-update-trigger gdb-invalidate-locals-1
  (gdb-get-buffer 'gdb-locals-buffer)
  (if (eq (buffer-local-value 'gud-minor-mode gud-comint-buffer) 'gdba)
      "server info locals\n"
    "info locals\n")
  gdb-info-locals-handler-1)

(def-gdb-auto-update-trigger gdb-invalidate-locals-2
  (gdb-get-buffer 'gdb-locals-buffer)
  (if (eq (buffer-local-value 'gud-minor-mode gud-comint-buffer) 'gdba)
      "server interpreter mi -\"stack-list-locals --simple-values\"\n"
    "-stack-list-locals --simple-values\n")
  gdb-stack-list-locals-handler-2)