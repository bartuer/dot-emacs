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

;; (set (make-local-variable 'forward-sexp-function) 'xml-forward-sexp)
(defun dom-tree ()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (setq dom-tree (xml-to-sexp)))
  (with-current-buffer (get-buffer-create
                        "*dom-tree*")
    (delete-region (point-min) (point-max))
    (insert (format "%S" dom-tree))))
    
(defun pos-inside (pos range)
  (if (consp range)
      (let ((left (car range))
            (right (cdr range)))
        (and
         (numberp left)
         (numberp right)
         (<= left pos)
         (>= right pos)))
    nil))

(defun search-inner-most-sexp (pos tree)
  "search most inner cons contain the POS in the TREE.

the TREE is genereated by `xml-to-sexp'.
returned cons is (head_of_tag_closure. end_of_tag_closure)."
  (let ((subtree nil)
        (loop-tree tree)
        item)
    (while (and
            (null subtree)
            (> (length loop-tree) 0))
      (when (listp (setq item (car loop-tree)))
        (cond ((pos-inside pos item)
               (setq cache loop-tree)
               (setq subtree (cddr loop-tree)))
              ((let ((index 2))
                 (when (pos-inside pos (car item))
                     (while (and
                             (null subtree)
                             (< index (length item)))
                       (when (pos-inside pos (car (elt item index)))
                         (setq cache item)
                         (setq subtree (elt item index)))
                       (setq index (1+ index))))
                 (not (null subtree))))
              ((pos-inside pos (car item))
               (setq cache item)
               (setq subtree (car item)))))
      (setq loop-tree (cdr loop-tree)))
    (if (and
         (listp (car subtree))
         (> (length subtree) 0))
        (search-inner-most-sexp pos subtree)
      (if (null subtree)
          (if (consp (car cache))
              (car cache)
            cache)
        (if (consp (car subtree))
            (car subtree)
          subtree)))))

(defun xml-mark-sexp (&optional allow-extend)
  "Put mark at end of this tag closure, point at beginning. "
  (interactive "p")
  (let ((range (search-inner-most-sexp (point) dom-tree)))
    (cond ((and allow-extend
                (or (and (eq last-command this-command) (mark t))
                    (and transient-mark-mode mark-active)))
           (set-mark
            (save-excursion
              (goto-char (mark))
              (goto-char (cdr range))
              (point))))
          (t
           (let ((opoint (point))
                 beg end)
             (push-mark opoint)
             (goto-char (car range))
             (setq beg (point))
             (goto-char (cdr range)) 
             (setq end (point))
             (if (> (point) opoint)
                 (progn
                   (push-mark beg nil t)
                   (goto-char end)
                   (exchange-point-and-mark))
               (goto-char opoint)
               (goto-char (cdr range))
               (push-mark (point) nil t)
               (goto-char (car range)))
             )))))


(defun xml-next-tag-head ()
  (while (looking-at "<\\?")
      (search-forward "?>"))
  (while (looking-at "!--")
      (search-forward "-->")
      (search-forward "<")
      )
  (unless (eq (char-before) 60);'<'
    (search-forward "<"))
  (point))

(defun xml-forward (&optional pos)
  "if POS in a tag closure, current position will move to the head of the closure.

if POS is at end of the tag closure, current position will move
to the head of next tag closure.

default POS is current position."
  (interactive)
  (if (eq nil pos)
      (setq pos (point)))
  (let ((range (search-inner-most-sexp pos dom-tree)))
    (if (< pos (cdr range))
        (goto-char (cdr range))
      (xml-next-tag-head)
      )))

(defun xml-before-tag-tail ()
  (while (and
          (eq (char-after) 62);'?'
          (eq (char-before) 63));'-'
      (search-backward "<?")
      (search-backward ">")
      )
  (while (and
          (eq (char-after) 62)
          (eq (char-before) 45))
      (search-backward "<!--")
      (search-backward ">")
      )
  (unless (eq (char-after) 62);'>'
    (search-backward ">"))
  (point))

(defun xml-backward (&optional pos)
  "if POS in a tag closure, current position will move to the end of the closure.

if POS is at head of the tag closure, current position will move
to the end of previous tag closure.

default POS is current position."
  (interactive)
  (if (eq nil pos)
      (setq pos (point)))
  (let ((range (search-inner-most-sexp pos dom-tree)))
    (if (> pos (car range))
        (goto-char (car range))
      (xml-before-tag-tail)
      )
  ))

(defun xml-up (&optional pos)
  "if POS in a tag closure, position will move to the head of the current tag closure.

if POS is at the head of the tag closure, position will move to
the head of tag closure contain current one.  if POS is in a tag
closure's inner HTML, position will move to the head of current tag
closure.

default POS is current position."
  (interactive)
  (if (eq nil pos)
      (setq pos (point)))
  (let ((range (search-inner-most-sexp pos dom-tree))
        up-range)
    (with-current-buffer (get-buffer-create "*dom-tree*")
      (goto-char (point-min))
      (goto-char (search-forward (format "%S" range)))
      (if (eq (char-after) 41);')'
          (progn
            (search-backward "(" nil nil 2)
            (setq up-range (read (buffer-substring-no-properties
                                  (point)
                                  (search-forward ")")))))
        (while (or
                (null up-range)
                (eq pos (car up-range)))   
          (goto-char (scan-lists (point) 1 1))    ;; up-list
          (backward-sexp)
          (setq up-range (read (buffer-substring-no-properties
                                (1+ (point))
                                (save-excursion
                                  (search-forward ")"))))
                ))))
    (goto-char (car up-range))))

(defun xml-down (&optional pos)
  "if POS in a tag closure, position will move to the head of first child tag closure.

if current tag closure has no child, nothing will happen.

default POS is current position."
  (interactive)
  (if (eq nil pos)
      (setq pos (point)))
  (let ((range (search-inner-most-sexp pos dom-tree))
        down-range)
    (with-current-buffer (get-buffer-create "*dom-tree*")
      (goto-char (point-min))
      (goto-char (search-forward (format "%S" range)))
      (condition-case nil
          ((lambda ()
             (goto-char (scan-lists (point) 1 -1))
             (when (and
                    (eq (char-before) 40);'('
                    (not (eq (char-after) 40)))
                 (backward-char))
             (setq down-range (read (buffer-substring-no-properties
                              (point)
                              (save-excursion
                                (search-forward ")")))))))
        (error)))
    (when (numberp (car down-range))
      (goto-char (car down-range)))))

(defun xml-forward-adapt (&optional arg)
  (interactive "^p")
  (if (eq arg -1)
      (xml-backward)
    (xml-forward)))

(defun xml-augment-hook ()
  (set (make-local-variable 'forward-sexp-function) 'xml-forward-adapt)
  (set (make-local-variable 'imenu-create-index-function) 'xml-imenu)
  (define-key sgml-mode-map "\C-\M-h" 'xml-mark-sexp)
  (define-key html-mode-map "\C-\M-h" 'xml-mark-sexp) ;that would be shadow if not do this
  (define-key sgml-mode-map "\C-\M-u" 'xml-up)
  (define-key sgml-mode-map "\C-\M-d" 'xml-down)
  )

(provide 'xml-augment)
