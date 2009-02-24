
(fset '2-floor
   (lambda (&optional arg) "Keyboard macro." (interactive "p") (kmacro-exec-ring-item (quote ("afloorlfloor>\\\\>l" 0 #("%d" 0 2 (auto-composed t)))) arg)))

(fset 'mark-hide
   (lambda (&optional arg) "Keyboard macro." (interactive "p") (kmacro-exec-ring-item (quote ("	" 11 " [%d]")) arg)))

(fset 'first-child
   "\C-n\C-j\C-[\C-[OC")
