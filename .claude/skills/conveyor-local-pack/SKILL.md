---
name: conveyor-local-pack
description: Drive one Conveyor pack (parent card + children) on this machine start to finish — this session is BOTH the pack coordinator and every child's implementer. Work children serially in dependency order, PR each into the pack branch, review + merge locally, sync dev after every merge, then land the whole pack as one final parent PR into dev. The local alternative to pressing Build on a parent card. Use when the user says "/conveyor-local-pack <card>", "drive this pack locally", or "run the whole pack on my machine". One invocation = one step (next child, a merge, or the finale); run continuously with "/loop /conveyor-local-pack <card>" (no interval) and it self-paces until the final PR is green, then stops itself. For a single non-pack card use conveyor-local-task; to work the whole Open queue (packs included) use conveyor-local-loop.
---

# Conveyor Local Pack

The cloud pack runner's autonomous loop (`pack-runner-prompt.ts`), adapted to
one machine. Two deliberate differences from the pod version:

- **No coordination-only rule.** The cloud runner fires child pods and never
  writes code; here the same session implements each child itself.
- **No server-side base sync.** The server merges dev into the pack branch
  before each cloud child launch; locally that sync is your job, after every
  child merge.

Everything else carries over: the card is the spec, task chat is the log, and
the host repo's CLAUDE.md governs gates, verification, and PR mechanics. This
skill assumes a feature-branch pack — children branch from and PR into the
pack branch, and the pack lands on dev in ONE final PR. If the parent has no
feature branch (children PR straight into dev), this skill does not apply:
run /conveyor-local-loop over the children instead.

## Ground rules

- **The parent card stays PARKED until the final PR.** Never
  `mcp__conveyor__start_task` the parent and never set it InProgress: the pack
  watchdog and child-event notifier ignore parked parents, but an ACTIVE
  parent treats a headless InProgress child as a dead agent environment and
  "recovers" it onto a cloud pod — duplicate implementation (observed
  2026-07-28). The final `create_pull_request` is what moves the parent to
  ReviewPR. Parent already InProgress/ReviewPR at setup → a coordinator is (or
  was) active; report and stop rather than compete.
- **Conveyor is the state store.** A pack spans days and the session gets
  compacted; every iteration re-derives state from `mcp__conveyor__get_task` +
  `mcp__conveyor__list_subtasks`, never from conversation memory.
- **All Conveyor tools fully-qualified** (`mcp__conveyor__get_task`; bare
  names fail).
- **WIP = 1, strictly serial.** One child at a time, in dependency order. No
  cloud offload: never `start_task` a child — a pod would duplicate the local
  work. Want parallel fan-out? Press Build on the parent instead.
- **You are the reviewer of record for child PRs** — the automated code
  reviewer skips PRs that target the pack branch. Review each child diff for
  real before merging; the independent review happens on the pack's final PR
  into dev (automated reviewer + human).
- **Never approve or merge the FINAL parent PR.** Finish line = parent in
  ReviewPR with green CI; the user takes it from there.
- **Child PRs into the pack branch get NO CI** (Conveyor runs CI on PRs to
  dev/main only) — the local gate pass is the ONLY verification before a
  child merges. Mandatory, never skippable. In a repo that does run CI on
  pack-branch PRs, let it finish before merging.
- **Run in the main workspace checkout — never a git worktree.** The fully
  provisioned main workspace (installed `node_modules`, `.env`/direnv auth
  wiring, the running dev stack) is the whole value of local execution;
  worktrees miss all of it and have consistently degraded agent sessions.
  Clean tree before any branch switch is still a hard rule: dirty
  `git status` at iteration start → touch nothing, report, idle — the
  resolution is the user committing or stashing, not a second checkout.
- **Push early.** No pod WIP-autosync locally; committed-and-pushed is the
  only durable state. Push child branches (`-u origin`) as soon as they
  exist, and the pack branch after every merge/sync.

## Setup (first iteration only)

1. Resolve the parent card from the argument (slug/id/URL — required; without
   one, ask which pack). `mcp__conveyor__get_task` +
   `mcp__conveyor__read_task_chat`.
2. Confirm it is a parked feature-branch pack: has (or will have) children,
   status not InProgress/ReviewPR, no active agent session.
3. Ensure the pack branch exists on origin: use the card's branch if set;
   else cut `ft/<parent-slug>` from `origin/dev`, push `-u`, and IMMEDIATELY
   record it on the card — `mcp__conveyor__update_task` with
   `githubBranch: <branch>` (the branch must already be pushed; the API
   verifies the ref exists). This write is load-bearing, not bookkeeping:
   identification mints a competing `conveyor/*` branch onto any branchless
   card it processes, and every pack-child merge handler keys on the card's
   recorded branch matching the PRs' real base — a drifted record strands
   externally-merged children in ReviewPR. Name the branch in the claim post
   too.
4. No children yet? Break the work down first, exactly as a fresh cloud
   parent would: explore the codebase, save the parent-level plan on the card
   (`mcp__conveyor__update_task`), then `mcp__conveyor__create_subtask` each
   child with a detailed standalone plan (file:line citations, verification
   steps) and `dependsOn` wherever one blocks on another.
5. Post to parent chat: `[local-pack] claimed — driving this pack locally on
   <hostname>, pack branch <branch>`.

## Iteration order

Each invocation re-reads the parent + `list_subtasks`, then does the FIRST
that applies:

1. **Recover** — a child with my `[local-pack] claimed` marker sitting
   InProgress without a PR? Resume it. Its branch may exist locally or on
   origin — audit what already landed before re-implementing anything.
2. **Merge** — a child in ReviewPR: merge path below.
3. **Promote** — a Planning child whose plan is solid:
   `mcp__conveyor__update_subtask` → status Open (+ story points/agent if
   unset). Genuinely not plannable → escalate to parent chat.
4. **Implement** — the next Open child with all dependencies met (a
   dependency counts as met at ReviewDev/Complete — i.e. merged into the
   pack — or Cancelled; ReviewPR is NOT met). No `dependsOn` set anywhere →
   ordinal order. Implement path below.
5. **Finale** — every child ReviewDev/Complete: cross-reference + final PR,
   below.
6. **Babysit** — final PR open: red CI or review comments → address directly
   on the pack branch (never claim or work children once the parent is in
   ReviewPR); green and quiet → post the wrap-up to parent chat and STOP the
   loop.

## Implement a child

1. `mcp__conveyor__get_task` on the child — reload the full plan fresh every
   time — + `read_task_chat` for addenda. Plan too thin for a context-free
   reader → post what's missing to parent chat, skip it, take the next ready
   child.
2. Claim: `mcp__conveyor__update_task` → InProgress, then chat marker
   `[local-pack] claimed — working locally on <hostname>`.
3. Branch from the PACK branch, never dev: `git fetch origin <pack> && git
   checkout -B <feat|fix|chore>/<child-slug> origin/<pack>`. If the child
   already has a branch with commits on origin, resume THAT branch — audit it
   first. Reinstall deps if the lockfile changed.
4. Work the plan. Chat updates at real milestones only, not play-by-play.
5. Verify per the host CLAUDE.md (scoped gates: `bun run check` +
   `bun run test:affected`). Note `test:affected` diffs vs origin/dev, so on
   a deep pack it naturally also covers previously merged children — that is
   fine, not a bug to fix. UI-visible change → capture evidence and
   `mcp__conveyor__upload_attachment` before the PR.
6. Refresh vs the pack branch (`git fetch origin <pack> && git merge
   origin/<pack> --no-edit && git push`), then
   `mcp__conveyor__create_pull_request` with `head:` the child branch and —
   ALWAYS EXPLICITLY — `base:` the pack branch. The default base is dev;
   omitting `base` opens the child against the wrong branch. Post a summary
   to the child's chat.

## Merge a child (ReviewPR)

1. Reviewer-of-record pass: re-read the child's plan, then the FULL diff
   (`git fetch origin <pack> <child> && git diff
   origin/<pack>...origin/<child>`) with reviewer eyes — plan coverage,
   stray files, pattern consistency, and that the gate pass actually
   happened. Found a real problem → fix it on the child branch first (you are
   also the implementer), re-gate, then continue.
2. Merge: `mcp__conveyor__approve_and_merge_pr`. Known trap: the merge queue
   can NEVER auto-merge a zero-check pack-branch PR — if the merge queues
   without landing, merge locally instead (`git checkout <pack> && git pull
   && git merge --no-ff <child-branch> && git push`; GitHub then marks the PR
   merged). Either way CONFIRM the child advanced to ReviewDev
   (`mcp__conveyor__get_task`; allow ~1 min for the merge webhook). Still
   ReviewPR after a local-merge fallback is an escalation, not a shrug — it
   means the parent card's `githubBranch` has drifted from the real pack
   branch: fix the parent record (`mcp__conveyor__update_task` with
   `githubBranch: <pack>`), advance the child by hand (`update_task` →
   ReviewDev), and post the drift to parent chat.
3. **Sync dev into the pack branch** — the local stand-in for the server-side
   base sync: `git checkout <pack> && git pull && git fetch origin dev && git
   merge origin/dev --no-edit && git push`. Merge, never rebase: the pack
   branch is shared (open child PRs, WIP refs) and rewriting it breaks them.
   Conflicts are yours to resolve properly — you wrote the code. If the merge
   drags in unrelated changes or errors, dev may have been rewound
   (revert/force-push): verify the previous sync point is still an ancestor
   of `origin/dev` (`git merge-base --is-ancestor`), and if not, abort the
   merge and escalate instead of chasing the noise.
4. Report the merge to parent chat in one line. Next iteration begins the
   next child.

## Finale (all children ReviewDev/Complete)

1. **Cross-reference:** for the parent plan and EVERY child plan, check the
   pack branch's actual state against the plan's acceptance and verification
   criteria — a real checklist pass, not a vibe. Small gap → fix directly on
   the pack branch. Substantial gap → new child card with a plan
   (`create_subtask`); the loop continues.
2. Pre-PR protocol on the pack branch, per the host CLAUDE.md: sync
   `origin/dev` FIRST, then ONE verification pass scoped to the pack's
   cumulative diff vs dev (cross-package packs → full `bun run test`).
3. `mcp__conveyor__create_pull_request` on the PARENT: `head:` pack branch,
   `base:` dev. The parent moves to ReviewPR. Post the pack summary to parent
   chat: what shipped per child, how it was verified, what reviewers should
   look at.
4. Confirm CI actually started (read-only `gh pr checks`); do NOT wait on it
   — the babysit tier owns it from here.

**Parked protocol** — after 2 genuinely different failed approaches on a
child, or a decision only the user can make: post `[local-pack] parked:
<reason + the specific question>` to the child AND the parent chat, set the
child back to Open, restore the tree, and take the next child whose
dependency chain doesn't run through the parked one. Everything remaining
blocked → idle long; the user's chat reply is the un-park signal.

## Pacing (dynamic /loop only)

Under `/loop` with no interval, end EVERY iteration with exactly one
`ScheduleWakeup` (prompt = the original /loop input verbatim, card argument
included):

| State | Delay | Reason should say |
|-------|-------|-------------------|
| A background gate is in flight — its completion notification is the real wake | 1200–1800s fallback | "fallback while <gate> runs" |
| Any actionable work: a child to implement/merge/promote, finale pending, red CI or comments on the final PR | 60–90s | which child / which step is next |
| Blocked on the user: parked children only, or a pack-level question posted | 1200–1800s | what it's waiting on |
| Loop-fatal: MCP dead after 2 tries, dirty tree, broken repo | notify the user (PushNotification if available), then 1800s — or `stop: true` if continuing is unsafe | what is wrong |
| Final PR green and quiet, wrap-up posted | `stop: true` | pack done |

Invoked bare (no /loop)? Run one iteration, report, and suggest
`/loop /conveyor-local-pack <card>` — don't self-schedule.

## What this is not

- Not a cloud coordinator: never `start_task` and never fire pods, for the
  parent or a child. Serial local execution is the point; for parallel
  fan-out, press Build on the parent instead of using this skill.
- Not the final reviewer: `approve_and_merge_pr` is for CHILD PRs into the
  pack branch only — never the parent's PR into dev.
- Not a pod: the dev DB and dev-server ports are shared with the user's
  interactive sessions — no destructive experiments, never reset the dev DB,
  reuse a running dev stack rather than fighting over ports.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
