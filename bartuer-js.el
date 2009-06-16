(defun bartuer-js-load ()
  "for javascript language
"
  (require 'flyspell nil t)
  (when (fboundp 'flyspell-prog-mode)
    (flyspell-prog-mode))
  (flymake-mode t)
  (moz-minor-mode t)
  )

(defvar js-process nil)

(defun connect-jsh ()
  "setup the connection to jsh"
  (interactive)
  (setq js-process
        (make-network-process :name "io" :host "192.168.1.2" :service "8889")))
  
(defun send-expression-jsh (expression)
  "prompt for a expression, then send it to remote inner server in jsh
\\[send-expression-jsh]"
  (interactive "sEval in jsh: ")
  (process-send-string js-process (concat expression "\n")))


(defun send-fuction-jsh ()
  "send current function to remote inner server in jsh
\\[send-fuction-jsh]"
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
    (process-send-region js-process pos_begin_def pos_end_def)
    (process-send-string js-process "\n")))

(defun send-region-jsh (start end)
  "send the region to remote inner server in jsh
\\[send-region-jsh]"
  (interactive "r")
  (process-send-region js-process start end)
  (process-send-string js-process "\n"))

(defun send-buffer-jsh ()
  "send the current buffer to remote inner server in jsh
\\[send-buffer-jsh]"
  (interactive)
  (process-send-region js-process (point-min) (point-max))
  (process-send-string js-process "\n"))

