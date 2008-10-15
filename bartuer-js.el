(defun bartuer-js-load ()
  "for javascript language
"
  (define-key js2-mode-map "\C-x\C-e" 'send-expression-jsh)
  (define-key js2-mode-map "\C-\M-x" 'send-file-jsh)
  (define-key js2-mode-map "\C-j" 'send-fuction-jsh)
  (define-key js2-mode-map "\C-c\C-c" 'send-region-jsh))

(defvar js-process nil)

(defun connect-jsh ()
  "setup the connection to jsh"
  (interactive)
  (setq js-process
        (make-network-process :name "io" :host "127.0.0.1" :service "8889")))
  
(defun send-expression-jsh (expression)
  "prompt for a expression, then send it to remote inner server in jsh"
  (interactive "sEval in jsh: ")
  (process-send-string js-process (concat expression "\n")))


(defun send-fuction-jsh ()
  "send current function to remote inner server in jsh"
  (interactive)
  (let ((parent (js2-node-parent-script-or-fn (js2-node-at-point)))
        pos sib)
    (cond
     ((and (js2-function-node-p parent)
           (not (eq (point) (setq pos_begin_def (js2-node-abs-pos parent)))))
      )    
     (t
      (js2-mode-backward-sibling)))
    (if (not (js2-function-node-p parent))
        (js2-mode-forward-sibling)
      (setq pos_end_def (+ 1 (+ (js2-node-abs-pos parent)
                         (js2-node-len parent)))))
    (process-send-region js-process pos_begin_def pos_end_def)))

(defun send-region-jsh (start end)
  "send the region to remote inner server in jsh"
  (interactive "r")
  (process-send-region js-process start end))

(defun send-buffer-jsh ()
  "send the current buffer to remote inner server in jsh"
  (interactive)
  (process-send-region js-process (point-min) (point-max))
  )


