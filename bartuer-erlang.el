(require 'erlang-start)
(require 'distel)
(setq erlang-root-dir "/usr/local/otp")

(defun bartuer-erlang-load ()
  "for erlang language"
  (distel-setup)
  )

(provide 'bartuer-erlang)