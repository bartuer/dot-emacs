(defun buddy-get (word)
  (let* ((timeout 180)
         (post-cmd
          (concat "GET /word/" word " HTTP/1.0\r\n"
                  "Host: localhost \r\n"
                  "User-Agent: Emacs\r\n"
                  "Accept: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5\r\n"
                  "Accept-Language: en-us,en;q=0.5\r\n"
                  "\r\n"))
         proc buf)

    (unwind-protect
        (progn
          (setq proc (open-network-stream "url-get-command"
                                          "*url-get-buffer*"
                                          "localhost"
                                          3721)
                buf (process-buffer proc))
          (process-send-string proc post-cmd)
          (while (equal (process-status proc) 'open)
            (unless (accept-process-output proc timeout)
              (delete-process proc)
              (error "Server error: timed out while waiting!")))
          ))
    buf))

(defun explain-current-in-brower ()
  (interactive)
  (let ((w (thing-at-point 'word)))
    (buddy-get w)
    ))

(defalias 'bd 'explain-current-in-brower)

(defcustom buddy-minor-mode-string " bd" 
  "String to display in mode line when buddy mode is enabled; nil for none."
  :type '(choice string (const :tag "None" nil))
  )

(define-minor-mode buddy-minor-mode
  "Minor mode query word under cursor from buddy"
  :lighter buddy-minor-mode-string
  (cond
   (buddy-minor-mode
    (add-hook 'post-command-hook 'explain-current-in-brower nil t)
    )
   (t
    (remove-hook 'post-command-hook 'explain-current-in-brower t)
  )))

  

(provide 'bartuer-buddy)