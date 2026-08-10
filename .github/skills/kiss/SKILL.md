---
name: kiss
description: Find the laziest correct solution. Use while implementing or reviewing code, plans, and diffs; use audit mode for "kiss audit". Removes unnecessary work without weakening explicit requirements, safety, or verification.
---

# KISS

Minimal means the least mechanism that fully satisfies the contract, not the
fewest lines regardless of risk.

## Boundary

- `kiss` tests necessity and implementation weight.
- It does not choose product behavior (`frontier`), author plan structure
  (`org_plan`), or execute plan state (`exec_plan`).
- Understand the real flow before simplifying; a small change at the wrong
  layer is not simple.

## Ladder

Stop at the first rung that fully meets the requirement:

1. Does this need to exist? (YAGNI)
2. Does the codebase already provide it?
3. Does the standard library provide it?
4. Does the native platform provide it?
5. Does an installed dependency provide it?
6. Can one direct expression solve it clearly?
7. Only then write the minimum new code.

Prefer deletion over addition and boring code over clever abstraction. Fix
bugs at the shared root-cause choke point, not at each symptom.

## Guardrails

Never simplify away:

- trust-boundary validation;
- data-loss and failure handling;
- security or accessibility;
- compatibility and rollback required by the task;
- explicit user requirements;
- the runnable check for non-trivial behavior.

Do not add speculative abstractions, scaffolding, or frameworks. If a deliberate
ceiling is accepted, mark it locally as:

```text
# kiss: <current ceiling>; upgrade when <observable condition>
```

## Modes and output

**Build mode:** apply the ladder while implementing; avoid a separate report
when the result is self-evident.

**Audit mode:** inspect each plan item or diff hunk. Report only places that can
stop at a lower rung, with the shorter alternative and why it remains correct.

Use this concise form:

```text
<item or hunk> -> remove/replace with <simpler form>; add complexity only when <condition>.
```
