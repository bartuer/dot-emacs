

(defun bartuer-erlang-load ()
  "for erlang language"
  (require 'erlang-start nil t)
  (require 'distel nil t)
  (distel-setup)
  (setq erlang-root-dir "/usr/local/otp")
  (setq erlang-skel nil)
  )

(provide 'bartuer-erlang)