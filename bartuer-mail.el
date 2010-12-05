(defun quote-encoded-subject ()
  (mail-position-on-field "Subject")
  (let ((beg ((lambda ()
                (beginning-of-line)
                (point))))
        (end ((lambda ()
                (end-of-line)
                (point)))))
    (unless (re-search-forward "=\\?UTF-8" (end-of-line) t 1)
    (let ((end (point))
          (start ((lambda ()
                    (beginning-of-line)
                    (re-search-forward "Subject:")
                    (point)
                    ))))
      (insert (concat  " =?UTF-8?Q?_" (quote-encoded-string (buffer-substring-no-properties start end) buffer-file-coding-system)
                       "?="))
      (kill-line)
      )
    )) 
  )

(defun quote-encoded-string (str coding-system)
  "Return a pretty description of STR that is encoded by CODING-SYSTEM."
  (setq str (string-as-unibyte str))
  (mapconcat
   (if (and coding-system (eq (coding-system-type coding-system) 'iso-2022))
       ;; Try to get a pretty description for ISO 2022 escape sequences.
       (function (lambda (x) (or (cdr (assq x iso-2022-control-alist))
				 (format "%02X" x))))
     (function (lambda (x) (format "=%02X" x))))
   str ""))

(defun utf8-quoted-code (char)
  (let* ((charset )
         (coding buffer-file-coding-system)
         (encoded (encode-coding-char char coding nil)))
    (if encoded
        (quote-encoded-string encoded coding)
      (list "not encodable by coding system"
            (symbol-name coding)))
    )
  )

(defun quoted-printable-encode-region (from to &optional fold class)
  "Quoted-printable encode the region between FROM and TO per RFC 2045.

If FOLD, fold long lines at 76 characters (as required by the RFC).
If CLASS is non-nil, translate the characters not matched by that
regexp class, which is in the form expected by `skip-chars-forward'.
You should probably avoid non-ASCII characters in this arg.

If `mm-use-ultra-safe-encoding' is set, fold lines unconditionally and
encode lines starting with \"From\"."
  (interactive "r")
  (unless class
    ;; Avoid using 8bit characters. = is \075.
    ;; Equivalent to "^\000-\007\013\015-\037\200-\377="
    (setq class "\010-\012\014\040-\074\076-\177"))
  (save-excursion
    (goto-char from)
    (save-restriction
      (narrow-to-region from to)
      ;; Encode all the non-ascii and control characters.
      (goto-char (point-min))
      (while (and (skip-chars-forward class)
		  (not (eobp)))
	(insert
	 (prog1
	     ;; To unibyte in case of Emacs 23 (unicode) eight-bit.
	     (utf8-quoted-code (char-after))
	   (delete-char 1))))
      ;; Encode white space at the end of lines.
      (goto-char (point-min))
      (while (re-search-forward "[ \t]+$" nil t)
	(goto-char (match-beginning 0))
	(while (not (eolp))
	  (insert
	   (prog1
	       (format "=%02X" (char-after))
	     (delete-char 1)))))
      (let ((mm-use-ultra-safe-encoding
	     (and (boundp 'mm-use-ultra-safe-encoding)
		  mm-use-ultra-safe-encoding)))
	(when (or fold mm-use-ultra-safe-encoding)
	  (let ((tab-width 1))		; HTAB is one character.
	    (goto-char (point-min))
	    (while (not (eobp))
	      ;; In ultra-safe mode, encode "From " at the beginning
	      ;; of a line.
	      (when mm-use-ultra-safe-encoding
		(if (looking-at "From ")
		    (replace-match "From=20" nil t)
		  (if (looking-at "-")
		      (replace-match "=2D" nil t))))
	      (end-of-line)
	      ;; Fold long lines.
	      (while (> (current-column) 76) ; tab-width must be 1.
		(beginning-of-line)
		(forward-char 75)	; 75 chars plus an "="
		(search-backward "=" (- (point) 2) t)
		(insert "=\n")
		(end-of-line))
	      (forward-line))))))))

(defun mail-dwim ()
  (interactive)
  (if (org-at-table-p)
      (org-export-table-to-mail)
    (compose-mail)
    ))

(provide 'bartuer-mail)