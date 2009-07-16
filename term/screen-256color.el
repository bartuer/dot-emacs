(defun terminal-init-screen ()
  "Terminal initailization function for sceen ."
  ;; use the xterm color initailization code.
  (load "term/xterm")
  (xterm-register-default-colors)
  (tty-set-up-initial-frame-faces))