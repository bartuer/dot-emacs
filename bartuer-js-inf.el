(defvar js-process nil)

(defun bartuer-jsh
  (make-network-process :name "io" :host "192.168.1.2" :service "8889"))

(defvar rhino-navigator-env "~/etc/el/js/env.js")
(defun rhino ()
  (unless (setq rhino-process (get-buffer-process "*rhino*"))
    (progn
      (setq rhino-process (make-comint "rhino"  "rhino"))
      (process-send-string rhino-process (concat "load('" (expand-file-name rhino-navigator-env) "');\n")))
    )
  rhino-process)

(defun MozRepl ()
  (setq mozrepel-jsh-process (inferior-moz-process)))

(defun v8 ()
  (unless (setq v8-process (get-buffer-process "*v8*"))
    (setq v8-process (make-comint "v8" "v8_shell")))
  v8-process)

(defun squirrelfish ()
  (unless (setq squirrelfish-process (get-buffer-process "*squirrelfish*"))
    (setq squirrelfish-process (make-comint "squirrelfish" "squirrelfish")))
  squirrelfish-process)
    
(defun spidermonkey ()
  (unless (setq spidermonkey-process (get-buffer-process "*spidermonkey*"))
    (setq spidermonkey-process (make-comint "spidermonkey" "spidermonkey-nanojit")))
  spidermonkey-process)

(defun connect-jsh ()
  "setup the connection to jsh"
  (interactive)
  (let* ((jsh (ido-completing-read "js shell to connect:" 
                                   (list  "rhino" "MozRepl" "squirrelfish" "spidermonkey" "v8") nil t)))
    (setq js-process (apply (intern jsh) nil))
    (pop-to-buffer (concat "*" jsh "*"))
    ))
  
(defun send-expression-jsh (expression)
  "prompt for a expression, then send it to jsh
\\[send-expression-jsh]"
  (interactive "sEval in jsh: ")
  (process-send-string js-process (concat expression "\n")))


(defun send-function-jsh ()
  "send current function to jsh
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
  "send the region to jsh
\\[send-region-jsh]"
  (interactive "r")
  (process-send-region js-process start end)
  (process-send-string js-process "\n"))

(defun send-buffer-jsh ()
  "send the current buffer to jsh
\\[send-buffer-jsh]"
  (interactive)
  (process-send-region js-process (point-min) (point-max))
  (process-send-string js-process "\n"))

(provide 'bartuer-js-inf)