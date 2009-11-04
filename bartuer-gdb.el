;; restore-frames is the best way to layout debugger windows: 
;; use GDB 7.0, it now support unicode, set host-charset auto
;; set breakpoint in source buffer via alias b and bb
;; all debugger related buffers grouped under debugger

;; see gdb-debug-log
;; also see gdb-annotation-rules
;; also see info page's GDB/MI section
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

;; TODO gdb command help in anything

(defun bartuer-gdb-load ()
  "for Debugger mode's quick switch window"
  (define-key gdb-locals-mode-map  "\C-i" 'gdb-local-toggle)
  (defalias 'b 'gud-break)
  (defalias 'bb 'gud-remove)
  (defalias 'k 'gdb-display-gdb-buffer)
  (defalias 'x 'gdb-display-memory-buffer)
  (defalias 'thread 'gdb-display-threads-buffer)
  (defalias 'disa 'gdb-display-assembler-buffer)
  (defalias 'regs 'gdb-display-registers-buffer))




