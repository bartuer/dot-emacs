(defun rst-imenu ()
  "make the rst toc into a imenu-index-alist"
  (mapcar (lambda (item)
            (cons (car item) (cadr item))) 
          (mapcan (lambda (item)
                    (if (stringp (car item))
                        (list item)
                      item))
                  (mapcan (lambda (item)
                            item)
                          (cdr
                           (rst-section-tree
                            (rst-find-all-decorations)))))))

(defun bartuer-rst-load ()
  "mode hooks for rst"
  (set (make-local-variable 'imenu-create-index-function) 'rst-imenu))


