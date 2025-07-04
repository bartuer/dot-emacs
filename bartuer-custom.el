
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(Man-fontify-manpage-flag nil)
 '(PC-meta-flag nil)
 '(ac-auto-show-menu 0.4)
 '(after-save-hook '(executable-make-buffer-file-executable-if-script-p))
 '(ansi-color-faces-vector
   [default default default italic underline success warning error])
 '(ansi-color-names-vector
   ["#242424" "#e5786d" "#95e454" "#cae682" "#8ac6f2" "#333366" "#ccaa8f"
    "#f6f3e8"])
 '(auto-compression-mode t nil (jka-compr))
 '(auto-revert-verbose nil)
 '(before-save-hook '(copyright-update time-stamp))
 '(bookmark-default-file "~/etc/el/bookmark/.emacs.bmk")
 '(bookmark-save-flag 1)
 '(c-mode-common-hook
   '(ac-cc-mode-setup
     (lambda nil
       (dolist (k '(":" ">" ";" "<" "{" "}"))
         (define-key (symbol-value (make-local-variable 'yas-keymap))
                     k 'self-insert-command)))
     bartuer-c-load bartuer-c-common))
 '(calendar-latitude 40)
 '(calendar-longitude 116)
 '(case-fold-search t)
 '(case-replace t)
 '(clang-format-style "file")
 '(colon-double-space t)
 '(column-number-mode t)
 '(comint-completion-autolist t)
 '(comint-input-autoexpand t)
 '(company-backends
   '(company-emacs-eclim company-elisp company-css company-semantic
                         company-clang company-xcode company-ropemacs
                         (company-gtags company-etags
                                        company-dabbrev-code
                                        company-pysmell
                                        company-keywords)
                         company-oddmuse company-files company-dabbrev
                         company-nxml company-ispell company-abbrev))
 '(compilation-ask-about-save nil)
 '(compilation-auto-jump-to-first-error t)
 '(compilation-error-regexp-alist
   '(("^ *at \\(.*? (\\|\\)\\(.+.js\\):\\([0-9]+\\):\\([0-9]+\\))*" 2 3 4)
     ("^[^\0-@]+ \"\\([^\"\12]+\\)\", [^\0-@]+ \\([0-9]+\\)[-,:]" 1 2)
     ("^\\(.*\\):\\[\\([0-9]*\\),\\([0-9]*\\)\\]" 1 2 3)
     ("At \\(.*\\):\\([0-9]+\\) char:\\([0-9]+\\)" 1 2) absoft ada aix
     ant bash borland python-tracebacks-and-caml comma cucumber msft
     edg-1 edg-2 epc ftnchek iar ibm irix java jikes-file maven
     jikes-line gcc-include ruby-Test::Unit lcc makepp mips-1 mips-2
     msft omake oracle perl php rxp sparc-pascal-file
     sparc-pascal-line sparc-pascal-example sun sun-ada watcom 4bsd
     gcov-file gcov-header gcov-nomark gcov-called-line
     gcov-never-called perl--Pod::Checker perl--Test perl--Test2
     perl--Test::Harness weblint))
 '(csharp-mode-hook '(bartuer-csharp-load))
 '(current-language-environment "UTF-8")
 '(custom-enabled-themes '(wheatgrass))
 '(default-input-method "chinese-py-punct")
 '(describe-char-unidata-list
   '(name general-category canonical-combining-class bidi-class
          decomposition decimal-digit-value digit-value numeric-value
          mirrored old-name iso-10646-comment uppercase lowercase
          titlecase))
 '(desktop-path '("~/etc/el/session" "~" "."))
 '(dired-guess-shell-alist-user
   '(("\\.[0-9]$"
      (progn
        (require 'man)
        (if (Man-support-local-filenames) "man -l"
          "cat * | groff -man -T utf8 | ul")))
     ("\\.[0-9].gz$"
      (progn
        (require 'man)
        (if (Man-support-local-filenames) "man -l"
          "gunzip -qc * | groff -man -T utf8 | ul")))))
 '(dired-omit-files "^\\.#.*$\\|^#.*#$\\|^\\.$\\|^\\.DS_Store$\\|^\\.\\.$")
 '(django-test-setting "vote.tests.settings")
 '(docker-containers-inspect-arguments nil)
 '(docker-containers-rm-arguments '("-f" "-v"))
 '(docker-images-rmi-arguments '("-f"))
 '(eclim-use-yasnippet nil)
 '(edebug-trace t)
 '(emms-player-list '(emms-player-mplayer))
 '(emms-stream-default-action "play")
 '(enable-local-eval t)
 '(eol-mnemonic-dos "(d\\r\\n)")
 '(eol-mnemonic-mac "(m\\r)")
 '(everything-cmd
   "/home/bazhou/c/Program Files (x86)/Everything/Everything.exe")
 '(everything-use-ftp t)
 '(fast-wiki-minor-mode-string " wk")
 '(file-cache-filter-regexps
   '("~$" "\\.o$" "\\.exe$" "\\.a$" "\\.elc$" ",v$" "\\.output$" "\\.$"
     "#$" "\\.class$" "\\.DS_Store$" "\\.gif$" "\\.pdf$" "\\.png$"
     "\\.jpg$" "\\.gitignore$" "\\.#.*$"))
 '(fill-column 70)
 '(find-function-C-source-directory "~/local/src/emacs-current/src" t)
 '(find-grep-options "-vE \".svn|drw|svn-base|*.pyc\"")
 '(find-ls-option '("-exec ls -ld {} \\;" . "-ld"))
 '(flycheck-checkers
   '(ada-gnat asciidoc c/c++-clang c/c++-gcc c/c++-cppcheck cfengine
              chef-foodcritic coffee coffee-coffeelint coq css-csslint
              d-dmd elixir emacs-lisp emacs-lisp-checkdoc erlang
              eruby-erubis fortran-gfortran go-gofmt go-golint go-vet
              go-build go-test go-errcheck haml handlebars haskell-ghc
              haskell-hlint html-tidy javascript-jshint
              javascript-eslint javascript-gjslint json-jsonlint less
              lua perl perl-perlcritic php php-phpmd php-phpcs
              puppet-parser puppet-lint python-flake8 python-pylint
              python-pycompile r-lintr racket rpm-rpmlint rst
              rst-sphinx ruby-rubocop ruby-rubylint ruby ruby-jruby
              rust sass scala scala-scalastyle scss sh-bash
              sh-posix-dash sh-posix-bash sh-zsh sh-shellcheck slim
              tex-chktex tex-lacheck texinfo verilog-verilator
              xml-xmlstarlet xml-xmllint yaml-jsyaml yaml-ruby swift))
 '(flycheck-swift-sdk-path
   "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk")
 '(flymake-allowed-file-name-masks
   '(("\\.c\\'" flymake-simple-make-init) ("\\.m\\'" flymake-objc-init)
     ("Rakefile" flymake-ruby-init) ("\\.rb\\'" flymake-ruby-init)
     ("\\.js\\'" flymake-jslint-init) ("\\.xml\\'" flymake-xml-init)
     ("\\.plist\\'" flymake-xml-init)
     ("\\.html?\\'" flymake-jslint-init) ("\\.css" flymake-css-init)
     ("\\.cs\\'" flymake-simple-make-init)
     ("\\.cpp\\'" flymake-simple-make-init)
     ("\\.p[ml]\\'" flymake-perl-init)
     ("\\.php[345]?\\'" flymake-php-init)
     ("\\.h\\'" flymake-master-make-header-init flymake-master-cleanup)
     ("\\.java\\'" flymake-simple-make-java-init
      flymake-simple-java-cleanup)
     ("[0-9]+\\.tex\\'" flymake-master-tex-init flymake-master-cleanup)
     ("\\.tex\\'" flymake-simple-tex-init)
     ("\\.idl\\'" flymake-simple-make-init)))
 '(flymake-log-level -1)
 '(flymake-objc-compile-options '("-I." "-F../Frameworks" "-I../Classes"))
 '(flymake-proc-allowed-file-name-masks
   '(("\\.c\\'" flymake-simple-make-init) ("\\.m\\'" flymake-objc-init)
     ("Rakefile" flymake-ruby-init) ("\\.rb\\'" flymake-ruby-init)
     ("\\.js\\'" flymake-jslint-init) ("\\.xml\\'" flymake-xml-init)
     ("\\.plist\\'" flymake-xml-init)
     ("\\.html?\\'" flymake-jslint-init) ("\\.css" flymake-css-init)
     ("\\.cs\\'" flymake-simple-make-init)
     ("\\.cpp\\'" flymake-simple-make-init)
     ("\\.p[ml]\\'" flymake-perl-init)
     ("\\.php[345]?\\'" flymake-php-init)
     ("\\.h\\'" flymake-master-make-header-init flymake-master-cleanup)
     ("\\.java\\'" flymake-simple-make-java-init
      flymake-simple-java-cleanup)
     ("[0-9]+\\.tex\\'" flymake-master-tex-init flymake-master-cleanup)
     ("\\.tex\\'" flymake-simple-tex-init)
     ("\\.idl\\'" flymake-simple-make-init)))
 '(flyspell-use-meta-tab nil)
 '(gdb-debug-log-max 20)
 '(gdb-enable-debug t)
 '(gdb-find-source-frame t)
 '(gdb-many-windows t)
 '(gdb-max-frames 60)
 '(gdb-memory-repeat-count 64)
 '(gdb-speedbar-auto-raise t)
 '(gdb-use-separate-io-buffer t)
 '(ggtags-find-tag-hook '(reposition-window))
 '(ggtags-global-use-color nil)
 '(global-font-lock-mode t nil (font-lock))
 '(global-mark-ring-max 32)
 '(global-semantic-idle-scheduler-mode nil)
 '(grep-find-command
   (if (string= system-type "windows-nt")
       "findnix . -type f -a ! -name \"*.o\" -a ! -name \"*xcodeproject*\" -a ! -name \"node_modules\" -a ! -name \"private_modules\" -a ! -name \"*.pyc\" -a ! -name \"*.elc\" -a ! -name \"*.u.js\" -a ! -name \"*.g.js\" -a ! -name \"dev.package.js\" -a ! -name \"*_min.css\" -a ! -name \"*_img.css\" |grep -vE \"BROWSE|Makefile|CMakeFiles|TAGS|.svn|drw|.bzr|.git|svn-base|z.js|z_min.js\" |xargs  grep -niHE "
     "find . -type f  -a ! -name \"*.o\" -a ! -name \"*xcodeproject*\" -a ! -name \"node_modules\" -a ! -name \"private_modules\" -a ! -name \"*.pyc\" -a ! -name \"*.elc\" -a ! -name \"*.u.js\" -a ! -name \"*.g.js\" -a ! -name \"dev.package.js\" -a ! -name \"*_min.css\" -a ! -name \"*_img.css\" |grep -vE \"BROWSE|Makefile|CMakeFiles|TAGS|.svn|drw|.bzr|.git|svn-base|z.js|z_min.js\" |quote0|xargs -0 grep -niHE "))
 '(grep-highlight-matches t)
 '(gud-gdb-command-name
   (concat
    "gdb -i=mi -silent -x ~/etc/el/gdb/init.gdb /opt/conda/bin/python"))
 '(gud-pdb-command-name "python -m pdb")
 '(gud-rdebug-command-name
   "rdebug --emacs 3 ~/local/src/uki-tools/bin/uki run -- localhost:21119")
 '(gud-tooltip-echo-area t)
 '(hippie-expand-try-functions-list
   '(try-complete-file-name-partially try-complete-file-name
                                      try-expand-line
                                      try-expand-all-abbrevs
                                      try-expand-list
                                      try-complete-lisp-symbol-partially
                                      try-complete-lisp-symbol))
 '(hippie-expand-verbose t)
 '(html-mode-hook '(er/add-html-mode-expansions bartuer-sgml-load))
 '(htmlize-html-charset "utf-8")
 '(htmlize-hyperlink-style
   "\12      a {\12        color: inherit;\12        background-color: #000000;\12        font: inherit;\12        text-decoration: inherit;\12      }\12      a:hover {\12        text-decoration: underline;\12      }\12")
 '(ibuffer-elide-long-columns nil)
 '(ibuffer-saved-filter '(nil))
 '(ibuffer-saved-filter-groups
   '(("normal"
      ("emacs"
       (or (mode . Custom-mode) (mode . lisp-interaction-mode)
           (mode . emacs-lisp-mode)))
      ("console"
       (or (mode . inferior-octave-mode) (mode . calc-mode)
           (mode . debugger-mode) (mode . comint-mode)
           (mode . reb-mode) (mode . inferior-ess-mode)
           (mode . inf-ruby-mode) (mode . shell-mode)
           (mode . inferior-moz-mode)))
      ("result"
       (or (mode . anything-mode) (mode . ediff-meta-mode)
           (mode . ediff-mode) (mode . occur-mode)
           (mode . compilation-mode) (name . "^\\*pP")
           (mode . grep-mode) (mode . completion-list-mode)
           (mode . apropos-mode) (name . "rct-result")
           (name . "*rct-compilation*") (name . "^\\*rake")
           (mode . term-mode)))
      ("debugger"
       (or (name . "^*gud") (name . "^*edebug") (name . "^*locals")
           (name . "^*register") (name . "^*stack")
           (name . "^*breakpoints") (name . "^*input")
           (name . "^*disassembly") (name . "^*threads")
           (name . "^*memory") (name . "^*rdebug")))
      ("log" (or (name . "\\.log$") (name . "_log")))
      ("help"
       (or (name . "^readme") (name . "^ri") (mode . help-mode)
           (mode . Info-mode) (mode . Man-mode) (mode . woman-mode)
           (mode . ess-help-mode)))
      ("irc" (or (mode . rcirc-mode)))
      ("tags" (or (name . "^TAGS") (mode . tags-table-mode)))
      ("org"
       (or (name . "^\\*Org") (mode . calendar-mode) (mode . org-mode)))
      ("ver"
       (or (mode . vc-annotate-mode) (name . "^\\*VC")
           (mode . vc-mode) (name . "^\\*magit")))
      ("dir" (or (mode . dired-mode) (mode . archive-mode))))))
 '(ibuffer-saved-filters
   '(("irc" (or (mode . rcirc-mode)))
     ("console"
      ((or (mode . debugger-mode) (mode . slime-repl-mode)
           (mode . comint-mode) (mode . reb-mode)
           (mode . inferior-ess-mode) (mode . inf-ruby-mode)
           (mode . shell-mode) (mode . inferior-moz-mode))))
     ("tags" (or (name . "^TAGS") (mode . tags-table-mode)))
     ("emacs"
      (or (mode . Custom-mode) (mode . lisp-interaction-mode)
          (mode . emacs-lisp-mode)))
     ("result"
      (or (mode . anything-mode) (mode . ediff-meta-mode)
          (mode . ediff-mode) (mode . occur-mode)
          (mode . compilation-mode) (name . "^\\*pP")
          (mode . grep-mode) (mode . completion-list-mode)
          (mode . apropos-mode) (name . "rct-result")
          (name . "*rct-compilation*") (name . "^\\*rake")
          (mode . term-mode)))
     ("debugger"
      (or (name . "^*gud") (name . "^*edebug") (name . "^*locals")
          (name . "^*register") (name . "^*stack")
          (name . "^*breakpoints") (name . "^*input")
          (name . "^*disassembly") (name . "^*threads")
          (name . "^*memory") (name . "^*rdebug")))
     ("log" (or (name . "\\.log$") (name . "_log")))
     ("org"
      ((or (name . "^\\*Org") (mode . calendar-mode) (mode . org-mode))))
     ("ver"
      ((or (mode . vc-annotate-mode) (name . "^\\*VC")
           (mode . vc-mode) (name . "^\\*magit"))))
     ("help"
      (or (name . "^readme") (name . "^ri") (mode . help-mode)
          (mode . Info-mode) (mode . Man-mode) (mode . woman-mode)
          (mode . ess-help-mode)))
     ("dir" (or (mode . dired-mode) (mode . archive-mode)))))
 '(icicle-apropos-cycle-next-keys '([next]))
 '(ido-create-new-buffer 'always)
 '(ido-enable-flex-matching t)
 '(ido-max-prospects 96)
 '(ido-max-window-height 5)
 '(indent-tabs-mode nil)
 '(inferior-lisp-program
   (if (string= system-type "windows-nt")
       "C:/Program Files/Steel Bank Common Lisp/1.3.8/sbcl.exe"
     "/usr/local/bin/sbcl") t)
 '(isearch-resume-in-command-history t)
 '(ispell-complete-word-dict "~/etc/el/vendor/aspell/web2")
 '(ispell-dictionary "british")
 '(ispell-program-name "aspell")
 '(js2-allow-member-expr-as-function-name t)
 '(js2-allow-rhino-new-expr-initializer t)
 '(js2-basic-offset 4)
 '(js2-highlight-level 3)
 '(js2-mirror-mode nil t)
 '(js2-parse-minor-mode-string " Pa")
 '(kill-read-only-ok t)
 '(line-spacing 5)
 '(list-matching-lines-default-context-lines 0)
 '(load-path
   '("~/etc/el/ess/" "~/etc/el/tree-sitter" "~/etc/el/vendor/use-package"
     "~/etc/el/auto-install/markdown" "~/etc/el/vendor/tree-sitter"
     "~/etc/el/vendor/tsc" "~/etc/el/vendor/tree-sitter-langs"
     "~/etc/el/vendor/phi-search" "~/etc/el/vendor/expand-region"
     "~/etc/el/auto-install/async" "~/etc/el/auto-install/dash"
     "~/etc/el/auto-install/magit-popup"
     "~/etc/el/auto-install/tablist" "~/etc/el/vendor/docker"
     "~/etc/el/vendor/hn" "~/etc/el/vendor/multiple-cursors"
     "~/etc/el/vendor/tern" "~/etc/el/vendor/js2-mode"
     "~/etc/el/vendor/js2-refactor" "~/etc/el/s"
     "~/etc/el/vendor/dash" "~/etc/el/vendor/flycheck"
     "~/etc/el/vendor/helm" "~/etc/el/vendor/omnisharp"
     "~/etc/el/vendor/pkg-info" "~/etc/el/vendor/popup"
     "~/etc/el/vendor/auto-complete" "~/etc/el/vendor/csharp-mode"
     "~/etc/el/vendor/ggtags" "~/etc/el/vendor/web-beautify"
     "~/etc/el/vendor/epl" "~/etc/el/yasnippet" "~/etc/el/gdb"
     "~/etc/el/vendor/s" "~/etc/el/vendor/dash"
     "~/etc/el/vendor/swift-mode" "~/etc/el/vendor/fsharp-mode"
     "~/etc/el/vendor/lua-mode" "~/etc/el/vendor/nav"
     "~/etc/el/vendor/emmet" "~/etc/el/vendor/rinari/util/jump/"
     "~/etc/el/vendor/rinari/util/" "~/etc/el/vendor/rinari/"
     "~/etc/el/vendor/node_modules/lintnode" "~/etc/el"
     "~/etc/el/icicles" "~/etc/el" "~/etc/el/auto-install"
     "~/etc/el/ess" "~/etc/el/icicles" "~/etc/el/org"
     "~/etc/el/vendor/gist" "~/etc/el/vendor/magit"
     "~/etc/el/vendor/rcodetools" "~/etc/el/vendor/rhtml"
     "~/etc/el/vendor/textile-minor-mode/" "~/etc/el/vendor/yasnippet"
     "~etc/el/vendor/yaml-mode/trunk" "~/etc/el/vendor/irony-mode"
     "~/etc/el/vendor/erlang"
     "~/etc/el/vendor/erlang/share/distel/elisp"
     "~/etc/el/vendor/tuareg" "~/etc/el/vendor/matlab-emacs"
     "~/etc/el/vendor/eclim" "~/etc/el/vendor/slime"
     "~/etc/el/vendor/swank-js" "~/etc/el/vendor/company"
     "~/etc/el/vendor/auto-complete"
     "~/local/share/emacs/current/leim"
     "~/local/share/emacs/current/lisp"
     "~/local/share/emacs/current/lisp/calc"
     "~/local/share/emacs/current/lisp/vc"
     "~/local/share/emacs/current/lisp/cedet"
     "~/local/share/emacs/current/lisp/calendar"
     "~/local/share/emacs/current/lisp/emacs-lisp"
     "~/local/share/emacs/current/lisp/emulation"
     "~/local/share/emacs/current/lisp/erc"
     "~/local/share/emacs/current/lisp/eshell"
     "~/local/share/emacs/current/lisp/gnus"
     "~/local/share/emacs/current/lisp/international"
     "~/local/share/emacs/current/lisp/language"
     "~/local/share/emacs/current/lisp/mail"
     "~/local/share/emacs/current/lisp/mh-e"
     "~/local/share/emacs/current/lisp/net"
     "~/local/share/emacs/current/lisp/nxml"
     "~/local/share/emacs/current/lisp/nxml/char-name"
     "~/local/share/emacs/current/lisp/nxml/char-name/unicode"
     "~/local/share/emacs/current/lisp/obsolete"
     "~/local/share/emacs/current/lisp/org"
     "~/local/share/emacs/current/lisp/play"
     "~/local/share/emacs/current/lisp/progmodes"
     "~/local/share/emacs/current/lisp/textmodes"
     "~/local/share/emacs/current/lisp/toolbar"
     "~/local/share/emacs/current/lisp/url"
     "~/local/share/emacs/current/site-lisp"
     "~/local/share/emacs/current/site-lisp/emms"
     "~/local/share/emacs/site-lisp") t)
 '(lpr-command "~/scripts/pdfprint")
 '(mail-send-hook '(quote-encoded-subject))
 '(make-backup-files nil)
 '(markdown-command
   "pandoc -s --from=markdown --to=html5 --highlight-style=kate")
 '(markdown-enable-highlighting-syntax t)
 '(max-mini-window-height 0.7)
 '(mm-body-charset-encoding-alist
   '((utf-8 . 7bit) (iso-2022-jp-2 . 7bit) (utf-16 . base64)
     (utf-16be . base64) (utf-16le . base64)))
 '(mode-line-format
   '("%e" mode-line-front-space mode-line-mule-info mode-line-client
     mode-line-modified mode-line-remote
     mode-line-frame-identification mode-line-buffer-identification
     "   " mode-line-position (vc-mode vc-mode) "  " mode-line-modes
     mode-line-misc-info system-name mode-line-end-spaces))
 '(mode-require-final-newline nil)
 '(next-line-add-newlines nil)
 '(next-screen-context-lines 0)
 '(omnisharp-imenu-support t)
 '(omnisharp-server-executable-path
   "/Users/bartuer/local/src/OmniSharpServer/OmniSharp/bin/Debug/OmniSharp.exe")
 '(org-agenda-columns-add-appointments-to-effort-sum t)
 '(org-agenda-files '("~/org/note.org"))
 '(org-archive-save-context-info '(time file category todo itags olpath ltags))
 '(org-clock-idle-time 3000)
 '(org-columns-default-format
   "%40ITEM(Task) %15Effort(EFFORT){:} %SCHEDULED(SCHEDULE) %22DEADLINE(DEADLINE) %CLOCK(CLOCK)")
 '(org-completion-use-ido t)
 '(org-default-notes-file "~/icloud/org/note.org")
 '(org-file-apps
   '((auto-mode . emacs) ("\\.mm\\'" . default)
     ("\\.x?html?\\'" . default) ("\\.pdf\\'" . default)
     ("m4v" . "/usr/bin/qlmanage -p %s") ("png" . "qlmanage -p %s")
     ("mov" . "qlmanage -p %s")))
 '(org-hide-leading-stars t)
 '(org-odd-levels-only t)
 '(org-outline-path-complete-in-steps nil)
 '(org-refile-targets
   '(("~/local/src/baza/sbs.org" :tag . "research")
     ("~/local/src/baza/sbs.org" :tag . "design")
     ("~/local/src/baza/sbs.org" :tag . "checklist")
     ("~/local/src/baza/sbs.org" :tag . "bug")
     ("~/local/src/baza/sbs.org" :tag . "feature")
     ("~/local/src/baza/sbs.org" :tag . "tool")
     ("~/local/src/baza/sbs.org" :tag . "lib")
     ("~/local/src/baza/sbs.org" :tag . "deployment")
     ("~/local/src/baza/sbs.org" :tag . "beta")
     ("~/local/src/baza/sbs.org" :tag . "alpha")))
 '(org-tag-alist
   '(("bug" . 98) ("finding" . 102) ("data" . 100) ("push" . 112)
     ("summary" . 115) ("research" . 114) ("fix" . 120)
     ("meeting" . 109) ("trip" . 116) ("build" . 117) ("buy" . 36)
     ("baza" . 106) ("hack" . 104) ("feature" . 110)
     ("deployment" . 101)))
 '(org-todo-keyword-faces '(("ABORT" . "white")))
 '(org-todo-keywords '((sequence "TODO" "HALT" "ABORT" "DONE")))
 '(org-use-speed-commands t)
 '(package-selected-packages
   '(aidermacs auctex chess dap-mode go-guru go-mode json-snatcher
               latex-math-preview latex-preview-pane tree-sitter
               tree-sitter-langs typescript-mode))
 '(ps-lpr-command "lp")
 '(ps-multibyte-buffer 'bdf-font)
 '(push-minor-mode-string " Pu")
 '(rcirc-server-alist '(("irc.freenode.net" :channels ("#rcirc"))))
 '(rdebug-many-windows nil)
 '(rdebug-short-key-mode nil)
 '(reb-auto-match-limit 8000)
 '(reload-minor-mode-string " Reload")
 '(remember-annotation-functions '(org-remember-annotation))
 '(rst-level-face-base-color "")
 '(safe-local-eval-forms
   '((add-hook 'write-file-hooks 'time-stamp)
     (add-hook 'after-save-hook (lambda nil (org-export-as-html 3)))
     (lambda nil (org-export-as-html 3))))
 '(safe-local-variable-values
   '((save-as-html lambda nil (org-export-as-html 3))
     (write-contents-files lambda nil (org-export-as-html 3))
     (erlang-indent-level . 4) (erlang-indent-level . 2)
     (require-final-newline) (backup-inhibited . t)
     (ruby-compilation-executable . "ruby")
     (ruby-compilation-executable . "ruby1.8")
     (ruby-compilation-executable . "ruby1.9")
     (ruby-compilation-executable . "rbx")
     (ruby-compilation-executable . "jruby")
     (minor-mode . clearcase-dired) (TeX-command-default . "CJKLaTeX")
     (TeX-header-end . "%+ *[Ee]nd[ -]*[oO]f[ -]*[hH]eader")
     (TeX-trailer-start . "%+ *[Ss]tart[ -]*[oO]f[ -]*[tT]railer")
     (TeX-command-default . "CLaTeX") (TeX-master . t)))
 '(scroll-conservatively 10)
 '(search-whitespace-regexp "[ \11\12\15]+")
 '(semantic-mode nil)
 '(sgml-tag-alist
   '(("![" ("ignore" t) ("include" t)) ("!attlist") ("!doctype")
     ("!element") ("!entity")))
 '(show-paren-mode t)
 '(size-indication-mode t)
 '(smtpmail-auth-credentials "~/.authinfo")
 '(smtpmail-debug-info t)
 '(smtpmail-debug-verb t)
 '(smtpmail-local-domain "gmail.com")
 '(smtpmail-sendto-domain "gmail.com")
 '(smtpmail-smtp-server "smtp.gmail.com")
 '(smtpmail-smtp-service 587)
 '(smtpmail-starttls-credentials '(("smtp.gmail.com" 587 "  " "")))
 '(swift-indent-switch-case-offset 4)
 '(tool-bar-mode nil)
 '(tree-sitter-langs-grammar-dir "/root/.emacs.d/tree-sitter")
 '(tree-sitter-major-mode-language-alist
   '((actionscript-mode . actionscript) (ada-mode . ada)
     (agda-mode . agda) (agda2-mode . agda) (arduino-mode . arduino)
     (astro-mode . astro) (fish-mode . fish) (asm-mode . asm)
     (fasm-mode . asm) (masm-mode . asm) (nasm-mode . asm)
     (gas-mode . asm) (sh-mode . bash) (beancount-mode . beancount)
     (bibtex-mode . bibtex) (c-mode . c) (caml-mode . ocaml)
     (clojure-mode . clojure) (lisp-mode . commonlisp)
     (lisp-interaction-mode . commonlisp) (csharp-mode . c-sharp)
     (c++-mode . cpp) (cmake-mode . cmake) (d-mode . d)
     (dart-mode . dart) (dockerfile-mode . dockerfile)
     (css-ts-mode . css) (css-mode . css) (csv-mode . csv)
     (elm-mode . elm) (elixir-mode . elixir) (emacs-lisp-mode . elisp)
     (erlang-mode . erlang) (ess-r-mode . r) (fennel-mode . fennel)
     (f90-mode . fortran) (fortran-mode . fortran)
     (gdscript-mode . gdscript) (git-commit-mode . gitcommit)
     (git-rebase-mode . git-rebase)
     (gitattributes-mode . gitattributes) (gitignore-mode . gitignore)
     (gleam-mode . gleam) (glsl-mode . glsl) (go-mode . go)
     (groovy-mode . groovy) (jenkinsfile-mode . groovy)
     (haskell-mode . haskell) (haxe-mode . haxe) (hcl-mode . hcl)
     (terraform-mode . hcl) (heex-mode . heex) (hlsl-mode . hlsl)
     (html-mode . html) (markdown-mode . markdown) (mhtml-mode . html)
     (nix-mode . nix) (jai-mode . jai) (java-mode . java)
     (javascript-mode . javascript) (js-mode . javascript)
     (js2-mode . javascript) (js-ts-mode . javascript)
     (js3-mode . javascript) (json-ts-mode . json) (json-mode . json)
     (jsonc-mode . json) (jsonnet-mode . jsonnet) (julia-mode . julia)
     (kotlin-mode . kotlin) (latex-mode . latex) (LaTeX-mode . latex)
     (llvm-mode . llvm) (llvm-mir-mode . llvm-mir) (lua-mode . lua)
     (magik-mode . magik) (makefile-mode . make)
     (makefile-automake-mode . make) (makefile-gmake-mode . make)
     (makefile-makepp-mode . make) (makefile-bsdmake-mode . make)
     (makefile-imake-mode . make) (matlab-mode . matlab)
     (mermaid-mode . mermaid) (meson-mode . meson)
     (ninja-mode . ninja) (noir-mode . noir) (ocaml-mode . ocaml)
     (org-mode . org) (pascal-mode . pascal) (perl-mode . perl)
     (cperl-mode . perl) (php-mode . php) (qss-mode . css)
     (prisma-mode . prisma) (python-ts-mode . python)
     (python-mode . python) (pygn-mode . pgn) (racket-mode . racket)
     (rjsx-mode . javascript) (rst-mode . rst) (ruby-mode . ruby)
     (rust-ts-mode . rust) (rust-mode . rust) (rustic-mode . rust)
     (scala-mode . scala) (scheme-mode . scheme)
     (solidity-mode . solidity) (smithy-mode . smithy)
     (sql-mode . sql) (svelte-mode . svelte) (swift-mode . swift)
     (tablegen-mode . tablegen) (toml-mode . toml)
     (conf-toml-mode . toml) (tcl-mode . tcl) (tuareg-mode . ocaml)
     (twig-mode . twig) (typescript-mode . typescript)
     (tsx-ts-mode . tsx) (typescript-tsx-mode . tsx)
     (typescript-ts-mode . typescript) (typst-mode . typst)
     (verilog-mode . verilog) (vhdl-mode . vhdl) (nxml-mode . xml)
     (yaml-ts-mode . yaml) (yaml-mode . yaml) (k8s-mode . yaml)
     (zig-mode . zig)))
 '(user-mail-address "bartuer@gmail.com")
 '(vc-handled-backends '(Git RCS CVS SVN SCCS Bzr Hg Arch))
 '(view-read-only t))
 
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:inherit nil :stipple nil :background "black" :foreground "wheat" :inverse-video nil :box nil :strike-through nil :overline nil :underline nil :slant normal :weight normal :height 200 :width normal :foundry "nil" :family "Monaco"))))
 '(anything-visible-mark ((t (:background "green1" :foreground "black"))))
 '(button ((((supports :underline t)) (:foreground "cyan" :underline t))))
 '(comint-highlight-prompt ((t (:foreground "cyan"))))
 '(css-property ((t (:inherit font-lock-keyword-face))))
 '(cursor ((t (:background "peach puff" :foreground "black"))))
 '(custom-comment-tag ((((class color) (background light)) (:foreground "cyan"))))
 '(diff-added ((t (:foreground "green"))))
 '(diff-changed ((t (:foreground "red" :slant italic :weight bold))))
 '(diff-file-header ((t (:background "blue" :weight bold))))
 '(diff-function ((t (:foreground "magenta"))))
 '(diff-header ((t (:background "blue"))))
 '(ediff-current-diff-A ((t (:background "#ffdddd" :foreground "black"))))
 '(ediff-current-diff-B ((t (:background "#ddffdd" :foreground "black"))))
 '(ediff-current-diff-C ((t (:background "#ffffaa" :foreground "black"))))
 '(ediff-even-diff-Ancestor ((t (:background "Grey" :foreground "black"))))
 '(ediff-even-diff-B ((t (:background "Grey" :foreground "black"))))
 '(ediff-fine-diff-A ((t (:background "#ffbbbb" :foreground "black"))))
 '(ediff-fine-diff-B ((t (:background "#aaffaa" :foreground "black"))))
 '(ediff-fine-diff-C ((t (:background "lightblue" :foreground "black"))))
 '(ediff-odd-diff-A ((t (:background "Grey" :foreground "black"))))
 '(ediff-odd-diff-C ((t (:background "Grey" :foreground "black"))))
 '(erb-face ((((class color) (min-colors 8)) nil)))
 '(flymake-errline ((((class color)) (:foreground "red"))) t)
 '(flymake-pos ((((class color)) (:background "yellow" :foreground "red"))))
 '(flymake-warnline ((t (:foreground "pink"))) t)
 '(flyspell-duplicate ((t (:underline t))))
 '(flyspell-duplicate-face ((t (:underline t))) t)
 '(flyspell-incorrect ((t (:underline "red"))))
 '(flyspell-incorrect-face ((t (:underline "red"))) t)
 '(font-lock-comment-face ((t (:foreground "green"))))
 '(font-lock-constant-face ((t (:foreground "magenta"))))
 '(font-lock-function-name-face ((t (:foreground "cyan"))))
 '(font-lock-keyword-face ((t (:foreground "green"))))
 '(font-lock-string-face ((t (:foreground "cyan"))))
 '(font-lock-variable-name-face ((((class color) (min-colors 8)) (:foreground "white" :weight light))))
 '(icicle-candidate-part ((((background dark)) (:foreground "red"))))
 '(icicle-complete-input ((((background dark)) (:foreground "green"))))
 '(icicle-current-candidate-highlight ((((background dark)) (:foreground "green"))))
 '(icicle-search-context-level-4 ((((background dark)) nil)))
 '(icicle-search-context-level-8 ((((background dark)) nil)))
 '(icicle-special-candidate ((((background dark)) nil)))
 '(js2-error ((t (:foreground "color-182"))))
 '(js2-instance-member-face ((t (:foreground "magenta"))))
 '(js2-jsdoc-html-tag-delimiter-face ((((class color) (min-colors 8) (background dark)) (:foreground "yellow"))))
 '(link ((((class color) (background light)) (:foreground "cyan" :underline t))))
 '(magit-diff-add ((t (:foreground "green"))))
 '(magit-diff-file-header ((t (:foreground "magenta"))))
 '(magit-diff-hunk-header ((t (:foreground "white" :slant italic))))
 '(magit-item-highlight ((nil (:foreground "green"))))
 '(magit-log-tag-label ((((class color) (background dark)) (:background "blue"))))
 '(magit-section-title ((t (:inherit magit-header :foreground "red" :weight bold))))
 '(minibuffer-prompt ((t (:foreground "Yellow"))))
 '(mode-line ((t (:inverse-video t))))
 '(mode-line-buffer-id ((t (:background "yellow" :foreground "blue" :weight bold))))
 '(mode-line-inactive ((default (:inherit mode-line)) (nil (:inverse-video nil))))
 '(org-agenda-structure ((t (:foreground "cyan" :weight bold))))
 '(org-column ((t (:background "black" :foreground "cyan" :strike-through nil :underline nil :slant normal :weight normal :height 1 :family "default"))))
 '(org-drawer ((t (:foreground "cyan" :weight bold))))
 '(org-level-1 ((t (:foreground "cyan"))))
 '(org-level-7 ((t (:foreground "cyan"))))
 '(org-link ((((class color) (background dark)) (:foreground "cyan" :underline t))))
 '(org-table ((t (:foreground "Orange"))))
 '(org-target ((((class color) (background dark)) (:foreground "cyan" :underline t))))
 '(reb-match-1 ((((class color) (background dark)) (:background "blue"))))
 '(region ((t (:background "cornflower blue"))))
 '(smerge-markers ((t (:background "grey85" :foreground "black"))))
 '(speedbar-button-face ((((class color) (background dark)) (:foreground "cyan" :underline t))))
 '(speedbar-selected-face ((t (:foreground "brightmagenta" :underline t))))
 '(tool-bar ((t (:foreground "brightwhite" :box (:line-width 1 :style released-button)))))
 '(which-func ((((background dark)) (:background "yellow" :foreground "blue"))))
 '(yas/field-highlight-face ((t (:background "blue"))))
 '(yas/mirror-highlight-face ((t (:background "blue")))))
