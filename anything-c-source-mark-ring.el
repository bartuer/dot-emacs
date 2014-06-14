; C-u C-SPC で anything-c-source-mark-ring 発動
;; copy this file from http://d.hatena.ne.jp/grandVin/20081204/1228368598
;; japanese guys have development really cool language and do greate improvement to anything


(defvar anything-c-source-mark-ring
  '((name . "Mark Ring")
    (candidates . anything-c-source-mark-ring-candidates)
    (action . (("Goto line" . (lambda (candidate)
                                (goto-line (string-to-number candidate))))))
    (persistent-action . (lambda (candidate)
                           (switch-to-buffer anything-current-buffer)
                           (goto-line (string-to-number candidate))
                           (set-window-start (get-buffer-window anything-current-buffer) (point))
                            
                           (anything-persistent-highlight-point
                            (line-beginning-position)
                            (line-end-position)
                            anything-current-buffer)
                           ))
    ))

(defun anything-c-source-mark-ring-candidates ()
  (with-current-buffer anything-current-buffer
    (let* ((marks (cons (mark-marker) mark-ring))
           (lines (mapcar (lambda (pos)
                            (save-excursion
                              (goto-char pos)
                              (beginning-of-line)
                              (let ((line  (car (split-string (thing-at-point 'line) "[\n\r]"))))
                                (when (string= "" line)
                                  (setq line  "<EMPTY LINE>"))
                                (format "%7d: %s" (line-number-at-pos) line))))
                          marks)))
      lines
      )))


;; global-mark
(defvar anything-c-source-global-mark-ring
  '((name . "Global Mark Ring")
    (candidates . anything-c-source-global-mark-ring-candidates)
    (action . (("Goto line" . (lambda (candidate)
                                (let ((items (split-string candidate ":")))
                                  (switch-to-buffer (second items))
                                  (goto-line (string-to-number (car items))))))))
    
    (persistent-action . (lambda (candidate)
                           (let ((items (split-string candidate ":")))
                             (switch-to-buffer (second items))
                             (goto-line (string-to-number (car items)))
                             (set-window-start (get-buffer-window anything-current-buffer) (point))
                             
                             (anything-persistent-highlight-point
                              (line-beginning-position)
                              (line-end-position)
                              (get-buffer (second items)))
                             )))
    ))

(defun anything-c-source-global-mark-ring-candidates ()
  (let* ((marks global-mark-ring)
         (lines (mapcar (lambda (pos)
                          (if (or (string-match "^ " (format "%s" (marker-buffer pos)))
                                  (null (marker-buffer pos)))
                              nil
                            (save-excursion
                              (set-buffer (marker-buffer pos))
                              (goto-char pos)
                              (beginning-of-line)
                              (let ((line  (car (split-string (thing-at-point 'line) "[\n\r]"))))
                                (when (string= "" line)
                                  (setq line  "<EMPTY LINE>"))
                                (format "%7d:%s:    %s" (line-number-at-pos) (marker-buffer pos) line)))))
                        marks)))
    (delq nil lines)))

