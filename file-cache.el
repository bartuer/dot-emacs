(file-cache-add-directory-list (list
                                "~"
                                "~/org"
                                "~/etc/el"
                                "~/org"
                                "~/local/src/selfie/jxcore/deps/leveldown-mobile"
                                "~/local/src/selfie/jxcore-addon"
                                ))
(eval-after-load
       "filecache"
       '(progn
          (message "Loading file cache...")
          (file-cache-add-directory-using-find
           "~/local/src/swift")
))