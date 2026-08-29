---
name: conveyor-local-loop
description: Run this machine as a serial local claudespace — pick the session owner's highest-priority Open Conveyor card, claim it, execute its plan to the PR finish line, repeat. Handles single cards AND whole packs (an Open pack parent is driven end-to-end per conveyor-local-pack, then the loop moves on once the pack's final PR is open). One invocation = one iteration; run continuously with "/loop /conveyor-local-loop" (no interval) and it self-paces (~1-2 min between cards while the queue has work; when the queue is empty it blocks on live board events via conveyor-wait and wakes seconds after a card becomes claimable, with a ~25 min fallback poll). Use when the user says "/conveyor-local-loop", "start the local loop", "work my open cards locally", or wants planned cards executed with full local CPU/RAM instead of spawning claudespaces. For exactly one card use conveyor-local-task; for one pack and nothing else, conveyor-local-pack.
---

# Conveyor Local Loop

Turn a queue of researched Open cards (usually authored via `/conveyor-plan`)
into review-ready PRs using this machine, one card at a time. Behave exactly as
a claudespace agent would: the card IS the spec, task chat is the log, and the
host repo's CLAUDE.md governs gates, verification, and PR mechanics. This skill
adds only selection, claiming, cadence, and local-machine hygiene.

## Ground rules

- **Conveyor is the state store.** The loop session spans days and gets
  compacted; at each iteration re-derive state from MCP reads, never from
  conversation memory.
- **All Conveyor tools fully-qualified** (`mcp__conveyor__get_task`; bare names
  fail).
- **WIP = 1.** At most one card claimed by this loop at a time.
- **Never `start_task`** — that boots a cloud pod and duplicates the work. Only
  exception: the opt-in offload valve below.
- **Merge your own PRs into `dev` once their checks pass.** A serial loop that
  parks PRs in ReviewPR forces every later card to branch from an increasingly
  stale `dev`, and cards planned in one batch routinely build on each other —
  so an unmerged queue compounds into conflicts and stale file references.
  Still never merged by the loop: a pack's finale PR into `dev` (that one is
  the user's call) and anyone else's work.
- **Only cards created by the session owner** (match against
  `mcp__conveyor__get_connection_context`), status Open, unassigned. Teammates'
  cards and pod-claimed cards are off limits.
- **Pack cards: claim the whole pack; the parent card stays parked.** An Open
  feature-branch pack parent that passes the claiming filters is claimable as
  a PACK: enter pack mode (below) and drive every child to the final parent
  PR per [conveyor-local-pack](../conveyor-local-pack/SKILL.md). Throughout,
  the parent card itself stays PARKED — never Build/`start_task` it, never
  set it InProgress; the finale `create_pull_request` is what moves it to
  ReviewPR. A parent already InProgress/ReviewPR has (or had) an active
  coordinator — hands off it AND its children: an actively-orchestrating
  parent reads a headless InProgress child as a dead agent environment and
  "recovers" it onto a cloud pod (observed 2026-07-28 — duplicate
  implementation). A NON-feature-branch pack — children PR straight into dev,
  so there is no pack branch to coordinate — is never claimed as a pack:
  /conveyor-local-pack explicitly does not apply to it. Claim those children
  individually, one per iteration, and only while the parent is parked.
- **Run in the main workspace checkout — never a git worktree.** The fully
  provisioned main workspace (installed `node_modules`, `.env`/direnv auth
  wiring, the running dev stack) is the whole value of local execution;
  worktrees miss all of it and have consistently degraded agent sessions.
  Clean tree before any branch switch is still a hard rule: dirty
  `git status` at iteration start → touch nothing, report, and idle — the
  resolution is the user committing or stashing, not a second checkout.
- **Push early.** There is no pod WIP-autosync locally; committed-and-pushed is
  the only durable state. Push the branch (`-u origin`) as soon as it exists.

## Iteration order

Each invocation does the FIRST of these that produces work, then paces:

1. **Recover** — a card with my `[local-loop] claimed` chat marker still
   InProgress without a PR? Resume it. The branch may already exist locally or
   on origin — check both before re-implementing anything. A pack parent
   whose chat carries my `[local-loop] claimed — driving this pack` marker
   and isn't yet in ReviewPR? Resume pack mode — re-derive where it left off
   from `mcp__conveyor__list_subtasks`, never from session memory. Skip a
   parent whose LATEST marker is `[local-loop] parked:` with no human reply
   after it — that pack yielded the WIP slot and stays yielded until the user
   replies; fall through to the next tier.
2. **Babysit** — my loop-opened PRs (ReviewPR cards, pack finale PRs
   included): red CI → fix now (on a pack finale, directly on the pack
   branch); request-changes or unanswered review comments → address now;
   green and quiet → leave alone.
3. **Claim** the next card (below).
4. **Idle** — nothing claimable: arm the board-event wake (below), then pace long.

## Claiming

1. `mcp__conveyor__list_tasks` with `status: "Open"` — results are already
   priority-then-newest ordered; board priority IS the intelligence, don't
   invent your own ranking. Walk top-down, `mcp__conveyor__get_task` each until
   one passes: created by me, no assignee or active session, an executable
   plan (a pack parent that still needs breakdown is fine — breakdown is
   pack-mode work), all `mcp__conveyor__get_dependencies` blockers Complete,
   no `[local-loop] parked:` chat marker without a later human reply (a reply
   un-parks), and the pack rules hold: a FEATURE-BRANCH pack parent (children
   branch from and PR into a pack branch — including one planned as a pack
   that has no children yet) is claimed as a PACK → pack mode below; a
   non-feature-branch parent, whose children PR straight into dev, is never
   claimable — take its children one at a time instead; a card with a
   `parentTaskId` only while the parent's status is neither InProgress nor
   ReviewPR (see ground rules).
   Skip `followParentStatus` mirror children. A blocker counts as met only
   when merged-or-beyond (ReviewDev/ReviewLive/Complete) or Cancelled — a
   blocker sitting in ReviewPR is NOT met until its PR merges.
2. Claim: re-confirm via `get_task` it is still Open, then
   `mcp__conveyor__update_task` → `status: "InProgress"`, then
   `mcp__conveyor__post_to_chat`: `[local-loop] claimed — working locally on
   <hostname>`. Claiming a PACK is different — never set the parent
   InProgress: leave it Open and post the pack claim marker instead (see Pack
   mode). Status changed under you → someone else took it; next
   candidate.
3. Plan missing or failing the context-free-reader bar → don't wing it: post
   what's missing to chat, leave the card Open, skip it.

## Execute and finish

1. `mcp__conveyor__get_task` (full plan) + `mcp__conveyor__read_task_chat`
   (addenda, user answers). The card must stand alone — if you find yourself
   relying on loop-session memory, stop and re-read the card instead. Consult
   `mcp__conveyor__get_tag` for the card's assigned/mentioned tags before
   diving in — the overview + linked files are the fast path into the
   subsystem.
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
5. Refresh against the card's base (`git fetch origin <base> && git merge
   origin/<base> --no-edit && git push`), then
   `mcp__conveyor__create_pull_request` with `head:` your branch and `base:`
   the card's base branch. Pack child: re-check the parent's status first —
   if it went InProgress/ReviewPR, park instead (post `[local-loop] parked:
   pack coordinator active — yielding`, leave the branch pushed) and let the
   coordinator take over. The card moves to ReviewPR. Post a chat summary:
   what shipped, how verified, what to look at.
6. Confirm CI actually started (read-only `gh pr checks`); do NOT wait on it —
   later iterations babysit.
7. **Read merge state from Conveyor, never by polling the forge.** Conveyor is
   the state store (see the ground rules), and a card at ReviewDev or beyond
   IS the merge signal — `mcp__conveyor__get_task` answers "did it land?"
   authoritatively. Reach for `gh` only for something Conveyor does not track,
   and then use `--json state,mergedAt`: there is no `merged` field, and a
   query naming one returns an error that an unguarded shell test silently
   reads as "not yet".
8. **Bound every wait.** A polling wait needs a deadline and must report on
   BOTH outcomes, so a condition that can never come true surfaces as a
   timeout instead of as silence. Never write an `until`/`while` loop whose
   exit condition cannot be falsified — if the check errors, the loop spins
   forever and its silence is indistinguishable from work still in progress.

**Parked protocol** — after 2 genuinely different failed approaches, or on a
decision only the user can make: post `[local-loop] parked: <reason + the
specific question>`, set status back to `"Open"`, restore the tree
(`git checkout dev`), move on. The user's next chat reply is the un-park
signal.

## Pack mode

Claiming an Open pack parent means driving the ENTIRE pack, exactly per
[conveyor-local-pack](../conveyor-local-pack/SKILL.md) — setup (pack branch on
origin, child breakdown if the parent has none yet), children serially in
dependency order, reviewer-of-record review + merge of each child PR into the
pack branch, dev→pack sync after every merge, cross-reference, then the finale
parent PR into dev. That skill is the source of truth for the procedure; this
section only defines how it embeds in the loop:

- The pack occupies the loop's single WIP slot from claim until the finale PR
  opens. Do not interleave unrelated cards mid-pack — that thrashes branch
  state.
- Claim marker goes to the PARENT chat: `[local-loop] claimed — driving this
  pack locally on <hostname>, pack branch <branch>`. The parent's status
  stays Open (parked); the marker is the claim.
- Once the finale PR is open (parent in ReviewPR), the pack leaves the WIP
  slot: its PR joins the Babysit tier like any other loop-opened PR, and the
  loop resumes claiming other cards. This is the one difference from
  standalone /conveyor-local-pack, which stops when the pack is done.
- Parked children follow conveyor-local-pack's parked protocol. If every
  remaining child is blocked on the user, the pack yields the WIP slot: post
  `[local-loop] parked: <what it is waiting on>` to the PARENT chat — that
  marker is what makes the Recover tier skip the pack — and the loop claims
  other cards. The user's chat reply un-parks it, and the next Recover tier
  retakes the slot.

## Waking on board events

An empty queue is not a quiet board. Rather than sleeping blind for 25 minutes,
arm `conveyor-wait`: a CLI in `@rallycry/conveyor-mcp` that subscribes to the
project's live card stream and exits the moment a card ENTERS a claimable
state. A card created Open, a Cancelled card reopened, and a card reassigned to
you all count; an edit to a card that already matched does not.

Arm it on an idle iteration only (tier 4), and only when no wait from an earlier
iteration is still running:

```bash
node_modules/.bin/conveyor-wait --scope mine,unclaimed --timeout 1740
```

Launch it with Bash `run_in_background: true` and end the turn. Its completion
notification is the wake. The `ScheduleWakeup` you still arm is the fallback for
the case where the wait dies silently — use the pacing table's background-gate
row (1200–1800s), not a second, shorter timer.

- Prefer `node_modules/.bin/conveyor-wait`. If it is absent, use
  `npx -y -p @rallycry/conveyor-mcp@latest conveyor-wait`. The `-p` form
  matters: inside the conveyor monorepo a bare
  `npx @rallycry/conveyor-mcp` misresolves.
- Narrow `--types` to whatever focus the user gave the loop invocation —
  "focus on incidents" → `--types incident`. The default watches tasks,
  incidents, and suggestions.
- `--scope mine,unclaimed` mirrors the claiming filter: cards assigned to the
  session owner plus unassigned cards. Use `--scope all` only when the user
  asked the loop to watch the whole board.
- `--statuses` defaults to `Open`, which is the claimable lane. Leave it alone
  unless the user asked for something else.
- Credentials come from the environment, then any `.mcp.json` from the working
  directory up, then `~/.claude.json`. An agent Bash shell does not inherit the
  MCP server's environment, so that file fallback is what makes this work at
  all. Exit 1 means the wait could not run: no credentials, a rejected token, or
  a project it cannot read. Read the stderr line, report it once, fall back to
  plain timed polling, and do not re-arm it every iteration.

**The result is advisory — the queue is still the source of truth.** The CLI
prints one line of JSON and exits 0 in every non-error case:

```
{"reason":"event","card":{"id":…,"slug":…,"title":…,"type":…,"status":…,"assignedUserId":…}}
{"reason":"timeout"}
{"reason":"interrupted"}
```

On wake, run a normal iteration and re-enumerate with
`mcp__conveyor__list_tasks`. By then the card may be claimed, cancelled, or
blocked by a dependency — never claim straight from the wait payload.

**Never arm a second wait.** On a wake where a wait process is still in flight
and the queue is still empty, re-arm the fallback `ScheduleWakeup` and end the
turn.

## Pacing

**A denied tool is not a denied goal.** Report a capability as unavailable only
after checking the alternatives — the failure below is what that rule exists to
prevent.

Under `/loop` WITH an interval, the harness's `CronCreate` normally owns the
cadence. If that call errors or is denied, do NOT report the schedule as
impossible and stop: fall back to `ScheduleWakeup` with
`delaySeconds = min(interval_seconds, 3600)` and say so in the iteration
summary. Treat this as a normal branch, not an exotic one — the denial is
intermittent, so the same invocation can succeed one hour and fail the next,
which is precisely why the fallback has to be automatic. Only an interval above
3600 s has no local option at all; point at the `schedule` skill (a durable
cloud schedule) rather than silently doing nothing. A loop that cannot schedule
its next iteration has no way to tell anyone — it does not crash or retry, it
just stops while the session still looks alive.

Under `/loop` with NO interval, self-pace: end EVERY iteration with exactly one
`ScheduleWakeup` (prompt = the original /loop input verbatim):

| State | Delay | Reason should say |
|-------|-------|-------------------|
| A background gate/agent/conveyor-wait is in flight — its completion notification is the real wake | 1200–1800s fallback | "fallback while <gate> runs — its notification wakes me sooner" |
| ANY actionable work exists: claimable cards or packs, a pack child to implement/merge, a PR still to open, red/pending CI, review comments | 60–90s | queue depth / which item is next |
| Queue enumerated as empty THIS iteration, all loop PRs green and quiet | 1200–1800s | queue empty; conveyor-wait armed, so this is only the fallback |
| Loop-fatal: MCP dead after 2 tries, dirty tree, broken repo | notify the user (PushNotification if available), then 1800s — or `stop: true` if continuing is unsafe | what is wrong |

The long idle tier is EARNED, never defaulted: it requires having enumerated
the queue this very iteration and found zero actionable work. When unsure
which tier applies, take the short one — a wasted 60s wake costs less than a
30-minute stall on live work.

Invoked bare (no /loop)? Run one iteration, report, and suggest
`/loop /conveyor-local-loop` — don't self-schedule.

## Offload valve (opt-in)

Only with an explicit `offload=N` argument: when 4+ claimable cards queue up,
`mcp__conveyor__start_task` up to N of the smallest into claudespaces and say
so in the iteration summary. Without the argument, never — just report backlog
depth each iteration so the user can offload manually.

## What this is not

- Not a reviewer of other people's work: never `approve_task` or
  `request_changes` on anything, and never `approve_and_merge_pr` on a pack's
  finale PR or on a card this loop did not open. Merging the loop's own passing
  PRs into `dev` is expected — see the ground rules.
- Not a pod: no sandbox, no WIP snapshots, and the dev DB + dev-server ports
  are shared with the user's interactive sessions — no destructive
  experiments, never reset the dev DB, reuse a running dev stack rather than
  fighting over ports.
- Not a parallel executor: one card (or one pack) at a time is the point (the
  full machine per gate). Backlogged? That is what claudespaces — or the
  offload valve — are for.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
