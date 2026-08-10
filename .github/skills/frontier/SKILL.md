---
name: frontier
description: Resolve consequential human decisions without silently guessing. Use before planning when scope or behavior is genuinely ambiguous, or in micro mode when execution reaches an unplanned branch. Produces concise `:decision:` and `:rejected:` annotations for the plan.
---

# Frontier

Map only the decisions needed to unblock the requested work.

## Boundary

- `frontier` resolves preferences, tradeoffs, scope, and behavior.
- The agent resolves discoverable facts through tools and repository research.
- `org_plan` turns settled decisions into work structure.
- `exec_plan` resumes execution after a micro decision.
- `kiss` removes branches that do not need to exist.

Never ask the user for a fact the environment can provide.

## Modes

### Planning mode

Use before authoring when multiple reasonable designs materially change the
plan. Stop once the decisions required for a deterministic plan are settled;
do not expand hypothetical branches that cannot affect the current goal.

### Micro mode

Use during execution for one unplanned blocker. Resolve that decision, record
it in the plan, and return control to `exec_plan`.

## Decision loop

1. Build the dependency tree of unresolved decisions internally.
2. Research facts that can eliminate branches.
3. Select the earliest decision whose prerequisites are settled.
4. Ask one focused question through the interactive question tool. Prefer
   concrete choices and put the recommended choice first.
5. Explain the recommendation in one sentence.
6. Update the tree from the answer and repeat only if another material
   decision remains.

Do not implement or author the plan before the required decisions are
confirmed.

## Output

Compress results into plan-ready annotations:

```org
:decision: <choice and concise rationale>
:rejected: <alternative> -- <reason>
```

Return settled branches, not the Q&A transcript.
