(defun bartuer-ocaml-load ()
  "mode hooks for ocaml"
  (setq tuareg-lazy-= t)
					; indent `=' like a standard keyword
  (setq tuareg-lazy-paren t)
					; indent [({ like standard keywords
  (setq tuareg-in-indent 0)
					; no indentation after `in' keywords
  (auto-fill-mode 1)
					; turn on auto-fill minor mode
  (if (featurep 'sym-lock)   ; Sym-Lock customization only
      (setq sym-lock-mouse-face-enabled nil))

)