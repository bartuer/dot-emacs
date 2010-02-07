(require 'xml-parse nil t)

(defun xml-tag-end (data-end-pos)
  (save-excursion
    (goto-char data-end-pos)
    (unless (eq (char-after) nil)
      (xml-parse-skip-tag))
    (point)))

(defun search-forward-tag-head-aug (end inner-p)
  (if (and inner-p
           (stringp (cadr tag))
           (string-equal (cadr tag) "script"))
      (progn
        (search-forward "</script" end t)
        (backward-char 8)
        )
    (search-forward "<" end t)))

;; borrow from http://www.gci-net.com/~johnw/emacs.html, if the xml
;; document has error, such as unclosed tag, parse will fail
;; if embedded script has <, the parser should handle that

(defun xml-to-sexp (&optional inner-p)
  "parse a xml document to sexp

  for example, below piece of xml

      <head>
      <title>the title</title>
      <meta name=\"the name\" content=\"the content\" />
      </head>

  will parsed to:

     ((793 . 885)
      \"head\"
     ((802 . 826)
      \"title\"
      (809 . 818))
     ((829 . 875)
      \"meta name the name content the content\"))

  For each tag, car is (cons beg and) of the tag,
  then follow the name attribute string of that tag.

  If that tag include any inner HTML, then (cons beg end) of the
  inner part, if that tag has children, sexp of children
  followed, else, end of the tag sexp. "
  
  (let ((beg (search-forward-tag-head-aug nil inner-p)) after)
    (while (and beg (memq (setq after (char-after)) '(?! ??)))
      (xml-parse-skip-tag)
      (setq beg (search-forward "<" nil t)))
    (when beg
      (if (eq after ?/)
	  (progn
	    (search-forward ">")
	    (cons (1- beg)
		  (buffer-substring-no-properties (1+ beg) (1- (point)))))
	(skip-chars-forward "^ \t\n/>")
	 (progn
	   (setq after (point))
	   (skip-chars-forward " \t\n")
	   (let* ((single (eq (char-after) ?/))
		  (tag (buffer-substring-no-properties beg after))
		  attrs data-beg data)
	     ;; handle the attribute list, if present
	     (cond
	      (single
	       (skip-chars-forward " \t\n/>"))
	      ((eq (char-after) ?\>)
	       (forward-char 1))
	      (t
	       (let* ((attrs (list t))
		      (lastattr attrs)
		      (end (search-forward ">")))
		 (goto-char after)
		 (while (re-search-forward
			 "\\([^ \t\n=]+\\)=\"\\([^\"]+\\)\"" end t)
		   (let ((attr (cons (match-string-no-properties 1)
				     (match-string-no-properties 2))))
		     (setcdr lastattr (list attr))
		     (setq lastattr (cdr lastattr))))
		 (goto-char end)
		 (setq tag (concat tag " " (mapconcat
                                            (lambda (l)
                                              (concat (car l) " " (cdr l)))
                                            (cdr attrs) " "))
		       single (eq (char-before (1- end)) ?/)))))
	     ;; return the tag and its data
	     (if single
                   (setq tag (list (cons (1- beg) (xml-tag-end (1- beg))) tag))
	       (setq tag (list (1- beg) tag))
	       (let ((data-beg (point))(tag-end (last tag)) (tag-beg (1- beg)))
		 (while (and (setq data (xml-to-sexp t))
			     (not (stringp (cdr data))))
		   (setcdr tag-end (list data))
		   (setq tag-end (cdr tag-end))
                   )
                 (if (eq (car tag) tag-beg)
                     (progn
                       (setcar tag (cons (car tag)
                                         (xml-tag-end (or (car data)
                                                          (point-max)))))
                       (unless (cddr tag)
                           (setq tag (list
                                  (car tag)
                                  (cadr tag)
                                  (cons data-beg (car data)))))
                       )
                   (setq tag (list (cons (car tag) (xml-tag-end (car data))) (cadr tag))))
		 tag)
               )))))))

(defun xml-sexp-to-imenu (sexp level)
  "convert the sexp of xml to imenu alist

  for a sexp converted from xml by `xml-to-sexp', only the tag
  start position and tag name ,attribute string will be added
  to `imenu--index-alist', using prefix string \"|-\" to denote
  the level of tag.
"
  (setq start-pos nil)
  ;; if the third item is list, that means level should increase one
  (let ((index 0))                      
    (dolist (item sexp)
      (setq index (1+ index))
      (cond
       ((and
         (listp item)
         (consp (car item)))
        (if (eq index 3) 
            (setq level (1+ level)))
        (xml-sexp-to-imenu item level)
        )
       ((stringp item)
        (let ((l level)
              (level-prefix ""))
          (while (> l 0)
            (setq level-prefix (concat level-prefix "|-"))
            (setq l (1- l)))
          (push (cons (concat level-prefix item)
                      start-pos)
                imenu--index-alist)))
       ((consp item)
        (if (eq start-pos nil)
            (setq start-pos (car item))))))))

(defun xml-imenu ()
  (setq imenu--index-alist nil)
  (save-excursion
    (goto-char (point-min))
    (xml-sexp-to-imenu (xml-to-sexp) 0)
    (setq imenu--index-alist (reverse imenu--index-alist))))


(defun xml-format ()
  "parse the dom tree, then insert it again"
  (interactive)
  (goto-char (point-min))
  (save-excursion
    (let ((tree (read-xml)))
      (kill-region (point-min) (point-max))
      (insert-xml tree)
      (indent-region (point-min) (point-max)))))

(provide 'xml-augment)