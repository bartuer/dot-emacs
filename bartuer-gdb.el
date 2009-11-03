;; restore-frames is the best way to layout debugger windows: 
;; use GDB 7.0, it now support unicode, set host-charset auto
;; set breakpoint in source buffer via alias b and bb
;; all debugger related buffers grouped under debugger

;; TODO local buffer's string is not set to right charset
;; TODO register buffer lack the register name
;; TODO gdb command helper like rake helper
;; TODO get local/memory/register buffer edit work (all bind to ENTER?)

(defun bartuer-gdb-load ()
  "for Debugger mode's quick switch window"
  (defalias 'b 'gud-break)
  (defalias 'bb 'gud-remove)
  (defalias 'k 'gdb-display-gdb-buffer)
  (defalias 'x 'gdb-display-memory-buffer)
  (defalias 'thread 'gdb-display-threads-buffer)
  (defalias 'disa 'gdb-display-assembler-buffer)
  (defalias 'regs 'gdb-display-registers-buffer))




