;; This buffer is for notes you don't want to save, and for Lisp evaluation.
;; If you want to create a file, visit that file with C-x C-f,
;; then enter the text in that file's own buffer.

(defun my-complete-tag ()
  "Perform tags completion on the text around point.
Completes to the set of names listed in the current tags table.
The string to complete is chosen in the same way as the default
for \\[find-tag] (which see)."
  (interactive)
  (or tags-table-list
      tags-file-name
      (error "%s"
	     (substitute-command-keys
	      "No tags table loaded; try \\[visit-tags-table]")))
  (let ((completion-ignore-case (if (memq tags-case-fold-search '(t nil))
				    tags-case-fold-search
				  case-fold-search))
	(pattern (funcall (or find-tag-default-function
			      (get major-mode 'find-tag-default-function)
			      'find-tag-default)))
        (comp-table (tags-lazy-completion-table))
	beg
	completion)
    (or pattern
	(error "Nothing to complete"))
    (search-backward pattern)
    (setq beg (point))
    (forward-char (length pattern))
    (setq completion (try-completion pattern comp-table))
    (cond ((eq completion t))
	  ((null completion)
	   (message "Can't find completion for \"%s\"" pattern)
	   (ding))
	  ((not (string= pattern completion))
	   (delete-region beg (point))
	   (insert completion))
	  (t
	   (message "Making completion list...")
	   (setq selection (completing-read "Complete Symbol:"
	      (all-completions pattern comp-table nil)
	      ))
           (delete-region beg (point))
	   (insert selection)))))

(defun my-find-tag (tagname &optional next-p regexp-p)
  "find the location of tag and highlight it"
  (let* ((buf (find-tag-noselect tagname next-p regexp-p))
	 (pos (with-current-buffer buf (point))))
    (condition-case nil
	(switch-to-buffer buf)
      (error (pop-to-buffer buf)))
    (goto-char pos)
    (forward-line 1)
    (setq end-mk (point))
    (goto-char pos)
    (make-overlay pos end-mk)))
(setq icicle-candidate-help-fn 'my-find-tag)


