---
name: convey-her
description: Nick's overlay on upstream conveyor-local-loop (1.0.4) for the WizOs repo — the same serial local card loop, executing each card via conveyor-build, with five amendments. (1) A loop-opened PR is merged to dev in the iteration that finds it green — this overrides upstream's never-merge-your-own-PR rule; only one may stay open awaiting the loop's own work, every open PR needs a named blocker, and PRs parked on the user do not count. (2) A card touching hosts/Hearth or hosts/Go3 is verified by actually running hearth-deploy switch / go3-deploy switch, not a build. (3) The loop ends its turn at card boundaries so the user has a window to /compact. (4) A denied CronCreate falls back to ScheduleWakeup rather than stalling. (5) The WizOs card-hygiene rules — file a bug as a card the moment it's noticed, falsify a cause before asserting it, and the create_task parameter gotchas. Use when the user says "/convey-her". For the unmodified loop use conveyor-local-loop; for exactly one card or one pack use conveyor-build.
---

# Convey-Her

Follow [conveyor-local-loop](../conveyor-local-loop/SKILL.md) exactly — the
same iteration order, claiming filters, WIP=1, pack rules, parked protocol and
pacing table — with the five amendments below. Execution inside the loop is
[conveyor-build](../conveyor-build/SKILL.md) (its task path for a childless
card, its pack path for a feature-branch pack); that skill is the source of
truth for resolving the card, branching from its base, working the plan,
gating, and opening the PR — do not re-derive its procedure here.

Upstream is stock in both scopes: bare `/conveyor-local-loop` and
`/conveyor-build` are the unmodified 1.0.4 skills, and every WizOs-specific
rule lives here. A merged PR moves its card to ReviewDev on its own; you never
set that status by hand.

## 1. Finish a PR before you start another card

This exists because the failure it prevents is the observed one: PRs pile up
in ReviewPR while the loop keeps claiming new cards, and nothing reaches
`dev`.

**This amendment overrides upstream's never-merge-your-own-PR rule**, which
appears in three places: conveyor-local-loop's ground rule "Never approve or
merge your own PRs" and its "What this is not" ("never … `approve_and_merge_pr`
on a PR into `dev`"), conveyor-build's ground rule "Never approve or merge your
own PR into `dev`", and conveyor-build's task path ("Finish line: the card in
ReviewPR with CI started. You do not merge it."). In the WizOs loop the
opposite holds: **the loop merges its own passing PRs into `dev`.** Two
exceptions carry over unchanged: a pack's finale PR into `dev` is still the
user's call, and you never merge anyone else's work.

The base skill's Execute-and-finish "Do not wait on CI … the Babysit tier owns
it from there" is **overridden here** — that deferral is the mechanism by which
PRs accumulate, every iteration passing the merge to the next one.

- **At most one loop-opened PR may be open awaiting the loop's own work.**
  Red CI, unanswered review comments, an unfinished branch — resolve it
  before claiming anything new.
- **A PR parked on the user does not count against that limit.**
  `os-rebuild switch` is always theirs to run (`AGENTS.md` forbids sudo-ing
  to activate), and some cards additionally need hardware they must touch or
  a password they must type. In this repo that is a normal way for a card to
  end, not accumulation. Keep claiming while those wait — but keep naming
  them in the count every iteration, so "waiting on you" can never quietly
  become "forgotten".
- **Green means merge now, in the same iteration that finds it green.** Wait
  for checks with a bounded loop that reports on both outcomes, then merge.
  In this repo the wait is short: there are no workflows under
  `.github/workflows/`, so the only check is GitGuardian and it reports in
  seconds.
- **The Babysit tier is a gate, not a courtesy.** If a loop-opened PR is
  open when an iteration starts, resolve it — merge it, fix its CI, or park
  it — *before* claiming anything new.
- **An open PR needs a named blocker**, recorded in the card chat. Exactly
  three qualify, and they split along the limit above: red CI and an
  unresolved review comment are the loop's to clear, so they count against
  it; a verification only the user can perform (they must run a switch, type
  a password, look at a screen, or approve a risky live action) does not.
  "A later iteration will get to it" is not a blocker at all; it is the bug.
- **Say the number out loud.** Every iteration summary states how many
  loop-opened PRs are open and, for each, which of those three reasons keeps
  it open. A count that only grows is the signal to stop claiming and drain;
  a count that is all "waiting on you" is a prompt to ask whether they want
  to clear one now.
- **Read merge state from Conveyor, never by polling the forge.** Conveyor is
  the state store (see the base skill's ground rules), and a card at ReviewDev
  or beyond IS the merge signal — `mcp__conveyor__get_task` answers "did it
  land?" authoritatively. Reach for `gh` only for something Conveyor does not
  track, and then use `--json state,mergedAt`: there is no `merged` field, and
  a query naming one returns an error that an unguarded shell test silently
  reads as "not yet".
- **Bound every wait.** A polling wait needs a deadline and must report on
  BOTH outcomes, so a condition that can never come true surfaces as a
  timeout instead of as silence. Never write an `until`/`while` loop whose
  exit condition cannot be falsified — if the check errors, the loop spins
  forever and its silence is indistinguishable from work still in progress.

## 2. Deploying is the verification for Hearth and Go3

The base skill's "verify per the host repo's CLAUDE.md policy" is generic. For
this repo, make it specific:

- A card whose changes touch `hosts/Hearth/**` is verified by running
  `hearth-deploy switch`; one touching `hosts/Go3/**` by `go3-deploy switch`.
  A successful `nix build` or `dry-activate` is a gate, not verification —
  it proves the closure evaluates, not that the thing works.
- Then check the result on the host rather than trusting the exit code:
  `readlink /run/current-system`, the relevant `systemctl show -p <prop>
  --value`, or the actual served artifact.
- **Never `sudo` on the local machine to activate it** — that rule from
  `AGENTS.md` is untouched. `hearth-deploy` and `go3-deploy` drive a *remote*
  host, which is why they are yours to run; `os-rebuild switch` for this
  machine still goes to the user.
- If a live deploy is not safely possible — the change is risky to test on a
  host in use, access is blocked, or the check needs the user present — leave
  the card in ReviewPR and write in the card chat exactly what went
  unverified and what would verify it. That is a named blocker under
  amendment 1. Do not skip the deploy and describe the card as verified.

## 3. `/compact` — what this skill can and cannot do

**A skill cannot invoke `/compact`.** It is a CLI built-in the interactive
user triggers; no tool or instruction available to an agent can call it. Do
not write it into a checklist as though it were an action, and do not report
having done it.

What is actually within reach, and is required here:

- **End the turn at card boundaries, never mid-card.** After a card reaches
  ReviewDev (or ReviewPR with a named blocker), finish the iteration and let
  the turn end before claiming the next one. That gap is the user's window to
  compact, and it only exists if you stop cleanly instead of rolling straight
  into the next claim.
- Say in the summary that the window is open and which card is next, so the
  user can compact or redirect before work starts.
- Rely on this only as a convenience, not for correctness. The base skill
  already requires re-deriving state from MCP reads at every iteration rather
  than from conversation memory, precisely because the session gets compacted
  at times nobody controls. That requirement still governs.

## 4. Pacing: a denied tool is not a denied goal

Report a capability as unavailable only after checking the alternatives — the
failure below is what that rule exists to prevent.

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
just stops while the session still looks alive. This applies unchanged when a
pack is holding the loop's WIP slot.

The base skill's own pacing table (dynamic `/loop` with no interval) is
otherwise unchanged.

## 5. WizOs card hygiene — every card, every iteration

These are Nick's rules; the examples are the point, so they are stated in full
rather than summarized.

- **File a card the moment you notice a bug — do not fix it inline.** A defect
  spotted outside the card in hand (in shipped behaviour or in this repo's own
  tooling) goes straight to `mcp__conveyor__create_task` with `status: "Open"`,
  carrying the symptom, the evidence it is real (a log line, a command and its
  output, a store path) and the suspected cause. Mentioning it only in a PR
  body, a chat message or a summary loses it — that is exactly how a stale tag
  link sat unactioned for five days after Conveyor's own checker flagged it.
  Filing rather than fixing is also what keeps the current card's scope honest.
  A bug you introduced yourself is exempt only while you fix it inside the same
  card. When unsure whether something qualifies, file it: a cheap extra card
  beats a lost defect. Check `mcp__conveyor__list_tags` before passing any
  `tags` — an unknown name creates the card *and then* errors, so retrying
  produces a duplicate.
- **Falsify a cause before the card asserts one.** Report the symptom and the
  evidence freely; a *mechanism* has to be checked against the source first. If
  you cannot point at the line that produces the behaviour, say the cause is
  unknown. A confident-but-speculative "where to look" section is worse than
  none — it sends the next reader after something that may not exist, and a
  card filed against working code costs more than the bug it imagined. This is
  not hypothetical: `hearth-deploy build exits 0 when the build fails` was
  filed, planned, and cancelled as invalid — the observed `0` came from reading
  `$?` through a `| tail`, and two minutes of reading `run_build` would have
  killed it.
- **`create_task` silently drops parameters it does not define.** Pass
  `status: "Open"` explicitly — it defaults to `Planning`, and a card left
  there is invisible to the Open queue. The tag parameter is `tags`, not
  `tagNames`. There is no `storyPointValue` on `create_task` (it exists on
  `update_task`); points are auto-filled once the card moves beyond Planning.
  Nothing errors when you get these wrong, so verify the card afterwards with
  `mcp__conveyor__get_task` rather than assuming the call did what you asked.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
