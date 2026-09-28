---
name: org_plan
description: Author or edit a comprehensive Org-mode plan document under `.github/REPL/NN.<slug>.org.txt` — including `* Goal`, `* Dependencies`, `* Context`, phased `* TODO Phase N` work-item groups with `[ ]`/`[X]` checkboxes and `[N/M]` counters, `:test_tool:` verification bullets, `:interrupt:` open-question gates, and `* References`. Use when the user says "org_plan", "/org_plan", "author a plan", "draft a plan doc", "create plan NN", "add a work item to plan NN", "add a phase to plan …", "write a plan for …", "new plan doc", "extend plan …", "insert a work-item group into …", or supplies an `.org.txt` path and asks to modify its structure. Sister skill to `exec_plan` (which runs plans); this one only authors/edits them.
location: project
---

# Plan Doc Format Description

## Skill boundaries

| Skill       | Owns                                                        |
|-------------|-------------------------------------------------------------|
| `org_plan`  | Plan structure, ordering, checks, and annotations           |
| `frontier`  | Unresolved human decisions and rejected alternatives        |
| `kiss`      | Minimality audit without weakening required coverage        |
| `exec_plan` | Commands, verification, and plan-state transitions          |

### Respect the project's dev process setup

Every plan doc authored by this skill MUST include a top-of-file
"respect the dev process setup" line pointing at the per-repo
instruction files (see the "Generate Plan Doc" section below for
the required header snippet).

This skill stays project-agnostic. It does NOT enumerate the
rules themselves — the plan doc points at the per-repo
instruction files by relative path, and the executor is
required to open and respect whatever is currently there.

### The Org mode plan document is an executable
    - If material decisions remain unresolved, invoke `frontier` before
      authoring; skip it when the user has already settled them.
    - The structure of document imitate the logic in a piece of programming language:
      - *Goal*
        The final result user want to take away
      - *Dependencies*
        Preconditions to run the program, those import and include
      - *Context*
        Prepare input data, environment, augments and configure, all
        necessary information to launch the pogrom
      - *Main Loop*
        With test_tool ready and clear criteria, loop:
        - (R) figure out what's wrong with the output
        - (E) modify in codebase and run test_tool again
        - (P) read test_tool output
        - (L) until no issues at all
    - all meaning of the plan document is to finally achieve our goal
      and get something done
      - it is instrument you need strictly follow
      - it is the guidance help you navigate through the whole journey
      - it is handy check list of things to be done in your mind

### How to update on work item

    - each work item begin with "- [ ]" or "- [X]"
      [ ] -> [X] means the work item has DONE
    - the list under the work item include but not limited
      - necessary information
      - subtask
      - command line to execute
      - code sample snippet
    - when you encounter a DONE work item,
      that means we can moving on and focus on next work item

### How to update work item group

    - work item group start with * and normally has 4 state:
      - TODO
      - DONE
      - ABORT
      - HALT
      so, if you find any necessary work item group add it without
      above label
    - if you have something to summarize that is a durable finding
      (taxonomy, postmortem, recipe), add to `.github/REPL/fix.archive/`
      with a short, meaningful name and commit it.  Turn-level
      narrative (why-I-did-X notes) belongs to CLI session memory at
      `~/.copilot/session-state/$COPILOT_AGENT_SESSION_ID/checkpoints/`
      — the CLI writes those automatically; do not hand-roll them
      under `fix.archive/`.

### How to execute the plan

    - our execution discipline: handle work item group one by one
      - except *Goal*, that is final check list
      - each time we focus on one work item in it
      - when we finish one, update work item status and focus on next
      - until all work item under a work item group DONE
    - file link format
      (link "/path/to/file" digit), the digit indicate approximate
      characters from beginning to the anchor location
    - pay attention to special work item with mark: :test_tool: and
      :interrupt:
      - :test_tool: the test/verify tool to make sure our goal
        accomplished, we will use it in the *Main Loop*
      - :interrupt: is a ONE-SHOT gate, not a permanent property of
        the item.  The MOMENT the user answers it, the author MUST
        rewrite the marker to :interrupt_TAKEN_AND_CLOSED: and
        record the answer VERBATIM under a :USER_VERBATIM_<date>:
        key right beneath it.  A live :interrupt: on an item that
        has already been ruled on is a BUG in the plan doc: it
        makes every later reader stop and re-ask a settled
        question, which wastes the user's time and is the one
        thing they will not forgive twice.
      - the same applies when a ruling on ITEM A settles ITEM B's
        interrupt.  Close BOTH, and cross-reference the item that
        carries the verbatim answer.  Do not leave B looking open
        because the words landed on A.
      - remember, never run test and test target in the same shell
        run test in a shell, run main loop in another, otherwise you
        will struggle a lot
      - other keywords surround by : normally reference a file,
        commit, Class, method, anything user can reference and already
        reference in the user prompt

# Example

[successul_executed_plan_doc](../../REPL/03.ollama.org.txt "sample")

# Generate Plan Doc

### required header — dev-process-respect line

Every new plan doc MUST begin with a header block that (a) states
the plan title / number, and (b) explicitly tells the executor to
respect this project's per-repo instructions. Do NOT enumerate
the rules in the plan doc itself — a plan should stay portable
across dev-process changes.

Canonical template — paste at the very top of every new
`.github/REPL/NN.<slug>.org.txt`, before the first `* Goal`:

```org
; -*- mode: Org;-*-

#+TITLE: <plan-number> <plan-slug>
#+STARTUP: overview

* Dev process setup
  Before executing ANY work item in this plan, open and obey
  the rules defined in this project's per-repo instructions:

    - .github/copilot-instructions.md  (mirrored in CLAUDE.md)

  Both auto-load into every GHCP CLI session.  Read the current
  rules there and follow them.  This plan intentionally does
  not restate any rule — the per-repo instructions are the
  single source of truth.

```

### optional header — execution environment (only when the file exists)

Before authoring, test for an execution-environment file at
`${FLEET_HOME:-$HOME/.fleet}/cluster.md`. **If it is absent, skip this
whole section.** Emit no block and run no SENSE command; the plan is
authored exactly as before.

If it exists:

1. **SENSE.** Read the file, run the SENSE commands it lists, and read
   their output before you write any work item. This skill names no
   command; the file does.
2. **Record it.** Add a `* MEASURED <ts>` snapshot to the plan. Quote
   the file's session-count header verbatim. List the busy and free
   workers. List every live session with its group and its work, and
   mark the ones that already touch the same plan or files. Name any
   existing group to join
   instead of creating a new one.
3. **Size the waves.** Each `:parallel_group:` wave is at most the number
   of free workers.
4. **Point at it.** Emit this block right after `* Dev process setup`.
   It points at the file by path and restates none of its content:

```org
* Execution environment
  This plan runs on a multi-machine environment described in:

    - ${FLEET_HOME:-$HOME/.fleet}/cluster.md

  Read it before executing.  Where it defines parallelism, it
  outranks subagent fan-out.  This plan does not restate it.

```

### save user plan document at request path or by default alongside the example plan doc

### after finish the draft of plan document

#### review with critique mindset
    - review with the `kiss` skill (audit mode): walk every work
      item down the ladder — does it need to exist (YAGNI)? can
      groups collapse to fewer ckps? is each item the laziest
      version that still meets its :test_tool: criteria?
    - verify the "Dev process setup" block is present at the top
      of the plan doc (before `* Goal`), pointing at the per-repo
      instruction files.
    - add necessary reference and context
      - url
      - (link "path") to local file
    - find disordered dependency
    - fix obvious implausible solution
    - make work item actionable
    - refine description in concise and way
