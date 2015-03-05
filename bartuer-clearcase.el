(defun bartuer-clearcase-load ()
  "for load clearcase"
  (interactive)
  (if (require 'clearcase nil t)
      (progn
        (let ((map clearcase-prefix-map))
          (define-key map "b" 'clearcase-gui-vtree-browser-current-buffer)
          (define-key map "p" 'clearcase-gui-diff-pred-current-buffer)
          (define-key map "=" 'clearcase-gui-diff-branch-base-current-buffer)
          (define-key map "n" 'clearcase-gui-diff-named-version-current-buffer)
          (define-key map "P" 'clearcase-ediff-pred-current-buffer)
          (define-key map "+" 'clearcase-ediff-branch-base-current-buffer)
          (define-key map "N" 'clearcase-ediff-named-version-current-buffer))
        (let ((dmap clearcase-dired-prefix-map))
          (define-key dmap "b" 'clearcase-gui-vtree-browser-dired-file)
          (define-key dmap "p" 'clearcase-gui-diff-pred-dired-file)
          (define-key dmap "=" 'clearcase-gui-diff-branch-base-dired-file)
          (define-key dmap "n" 'clearcase-gui-diff-named-version-dired-file)
          (define-key dmap "P" 'clearcase-ediff-pred-dired-file)
          (define-key dmap "+" 'clearcase-ediff-branch-base-dired-file)
          (define-key dmap "N" 'clearcase-ediff-named-version-dired-file)))))

;; Lack language describle how to manipulate branch, include list all
;; files and directories belong the branch, query their status, diff
;; their code change, show their merge lines, and merge them with
;; another branch.  Through config spec, how to create branches
;; described well, by VC mode, all checkin and checkout staff done
;; well, but for all above things, need first get the file set (the
;; branch), like many operation in UNIX need first get the file list
;; by find.  So the thumb important thing is a find-dired like
;; feature, using clearcase find, findmerge, lscheckout replace the
;; find(1) seems a good start point.  User will get a derived dired
;; buffer via invoke such tools in background, and the buffer is a
;; branch oriented one, he mark the subset files he want to operate
;; on, and invoke lsvtree, diff and merge by only one key stroke.
;; Many functions have wrote down in clearcase.el, there are two
;; key-map for clearcase, one for current buffer and another for dired
;; buffer, the only thing I need do is adding filter to dired buffer
;; generation.

;; A little words about find(1) design, the bad thing about it is the
;; conflict with shell.  xargs is more clean way to do things find
;; want to do by -exec argument, finally you get things like:  find
;; . -exec -l '{}' \; totally anti intuit.  And more, clearcase find
;; tools inhered both find(1) great merit and such sucks attribute,
;; the bad design should be throw away early but indeed carry on for
;; ever, one generation by another.  Normally a version control system
;; need it's own filesystem or database, some time a filesystem is
;; implement as a database, thus user need a language to query the
;; database, for clearcase there is a query language, for general
;; filesystem, this is the find syntax, indeed the clearcase find is a
;; interface let user using the query language.  But clearcasel.el
;; lack the find or query language ability, what I really want is a
;; vc-dired-mode display the clearcase special attribute of version
;; files, and a utils like find-dired let user using the clearcase
;; query language to operation on the file set he can express with
;; such language. 

;; the major three design flaw of clearcase is: first, it lacks clear
;; language manipulate branch. second, it's document format not follow
;; standard, so many utils can quick access and navigate in document
;; sections can not apply to clearcase manpage. third, because of the
;; first flaw, it is a bit hard for tools developer to add feature
;; that issue batch action on branch easily, as seen in clearcase.el.


