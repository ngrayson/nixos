---
name: conveyor-local-task
description: Complete ONE linked Conveyor card on this machine, start to ReviewPR — claim it, execute its plan in the main workspace, gate, open the PR, report, done. Use when the user says "/conveyor-local-task <card>", "do this card locally", or "complete this task on my machine". One card only, no queue and no loop — for a whole pack use conveyor-local-pack; to work everything Open (packs included) use conveyor-local-loop.
---

# Conveyor Local Task

Execute one Conveyor card exactly as a claudespace agent would, using this
machine instead of a pod: the card IS the spec, task chat is the log, and the
host repo's CLAUDE.md governs gates, verification, and PR mechanics. This
skill adds only claiming, routing, and local-machine hygiene. Finish line =
card in ReviewPR with CI started; the user reviews and merges.

## Ground rules

- **All Conveyor tools fully-qualified** (`mcp__conveyor__get_task`; bare
  names fail).
- **Run in the main workspace checkout — never a git worktree.** The fully
  provisioned main workspace (installed `node_modules`, `.env`/direnv auth
  wiring, the running dev stack) is the whole value of local execution;
  worktrees miss all of it and have consistently degraded agent sessions.
  Clean tree before any branch switch is a hard rule: dirty `git status` →
  touch nothing and report — the resolution is the user committing or
  stashing, not a second checkout.
- **Never `mcp__conveyor__start_task`** — that boots a cloud pod and
  duplicates the work you're about to do locally.
- **Never approve or merge your own PR.** ReviewPR with green-or-running CI
  is where you stop.
- **Push early.** There is no pod WIP-autosync locally; committed-and-pushed
  is the only durable state. Push the branch (`-u origin`) as soon as it
  exists.
- **Not a pod:** the dev DB and dev-server ports are shared with the user's
  interactive sessions — no destructive experiments, never reset the dev DB,
  reuse a running dev stack rather than fighting over ports.

## Resolve and route

1. Resolve the card from the argument (slug, id, or URL; none given → ask
   which card). `mcp__conveyor__get_task` for the full plan +
   `mcp__conveyor__read_task_chat` for addenda and user answers. Consult
   `mcp__conveyor__get_tag` on the card's tags before diving in — the
   overview + linked files are the fast path into the subsystem.
2. Route pack cards away:
   - Card **has children** → it's a pack coordinator; point the user at
     `/conveyor-local-pack` and stop. Children that PR straight into dev are
     not a feature-branch pack — point at `/conveyor-local-loop` instead, or
     run this skill on one child card.
   - Card **has a `parentTaskId`** and the parent is InProgress or ReviewPR →
     decline: an actively-orchestrating parent reads a headless InProgress
     child as a dead agent environment and "recovers" it onto a cloud pod
     (duplicate implementation). Parent parked → proceed; the child's base is
     the parent's feature branch.
3. Plan missing or failing the context-free-reader bar → don't wing it: post
   what's missing to chat and stop. The card must stand alone.

## Claim and execute

1. Re-confirm via `mcp__conveyor__get_task` that the card is claimable (Open —
   or whatever the user explicitly overrode — with no assignee or active
   session), then `mcp__conveyor__update_task` → `status: "InProgress"` and
   `mcp__conveyor__post_to_chat`: `[local-task] claimed — working locally on
   <hostname>`.
2. Branch from the card's base, never blindly dev: `base` = the card's
   `baseBranch` (a pack child's base is the PARENT's feature branch). If the
   card already has a `githubBranch` with commits on origin, resume THAT
   branch — a prior pod may have landed real work; audit it before
   re-implementing anything. Else `git fetch origin <base> && git checkout -B
   <feat|fix|chore>/<slug> origin/<base>`. Reinstall deps if the lockfile
   changed.
3. Work the plan. Post chat updates at real milestones only (claim, blocking
   discovery, gates green, PR) — not play-by-play.
4. Verify per the host repo's CLAUDE.md policy (scoped gates). UI-visible
   change → capture screenshot/recording evidence with the repo's tooling and
   attach via `mcp__conveyor__upload_attachment` before opening the PR.
5. Refresh against the base (`git fetch origin <base> && git merge
   origin/<base> --no-edit && git push`), then
   `mcp__conveyor__create_pull_request` with `head:` your branch and — always
   explicitly — `base:` the card's base branch. The card moves to ReviewPR.
   Post a chat summary: what shipped, how verified, what to look at.
6. Confirm CI actually started (read-only `gh pr checks`); do NOT wait on it.
   Report the card + PR state to the user — done. No pacing, no loop, no
   babysitting: follow-up CI fixes are a fresh ask.

**Blocked** — after 2 genuinely different failed approaches, or on a decision
only the user can make: post to chat the reason + the specific question, set
the card back to `"Open"`, restore the tree (`git checkout dev`), and report.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
