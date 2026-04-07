---
name: org_plan
description: Use this skill create comprehensive plan document
---

# Plan Doc Format Description

### The Org mode plan document is an executable

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
    - if you have something to summarize, add to fix.archive folder
      with a short, meaningful name

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
      - remember, never run test and test target in the same shell
        run test in a shell, run main loop in another, otherwise you
        will struggle a lot
      - other keywords surround by : normally reference a file,
        commit, Class, method, anything user can reference and already
        reference in the user prompt

# Example

[successul_executed_plan_doc](../../REPL/11.prompt.fingerprint.upgrade.org.txt "sample")

# Generate Plan Doc

### save user plan document at request path or by default alongside the example plan doc

### after finish the draft of plan document

#### review with critique mindset
    - add necessary reference and context
      - url
      - (link "path") to local file
    - find disordered dependency
    - fix obvious implausible solution
    - make work item actionable
    - refine description in concise and way
