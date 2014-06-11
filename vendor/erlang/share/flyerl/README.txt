----
INTRO

Advanced flymake + dialyzer mode for Erlang, by bkil.hu

----
PRECONDITIONS:

You need:
* Erlang (R12+, once tested on R12B3/B5, now: R13B01)
 * +debug_info build recommended, otherwise you can't build
   the complete OTP PLT yourself
* Emacs 
 * flymake-mode
 * erlang-mode is recommended
* RefactorErl is recommended (also has neat semantics-aware queries!)
  you can get it from here: http://plc.inf.elte.hu/erlang/dl/

----
INSTALLATION:

To the top of your ~/.emacs file, add the following lines:

 (require 'flymake)
 (defun flymake-erlang-init ()
   (let* ((temp-file (flymake-init-create-temp-buffer-copy
              'flymake-create-temp-inplace))
      (local-file (file-relative-name temp-file
         (file-name-directory buffer-file-name))))
     (list "/FULL_PATH_TO/check_erlang.erl" (list local-file))))
 (add-to-list 'flymake-allowed-file-name-masks '("\\.erl\\'" flymake-erlang-init))
 (setq flymake-log-level 3)


Optionally add:

 (add-hook 'erlang-mode-hook '(lambda () (flymake-mode t)))

----
USAGE:

When running Emacs and having loaded an Erlang file, invoke:
 META-x flymake-mode

----
CONTACT:

Use the project mailing list.
