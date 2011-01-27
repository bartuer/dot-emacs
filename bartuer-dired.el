(defun dired-copy-filename-as-kill-fix (&optional arg)
  "Copy names of marked (or next ARG) files into the kill ring.
The names are separated by a space.
With a zero prefix arg, use the absolute file name of each marked file.
With \\[universal-argument], use the file name relative to the dired buffer's
`default-directory'.  (This still may contain slashes if in a subdirectory.)

If on a subdir headerline, use absolute subdirname instead;
prefix arg and marked files are ignored in this case.

You can then feed the file name(s) to other commands with \\[yank]."
  (interactive "P")
  (let ((string
         (or (dired-get-subdir)
             (mapconcat (function identity)
                        (if arg
                            (cond ((zerop (prefix-numeric-value arg))
                                   (dired-get-marked-files))
                                  ((consp arg)
                                   (dired-get-marked-files t))
                                  (t
                                   (dired-get-marked-files
				    'no-dir (prefix-numeric-value arg))))
                          (dired-get-marked-files ))
                        " "))))
    (if (eq last-command 'kill-region)
	(kill-append string nil)
      (kill-new string))
    (message "%s" string)))

(provide 'bartuer-dired)
