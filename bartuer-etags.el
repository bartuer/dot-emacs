(defun get-string-of-line (lineno)
  "Get the content of the line LINENO"
  (save-excursion
    (goto-line lineno)
    (beginning-of-line)
    (setq beg (point))
    (end-of-line)
    (setq end (point))
    (buffer-substring-no-properties beg end)
    ))

(defun add-etags-search-head (line)
  "Completion content of a TAGS file record according to line number information

A TAGS file record should be:
string in filesyntax meaning stringline number,position

Also see `tags-table-list'."
  (let* ((start (string-match "" line))
         (end (string-match "," line start))
         (lineno (substring line (+ 1 start) end)))
    (concat
     (get-string-of-line (read lineno))
     ""
     line)))

(defun flat-alist (entry)
  "Go through alist returned by `imenu--make-index-alist'

Also see `imenu-2-etags'."
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
  "convert imenu to etags string list

Also see `generate-etags'."
  (mapcar 'add-etags-search-head 
          (cdr (mapcan
                'flat-alist
                (imenu--make-index-alist t)))))

(defvar emacs-etags-file-name "/tmp/TAGS"
  "`generate-etags''s output

Default is at the directory indicated when invoke `generate-etags'.")

(defun write-etags (filename)
  "parse a file and write the parse result (for using as TAGS) to TAGS file

FILENAME the file to be parsed
Also see `generate-etags', the result is written to `emacs-etags-file-name'"
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
    (write-region (point-min) (point-max) emacs-etags-file-name t)
    )
  )

(defun generate-etags (dir pattern)
  "Generate TAGS file using file's imenu parse result.

DIR is the root directory to process
PATTERN is file name pattern to process

About imenu, see `imenu'.  About TAGS, see `tags-table-list'.

The result is written to `emacs-etags-file-name'."
  (interactive
   "Ddirectory: \nsfile-name : ")
  (setq emacs-etags-file-name (concat dir "/TAGS"))
  (let ((files (butlast (split-string (shell-command-to-string
                              (concat
                               "find "
                               dir
                               " -name "
                               (shell-quote-argument pattern)))
                               "\n"))))
    (mapcar 'write-etags files)))
