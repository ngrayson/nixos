# Conveyor Plan Format & Sizing

## Plan Format

```markdown
## Objective
One sentence: what this task accomplishes and why.

## Approach
High-level strategy with relevant files/patterns/APIs.

## Implementation Steps
1. Concrete step.
2. Concrete step.

## Testing
- Commands and manual checks.
- Edge cases.

## Notes
- Dependencies, risks, blockers, or files likely touched.
```

## Sizing

Default **1 SP**. Use **2 SP** for multi-file work, **3 SP** for complex
patterns/design choices, **5 SP** only for hard work. Split anything larger.

## Packs (parent + child tasks)

A **pack** is Conveyor's bundle shape: a parent card with child cards.
`create_subtask(parentTaskId, ...)` creates a NEW child; to move an EXISTING
card under a parent (or out of one) use `set_task_parent`. `create_task` /
`update_task` have no parent field. Each child is a full card
(own chat, plan, story points). Split into a pack only when the work is
genuinely multiple independently buildable pieces (8-SP-tier); otherwise keep
one card.

- **Orchestration packs** (future work): `start_task` on the parent boots a
  *pack runner* that starts each ready child's own build/PR, honoring
  `add_dependency` edges (independent children run in parallel). Give each
  child a detailed plan with a **Testing / Verification** section —
  identification sizes children like any other card. The parent card's
  `featureBranch` setting (default on) makes children branch off and PR back
  into the parent's branch instead of the default base.
- **Mirror packs** (already-done work shipping in ONE PR on the parent's
  branch): create children with **`followParentStatus: true`** — title and a
  plain-language description only. A follower mirrors its parent's status
  automatically through the whole pipeline, identification sizes it, and it
  never posts its own Slack card. Evidence rolls up to the **parent**. Never
  `start_task` a mirror pack's parent, and leave children's PR fields empty —
  the parent owns the PR.

## Status Flow

`Planning -> Open -> InProgress -> ReviewPR -> ReviewDev -> ReviewLive -> Complete`

`Cancelled` is terminal. A task must be `Open` before `start_task`.
