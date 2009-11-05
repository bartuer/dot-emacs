;; (describe-function restore-frames)
;; use GDB 7.0, it now support unicode, set host-charset auto
;; (link "~/local/src/gdb-7.0/gdb/ChangeLog" 352708)

;; (describe-variable gdb-debug-log)
;; (describe-variable gdb-annotation-rules)
;; [[info:gdb.info:GDB/MI][GDB/MI]]
;; before 6.4 annotation interface works for unicode

;; DONE local buffer's string is not set to right charset
;; DONE view hierarchical data in local buffer
;; - set print pretty                   
;; - merge annotation and mi
;; - visible high light 
;; - fold/unfold data structure
;; DONE register buffer lack the register name (works now)
;; DONE get local/memory/register buffer edit work (all bind to ENTER?)
;; - edit via annotation

;; DONE binding problem in gdb-locals-mode,
;; change the map at another place, such side effect let different
;; buffer area has different bindings, it is really interesting

;; DONE invoke gdb-locals-mode will cause update problem

;; TODO add call yas
;; TODO remember current local buffer folding

(defun bartuer-gdb-load ()
  "for Debugger mode's quick switch window"
  (defalias 'b 'gud-break)
  (defalias 'bb 'gud-remove)
  (defalias 'k 'gdb-display-gdb-buffer)
  (defalias 'x 'gdb-display-memory-buffer)
  (defalias 'thread 'gdb-display-threads-buffer)
  (defalias 'disa 'gdb-display-assembler-buffer)
  (defalias 'regs 'gdb-display-registers-buffer))




