(defun get-string-of-line (lineno)
  (save-excursion
    (goto-line lineno)
    (beginning-of-line)
    (setq beg (point))
    (end-of-line)
    (setq end (point))
    (buffer-substring-no-properties beg end)
    ))

(defun add-etags-search-head (line)
  (let* ((start (string-match "" line))
         (end (string-match "," line start))
         (lineno (substring line (+ 1 start) end)))
    (concat
     (get-string-of-line (read lineno))
     ""
     line)))

(defun flat-alist (entry)
  (if (listp (cdr entry))
      (mapcan (lambda (sub)
                (if (consp (cdr sub))
                    (mapcar
                     (lambda (subentry)
                       (concat
                        (car entry)
                        "." subentry))
                     (flat-alist sub))
                  (list (concat
                         (car entry) "." (car sub) ""
                         (format "%d,%d\n"
                                 (line-number-at-pos (cdr sub))
                                 (let ((pos (cdr sub)))
                                   (if (markerp pos)
                                       (marker-position pos)
                                     pos)))))))
              (cdr entry))
    (list (format "%s%d,%d\n"
                  (car (car (list entry)))
                  (line-number-at-pos (cdr (car (list entry))))
                  (let ((pos (cdr (car (list entry)))))
                    (if (markerp pos)
                        (marker-position pos)
                      pos))))))

(defun imenu-2-etags ()
  (mapcar 'add-etags-search-head 
          (cdr (mapcan
                'flat-alist
                (imenu--make-index-alist)))))

(defun write-etags (filename)
  "should invoke it in virtual dired mode"
  (interactive)
  (setq etags-string-size 0)
  (setq etags-string "")

  (with-current-buffer (find-file (expand-file-name filename))
    (setq etags-string (imenu-2-etags))
    (setq etags-string-size (apply '+ (mapcar 'length etags-string)))
    )
  
  (with-current-buffer (get-buffer-create "imenu-2-etags")
    (when (buffer-size)
      (erase-buffer))
    (insert "\n")
    (insert (expand-file-name filename))
    (insert (format ",%d\n" etags-string-size))
    (mapcar 'insert etags-string)
    (write-region (point-min) (point-max) "/tmp/TAGS" t)
    )
  )

(defun generate-etags (dir pattern)
  (interactive
   "Ddirectory: \nsfile-name : ")
  (let ((files (butlast (split-string (shell-command-to-string
                              (concat
                               "find "
                               dir
                               " -name "
                               (shell-quote-argument pattern)))
                               "\n"))))
    (mapcar 'write-etags files)))
