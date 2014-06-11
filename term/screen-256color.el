(defun terminal-init-screen ()
  "Terminal initailization function for screen ."
  ;; use the xterm color initailization code.
  (load "term/xterm")
  (xterm-register-default-colors)
  (tty-set-up-initial-frame-faces))