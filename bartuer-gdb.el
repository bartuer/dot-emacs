(defun bartuer-gdb-load ()
"for Debugger mode's quick switch window"
  (defalias 'locals 'gdb-display-locals-buffer)
  (defalias 'x 'gdb-display-memory-buffer)
  (defalias 'bt 'gdb-display-stack-buffer)
  (defalias 'thread 'gdb-display-threads-buffer)
  (defalias 'break 'gdb-display-breakpoints-buffer)
  (defalias 'disa 'gdb-display-assembler-buffer)
  (defalias 'regs 'gdb-display-registers-buffer))




