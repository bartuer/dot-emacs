# Copilot Chat Conversation Export: Compatibility of vterm with Ink TUI

**User:** @bartuer
**Thread URL:** https://github.com/copilot/c/bd779efa-54ee-46ef-8040-811fbad3929f

## @bartuer

it compatible with the latest libvterm?, how about compatible with TUI?

## Copilot

Yes—**`akermu/emacs-libvterm` is generally compatible with the latest libvterm**, and if you install it the usual way (MELPA / building the module), it will **either use your system libvterm (if found) or automatically download/build a current libvterm** during compilation. ([github.com](https://github.com/akermu/emacs-libvterm))

Practical notes:

## 1) “Latest libvterm” compatibility
- The project’s stated requirement is **libvterm >= 0.2**. ([github.com](https://github.com/akermu/emacs-libvterm))  
- If your distro’s libvterm is **too old** (the README specifically calls out older Ubuntu/Debian versions and mentions build errors around `VTERM_COLOR`), you should **avoid the system libvterm** and let emacs-libvterm **build its bundled/downloaded one** (i.e., configure with `-DUSE_SYSTEM_LIBVTERM=no`). ([github.com](https://github.com/akermu/emacs-libvterm))
- Some newer features (example: OSC52 clipboard integration) rely on newer libvterm internals, and the README again recommends building with `-DUSE_SYSTEM_LIBVTERM=no` to ensure you have a new-enough libvterm and to avoid known truncation bugs in older libvterm builds. ([github.com](https://github.com/akermu/emacs-libvterm))

## 2) “Compatible with TUI?”
If by “TUI” you mean **full-screen/interactive terminal UI apps** (ncurses-style programs like `htop`, `ncdu`, `nmtui`, etc.), then **yes**: this is one of the main reasons to use `vterm`. The README explicitly contrasts it with `eshell`/`shell` (which don’t support such apps) and says `vterm` has “nearly universal compatibility with terminal applications.” ([github.com](https://github.com/akermu/emacs-libvterm))

## Quick recommendation
- If you want the smoothest “latest libvterm” experience across distros: **compile with the bundled libvterm** (`-DUSE_SYSTEM_LIBVTERM=no`) unless you *know* your system `libvterm` package is current. ([github.com](https://github.com/akermu/emacs-libvterm))

If you tell me your OS/distro (and whether you’re using system packages or building from source), I can suggest the most reliable install path for your setup.

## @bartuer

https://github.com/features/copilot/cli use which TUI lib? Node.js terminal UI frameworks like Ink? 

## Copilot

GitHub Copilot CLI’s **interactive TUI is built with Ink (React for CLIs)** — not Blessed. GitHub’s own engineering write-up about the Copilot CLI banner has a section titled **“Exporting to Ink (React for the terminal)”**, describing integrating the animation into the Copilot CLI codebase via Ink components. ([noise.getoto.net](https://noise.getoto.net/2026/01/28/from-pixels-to-characters-the-engineering-behind-github-copilot-clis-animated-ascii-banner/?utm_source=openai))

A couple of clarifications:

- **Ink** is a Node.js terminal UI framework that renders React components to the terminal (stdout). ([gitlink.org.cn](https://www.gitlink.org.cn/mirrors/ink?utm_source=openai))  
- The public marketing page and docs don’t call out “Ink” explicitly, but they do confirm Copilot CLI is an installable CLI (including via npm), and it has an interactive interface—i.e., a rich terminal UI exists. ([github.com](https://github.com/features/copilot/cli?utm_source=openai))

If you meant something else by “TUI lib” (e.g., what they use for prompts/select menus vs layout, or what they use for ANSI handling), tell me which part of the UI you’re asking about (input widgets, layout, keybindings, rendering/ANSI, etc.).

## @bartuer

so, we don't know if vterm works well with lnk , right?

## Copilot

We **don’t have a specific guarantee** that *Emacs vterm* “works well with Ink” in the sense of an officially tested compatibility statement from either project.

That said, in practice **vterm usually works well with Ink-based CLIs**, because:

- **Ink renders to a normal terminal** using ANSI escape sequences and relies on typical terminal capabilities (cursor movement, clearing regions, colors, etc.). That’s the same class of behavior vterm is designed to emulate via libvterm.
- `emacs-libvterm`’s goal is **high compatibility with terminal applications**, especially full-screen / interactive TUIs. So Ink apps fall within what it aims to support.

Where it can get flaky (rare, but possible) is when an app:
- depends on very specific **terminal feature detection** (TERM/terminfo quirks),
- uses unusual **mouse tracking**, bracketed paste, or
- assumes certain **alternate screen / cursor save-restore** semantics that differ across emulators.

If you want to *quickly verify* on your machine, the most reliable test is:

1) In Emacs, open `M-x vterm`
2) Run an Ink-heavy CLI (for Copilot CLI, run whatever interactive command opens its TUI)
3) Check:
   - screen redraw correctness (no “ghost” lines)
   - keyboard input (arrows, ctrl keys, alt/meta)
   - resize behavior
   - colors and cursor placement

If you tell me which Ink app you care about (Copilot CLI? something else) and your OS + Emacs version, I can suggest a focused checklist and common fixes (e.g., TERM value, libvterm build choice, or emacs-libvterm compile flags).
