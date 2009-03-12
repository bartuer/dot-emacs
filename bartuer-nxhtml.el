(defun bartuer-nxhtml-load
  "mark language mode "
  (interactive)
  (load "~/etc/el/vendor/nxhtml/autostart.el") ;only load once

  (setq
   nxhtml-global-minor-mode t
   mumamo-chunk-coloring 'submode-colored
   nxhtml-skip-welcome t
   indent-region-mode t
   rng-nxml-auto-validate-flag nil
   nxml-degraded t))
