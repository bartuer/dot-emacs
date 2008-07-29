(defun bartuer-general-todo-list ()
  "list bugs will be fixed,or wishes will be done in bartuer's
dot emacs files, \\[bartuer-general-todo-list], "
  (interactive)
    (with-current-buffer
      (get-buffer-create "BARTUER REMARK")
    (if (buffer-size)
        (erase-buffer))
    (insert "TODO LIST:

        Bugs:
                Ispell-complete-word do not work.  ;Done, help-char t
                Fix prefix binding help do not work.  ;Done, help-char t <f1>
                Do not delete window, when there is only one window.  ;Done
                Turn off the debug?     ;Done
                Emacs-lisp-mode hook cann't load before dot emacs.  ;Done
                debug-on-error-ignore is ugly, do not list all in dot file ;Done
                Some time ibuffer not work, restart it first ;Maybe because of compile warning
                Why dot file is reloaded?

        Feature:

                Need a git module?(modify, C-u C-x v v, checkin,
                switch branch )

                M-* should reserved for tag ;Done
                should have one place for all key define? ;No
                need learn more about map define ;Done
                merge icicle completion in minibuffer completion. ;Done
                customize inactive mode-line ;Done
                Unbind M--, it is useful for quick change the Capital.  ;Done
                Should try the apropos apropos, many...
                there are totally 25 types of input method of Chinese, ;them 
                so be worthy to try ;Done 
                try mark ring           ;Done
                a search dict or eval expression when moving is fine.
                Try the outline minor mode
                try binary-overwrite-mode
                Compare fly spell and spell completion
                dict utility
                Abbrev function
                Create possible completion list.
                Tags function
                What is follow mode?    ;Done
                Major mode structure expand.
                Highlight facilities
                Define extension keyboard bindings.
                How about let tips buffer using help mode?
                Finish design style description.
                Let the i,j keys to be more effective
                Practice fine movement
                Plan to learn elisp
                Plan to learn emacs manual
                Plan to learn c minor mode
                Plan to learn Autotype facilities
                How about automatic highlight the current symbol
                Remove M-i, because it is tab-to-tab-stop ;Done
                Should bind M-k to kill-sentence, the default ;Done
                The content of this should be edited on fly? ;No
                Prefix map of dot docs.  ;No
                Can I resize the lossage? ;Done
                Explore Emacs <help> <help> ;Done
                Compile dot emacs automaticlly.  ;Done
                Self document dot emacs.  ;Done
                Add tolerant bindings to kill-region.  ;Done
                Bind <CR> to comment-indent-new-line.  ;Done
                Register can remember the windows setting? ;Done
                Add tips list.           ;Done
                Customize emacs src dir.  ;Done
                Bind C-j to eval-last-sexp.  ;Done
                Echo area is not high enough , need new buffer.  ;Done
                Add find-function-at-point binding.  ;No
                Add kill-whole-* functions.  ;Done
                Grep options            ;Done
                Add Select whole-*      ;No
                Create dwim compile & eval binding.  ;No

TIPS:
        M-( can insert parentheses, M-) can just like C-M-e and C-m,
        these command is very convenient for write lisp.

        in isearch C-x C-h can query all meta keys

        in isearch mode,type C-h C-h to query Isearch-mode-map

        in isearch you can enter a tiny edit mode, you can toggle case,
        regexp, direct, increment, word on the fly, you can toggle input
        method, and you can switch to other search relate task without
        quit the search first, you can query-replace, you can
        highlight, you can list matches.

                C-\\             isearch-toggle-input-method
                C-^             isearch-toggle-specified-input-method

                C-M-r           isearch-repeat-backward
                C-M-s           isearch-repeat-forward
                M-r             isearch-toggle-regexp
                M-c             isearch-toggle-case-fold

                DEL             isearch-delete-char
                C-M-w           isearch-del-char
                M-e             isearch-edit-string
                M-n             isearch-ring-advance
                M-p             isearch-ring-retreat
                M-TAB           isearch-complete
                C-y             isearch-yank-line
                M-y             isearch-yank-kill
                C-M-y           isearch-yank-char
                C-w             isearch-yank-word

                M-s o           isearch-occur
                M-s h r         isearch-highlight-regexp
                M-%             isearch-query-replace
                C-M-%           isearch-query-replace-regexp

        regular expression in emacs:

                *, +, ?, *?, +?, ?? only match the smallest possible
                preceding expression.

                when a special char has no special meaning, do not
                quote it, for example, it is wrong [\\-], for '-' has
                no meaning when it is the first char in the [] set,
                compare with '-' in 0-9.

                \\(...\\) has two meaning, one is for subgroup,
                and another is for refer later, but if you
                combine two regular expression, the digit used
                to refer the subgroup will be messed up, to
                avoid this, you can use the shy subgroup, like
                this, \\(?:...\\)
                
                M-x describe-categories, for how to search all char which
                is not a ASCII char? \\Ca

                M-x describe-syntax, for how to search all comments?

                enter regular expression in emacs, can not using the
                \\n and the \\t, using the C-q prefix.

        some time you want to programing when you do replace, for
        example, how to add a special label for all lines in this
        buffer? for this line it should be xxx buffer?..., the xxx is
        the number of lines which is not a blank line, you can finish
        it with the cl and sed, M-x replace-regexp,

        replace
                ^.*\\_>
        with  
                \\,(format \"% 5d^I^I%s\" \\# \\&)
                
        variant tab-width set how when you M-i

        the code system indicator in mode line is
        keyboard.terminal.buffer-file-eol, using C-x RET C-h

        using C-x 8 to insert latin-1 char Bjørn ¿

        M-- M-; can delete the line comment

        C-i and M-; is same, both of them can indent the comment line

        set-selective-display C-u C-u C-x $ hide line begin > 8

        change the eol indicator in mode line d\\r\\n means DOS CRLF,
        m\\r means MAC CR.

        the fast way to input buffer and file/directory is using ido,
        the fast way to input command is icomplete and partial
        completion.  icicle can do more deep research on commands,
        ibuffer is same to buffer and dired is for file.

        ido has a magic switch mode method.

        C-x C-d like C-x C-f, but only for directories

        detail information, M-x report-emacs-bug
        
        list-matching-lines-default-context-lines should be 0,
        otherwise can not quick look at it.

        shrink-window-if-larger-than-buffer C-x -

        do not need a overwrite-mode key binding, because the
        insertchar can do that.

        list-matching-lines-default-context-lines should be 0,
        otherwise can not quick look at it.

        shrink-window-if-larger-than-buffer C-x -

        default-frame-alist defined the foreground color, so for
        print,can change that on fly.

        [list-faces-display], if change the buffer-id faces in the mode
        line, the cursor color is changed also.

        [list-faces-display] can help you customize the faces.

        using customize-group RET font-lock-faces to set the syntax
        highlight

        you can generate very beautiful print out by ps-print-buffer-with-faces

        to Accelerate the parsing of long complicate syntax language,
        as c++, you can set the font-lock-maximum-decoration to a
        level is not too high.

        Another method to accelerate the speed to highlight the syntax
        is using the jit-lock.

        apropos font-lock can customize many language related faces

        bookmark-insert can copy things in bookmark to buffer quickly

        C-u 0 [C-x C-t, C-t, M-t, C-M-t] can do transpose remotely.

        C-u C-x r + register_number, will add 4 to the register_number

        M-s center a line

        C-SPC C-SPC only set mark, not active the mark

        C-M-w append-next-kill

        C-x C-x exchange the mark and point

        C-h .  can show some tips information even in the text-mode

        if point is near the function and varible, just type C-h f, do
        not need input the funtion name.

        see the Language and Coding system and input method.

        for check the coding system, a quick way is from the mode
        line,  the other method is C-h C

        if the buffer is readonly, auto open the view mode

        if the buffer is readonly, kill is not a wrong, just for yank

        indent-relative can be used to write column content

        C-h i (m i s), if you can remember the topic or content

        ? SPC icomplete

        completion-ignored-extensions

        icomplete-mode

        pcomplete

        C-x ESC ESC can complete more complex command than the M-p,
        not only the command , but also the eval, and prompt with the
        redo and the lisp expression of that command.

        C-u C-x = show current charactor, here you get the code point
        of the charactor, so you can insert it again using the C-q
        followed by the octal code point number.   For example, the c-h
        h can show the hello file.

        frame can be on another display or tty, if on the text
        terminal, can using the frame remember the windows settings
        set-frame-name, (select-frame-by-name)

        message-log-max

        view-lossage can't display the Control charactor, but
        dribble file can.  TAB is C-i, DEL is C-? or C-h (depend
        on terminal settings) ESC is C-[, RET is C-m, so what
        ever the keyboard is, the only important key is Ctrl,
        other keys is just a Control charactor.  Then you can get
        three result, first, do not bind these control charactor,
        second if some key can not work, you can use the control
        method, and last, if you feel such keys is too far away
        from your finger, you can just press the C-i?[m\_^234567
        ...  you can only use c b i and C M to browse in the help
        mode.

        META is modifier but the ESC is a seperater.

        C-x @ s can simulate super key, and C-x @ h can simulate the
        hyper key

        Using C-u C-u C-n C-x z z z z z to scroll

        Using C-x C-n to set the next-line and previous-line stop
        position.  it is disabled by default.

        If you want to see all Meta prefix key bindings, use the ESC
        f1, then you can learn many things from there, ESC C-h can not
        work because it is binded to select function by default.  for
        more details, see the variable esc-map

        overwrite mode

        hl-line-mode can highlight current line.
        complete symbol is bind to M-TAB, but it is the switch window
        bindings in many windows manage system, so press the C-M-i.

        you do not need C-a C-k the find-file default parameter, just
        type double //, find-file will discard any charactor before
        double //.

        quick move cursor using M-r

        toggle-truncate-lines

        other quick indent methods include M-i C-i M-SPC M-\

        browse help using back and forward button
        using view mode to just view readonly file, like less

        register, bookmark and rectangle they are same, let you naming
        operations include select, find position, input text, input
        number, modify windows and frame.

        keyboard macro like C-x r three, it is another method to
        define shortcut, bind name to definition, but C-x r three
        more like defvar, and kbd-macro more like defun, a saved
        kbd-macro like a program wrote by key-binding language,
        it is not suitable for human reading and wrting, and it
        is not a function , because of without parameter, if
        needed user can rewrite the function in emacs lisp, and
        binding it again.  

        name-last-kbd-macro invoke fset, insert-kbd-macro
        generate the lisp code using fset.

        kbd-macro can  DO repeat, query, recursive editing.

        there is a detail description of difference between
        function, command and macro in elisp's
        info, function, [what is function] , after eval a
        function dynamically, maybe it is not a
        byte-code-function anymore, it means the same symbol now
        binding to another entity.

        C-q C-l insert a page, C-x [ and C-x ], move as page

        using C-h d , then input word list, search all contents in
        documents.  Jump using TAB and M-TAB in help view mode.

        M-x apropos and C-h a apropos-command is different.

        Using C-M-c exit recursive editing.

        Using M-x linum to toggle line number

        C-u C-M-| can filter the region using any shell command

        C-x C-o kill blank lines around

        M-\ kill whitespace around

        (setq show-trailing-whitespace t), delete-trailing-whitespace

        info-apropos

        customize-apropos

        beside moving by sexp and list, c can moving by macro, see conditional.

        C-cc C-uC-cc in c-mode at defun point open and close comment at func level

        C-M-i symbol-complete

        the syntax highlight is done by font-lock-mode
DESIGN THOUGHT:

        Emacs is a way of life, one day you encountered it, try to be
        family with it, remove conflict one by one, and love it finally.

        Improve yourself daily
        Using it anywhere
        Do everything Dynamically
        Efficiently thinking, viewing ,moving and inserting

        Given anything a name, then define a shortcut to it, so
        there will be more and more names, need long and long
        name to avoid conflict, the files, the buffers, the
        commands ... how to quick find them is very important, if
        you can access the proper sized document and the
        candidate on the fly, it would be fine.  igood good

        You can also use many tiny editor in the minibuffer, move eye
        ball and finger as less as possible, they are the 
        Sometime select is for killing, and kill is for selection.
        but indeed I want to do one thing without through
        another thing's method, I do not want to express.

Hi-lock: ((\".*:\" (0 (quote hi-blue-b) t)))
Hi-lock: ((\"No\" (0 (quote hi-red-b) t)))
Hi-lock: ((\"Done\" (0 (quote hi-green-b) t)))

                 ")
    (goto-char (point-min))
    (display-buffer "BARTUER REMARK")
    t))
