# Running GitHub Copilot CLI inside Emacs

**Date:** 2026-04-24
**Context:** Copilot CLI is a full-screen TUI. In Emacs's default `term`/`ansi-term` it renders acceptably but scrollback is awkward (`C-c C-j` line-mode vs `C-c C-k` char-mode, line-mode is editable → foot-gun). `vterm` is the right host — it speaks libvterm natively, handles the alt-screen, true colour, mouse, and has a proper read-only **copy-mode** for reviewing long tool output.

## TL;DR — the one shortcut you asked about

Inside `vterm` running Copilot CLI:

| Key | What it does |
|-----|--------------|
| `C-c C-t` | Toggle **`vterm-copy-mode`** — freezes PTY input, turns the buffer read-only so normal Emacs motion (`C-p` `C-n` `M-v` `C-v` `M-<` `M->` `C-s` `C-r`) works for scrolling. Mode-line shows `(VTermCopy)`. Press `C-c C-t` again (or `q`) to return to the prompt. |
| `RET` (in copy-mode) | Copy current line and exit copy-mode. |
| `M-w` (in copy-mode with active region) | Copy region and exit copy-mode. |

Rule of thumb: `C-c C-t` → `M-v` to page up through Copilot output → `C-c C-t` to resume typing.

Note: the Copilot CLI help command (`/help`) mentions `C-l` to clear screen and arrow keys for input history. These *only* work in char-mode; the TUI never sees them while copy-mode is on.

## Installing `emacs-vterm`

`vterm` is a native Emacs module (not pure ELisp) so you need a C toolchain plus `libvterm` at build time. The ELisp package from MELPA/ELPA will build the `.so` on first load if the prerequisites are present.

### Prerequisites (one-time, per machine)

- Emacs 26.1+ compiled with dynamic-module support (`./configure --with-modules`; most distro packages already have this — check with `M-x describe-variable RET system-configuration-features RET` — look for `MODULES`).
- CMake ≥ 3.11
- libvterm development headers
- libtool
- A C compiler (gcc/clang)

Install by platform:

**macOS (Homebrew):**
```bash
brew install cmake libtool libvterm
```

**Debian / Ubuntu:**
```bash
sudo apt-get install -y cmake libtool-bin libvterm-dev
```

**Fedora / RHEL:**
```bash
sudo dnf install -y cmake libtool libvterm-devel
```

**Azure Linux 3.0 / Mariner (`tdnf`):**
```bash
sudo tdnf install -y cmake libtool libvterm-devel gcc make
```
(If `libvterm-devel` isn't in the default repos, enable the extras repo or build libvterm from https://github.com/neovim/libvterm — vterm's `CMakeLists.txt` will also vendor-build it if you pass `-DUSE_SYSTEM_LIBVTERM=OFF`.)

**Arch:**
```bash
sudo pacman -S cmake libtool libvterm
```

**Windows:** not supported upstream. Use WSL2 + one of the Linux recipes above, or stick with `term`/`ansi-term`.

### Install the Emacs package

Pick ONE of the following — don't mix.

**MELPA (most common):** add to `~/.emacs.d/init.el` if not already there:
```elisp
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)
```
Then:
```
M-x package-refresh-contents RET
M-x package-install RET vterm RET
```

**`use-package` (declarative):**
```elisp
(use-package vterm
  :ensure t
  :commands (vterm vterm-other-window)
  :custom
  (vterm-max-scrollback 100000)    ;; Copilot output is long; default 1000 is too small
  (vterm-timer-delay 0.01))        ;; snappier redraw for TUI apps
```

**`straight.el`:**
```elisp
(straight-use-package 'vterm)
```

On the very first `M-x vterm`, Emacs will build the `vterm-module.so`. Watch the `*Compile-Log*` / `*Messages*` buffer for errors — 95% of install failures are a missing prereq from the list above.

### Verify

```
M-x vterm RET
```
You should land in a real shell. Then:
```
copilot
```
(or `copilot --banner` for the splash). Inside the session, test `C-c C-t` — mode-line flips to `(VTermCopy)`, `M-v` pages up, `C-c C-t` returns to the prompt.

## Recommended settings for Copilot CLI

Add to your `vterm` config:

```elisp
(with-eval-after-load 'vterm
  ;; Copilot CLI produces tens of thousands of lines; default 1000 loses history.
  (setq vterm-max-scrollback 100000)

  ;; Paste without vterm's bracketed-paste dance — Copilot CLI accepts raw paste fine.
  (define-key vterm-mode-map (kbd "C-y") #'vterm-yank)
  (define-key vterm-mode-map (kbd "M-y") #'vterm-yank-pop)

  ;; Let M-x commands from copy-mode not kill the session accidentally.
  (define-key vterm-copy-mode-map (kbd "q") #'vterm-copy-mode))
```

If you use `evil-mode`, add to `vterm-copy-mode-hook` a call to `evil-normal-state` so `j`/`k`/`C-d`/`C-u` just work.

## When `vterm` isn't available — `ansi-term` fallback

| Key       | What it does in `term`/`ansi-term`                                                                                                |
|-----------|-----------------------------------------------------------------------------------------------------------------------------------|
| `C-c C-j` | Switch to **line-mode** — buffer becomes a normal Emacs buffer you can scroll AND edit (careful). Mode-line shows `(Term: line)`. |
| `C-c C-k` | Switch back to **char-mode** — Copilot CLI sees keystrokes again.                                                                 |

`vterm` is strictly better for full-screen TUIs. Only fall back to `ansi-term` on platforms where you can't build native modules (e.g. vanilla Windows Emacs).

## Cross-references

- Project plan that produced this note: [`14.headless.officejs.org.txt`](../14.headless.officejs.org.txt "plan")
- Upstream vterm: <https://github.com/akermu/emacs-libvterm>
- Copilot CLI docs: <https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli>
