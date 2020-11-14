(defvar js-process nil)

(defun bartuer-jsh ()
  (make-network-process :name "io" :buffer nil :host "192.168.1.2" :service "8889" ))

(defvar rhino-navigator-env "~/etc/el/js/env.js")
(defun rhino ()
  (unless (setq rhino-process (get-buffer-process "*rhino*"))
    (progn
      (setq rhino-process (get-buffer-process (make-comint "rhino"  "rhino")))
      (process-send-string rhino-process (concat "load('" (expand-file-name rhino-navigator-env) "');\n")))
    )
  rhino-process)


(defun MozRepl ()
  (setq mozrepel-jsh-process (inferior-moz-process)))

(defun iv8 ()
  (unless (setq v8-process (get-buffer-process "*iv8*"))
    (setq v8-process (get-buffer-process (make-comint "iv8" "v8_evaluator"))))
  v8-process)

(defun woap ()
  (interactive)
  (let ((current-char (following-char)))
    (when (and (<= 48 current-char)
               (>= 57 current-char))
      (let  ((id (clean-thing-at-point)))
        (message (concat "inspect #" id "#\n"))
        (process-send-string (get-buffer-process (current-buffer))
                             (concat "dir #" id "#" "\n"))
        (save-excursion
          (search-backward "dbg"))
          (recenter-top-bottom 14)
        ))
    )
  )

(defun chromium ()
  (unless (setq d8r-process (get-buffer-process "*chromium**"))
    (progn
      (make-comint "chromium" "d8r")
      (setq d8r-process (get-buffer-process "*chromium*"))
      (with-current-buffer "*chromium*"
        (add-hook 'post-command-hook 'woap nil t)
        )))
  d8r-process)

(defun node-d8 ()
  (interactive)
  (unless (string-equal  (shell-command-to-string "p 5959") "yes\n")
    (progn
      (make-comint "node.eval:4242.debug:5959.console" "noded")
      (setq node-dev-process (get-buffer-process "*node.eval:4242.debug:5959.console*"))
      )
    )
  (unless (setq node-d8r-process (get-buffer-process "*node.d8r*"))
    (progn
      (make-comint "node.d8r" "node.d8")
      (setq node-d8r-process (get-buffer-process "*node.d8r*"))
      (with-current-buffer "*node.d8r*"
        (add-hook 'post-command-hook 'woap nil t)
        )))
  (message "%s" (concat "rename scratch\n" "remove copyright\n" "check require\n" "eval expression\n" "insert debugger;"))
  node-d8r-process)

(defun squirrelfish ()
  (unless (setq squirrelfish-process (get-buffer-process "*squirrelfish*"))
    (setq squirrelfish-process (get-buffer-process (make-comint "squirrelfish" "squirrelfish"))))
  squirrelfish-process)

(defun phantomjs ()
  (unless (setq phantomjs-process (get-buffer-process "*phantomjs*"))
    (setq phantomjs-process (get-buffer-process (make-comint "phantomjs" "phantomjs"))))
  phantomjs-process)

(defun spidermonkey ()
  (unless (setq spidermonkey-process (get-buffer-process "*spidermonkey*"))
    (setq spidermonkey-process (get-buffer-process (make-comint "spidermonkey" "spidermonkey-nanojit"))))
  spidermonkey-process)

(defun slime ()
  (interactive)
  (let ((js-buffer (current-buffer)))
    (if (slime-current-connection)
        (progn
          (pop-to-buffer "*slime-repl JS*" t)
          (pop-to-buffer js-buffer t)
          )
      (progn
        (slime-connect "localhost" 4005 nil t)
        (with-current-buffer js-buffer
          (slime-js-minor-mode 1)
          (pop-to-buffer js-buffer t)
          )
        ))
    )
)

(defun connect-jsh ()
  "setup the connection to jsh"
  (interactive)
  (let* ((jsh (ido-completing-read "js shell to connect:" 
                                   (list  "slime" "phantomjs"  "rhino" "spidermonkey" ) nil t))
         (js-buffer (current-buffer)))

    (if (equal jsh "slime")
        (slime)
      (progn
        (setq js-process (apply (intern jsh) nil))
        (if (string-equal jsh "node-d8")
            (progn
              (pop-to-buffer "*node.eval:4242.debug:5959.console*")
              (pop-to-buffer "*node.d8r*"))
          (pop-to-buffer (concat "*" jsh "*")))
        )
      )
))

(defun d8r-head ()
  (when (string-equal (process-name js-process) "d8r")
      (process-send-string js-process "pp ")))

(defun send-expression-jsh (expression)
  "prompt for a expression, then send it to jsh
\\[send-expression-jsh]"
  (interactive "sEval in jsh: ")
  (d8r-head)
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

    (d8r-head)
    (process-send-region js-process pos_begin_def pos_end_def)
    (process-send-string js-process "\n")))

(defun send-region-jsh (start end)
  "send the region to jsh
\\[send-region-jsh]"
  (interactive "r")
  (d8r-head)
  (process-send-string js-process
                       (replace-regexp-in-string
                        "\n" " "
                        (buffer-substring-no-properties start end)))
  (process-send-string js-process "\n")
  (when (region-active-p)
    (deactivate-mark))
)

(defun send-buffer-jsh ()
  "send the current buffer to jsh
\\[send-buffer-jsh]"
  (interactive)
  (when (string-equal (process-name js-process) "d8r")
      (process-send-string js-process "p "))
  (d8r-head)
  (process-send-region js-process (point-min) (point-max))
  (process-send-string js-process "\n"))

(provide 'bartuer-js-inf)