;;; Package --- summary
;;
;; A javascript evaluating service
;;
;;; Commentary:
;;
;; Installation:
;;
;; Put this in your load-path, then add the following to your .emacs.
;; You substitude espresso-mode-hook for javascript-mode-hook if you
;; use espresso.
;;
;;     (require 'swanknode)
;;
;; Run M-x swanknode-start once to start the server before invoking flymake.

;;; Code:
(defun swanknode-start ()
  "Start the swanknode server."
  (interactive)
  (start-process "swanknode-server" "*swanknode*" "node" (concat (file-name-directory (or load-file-name buffer-file-name)) "swank.js")
                 ))

(provide 'swanknode)
;;; swanknode.el ends here