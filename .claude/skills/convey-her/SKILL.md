---
name: convey-her
description: Nick's preset over conveyor-local-loop for the WizOs repo — same serial local card loop, but with three amendments: a loop-opened PR is merged to dev in the iteration that finds it green (at most one may stay open, and only with a named blocker), a card touching hosts/Hearth or hosts/Go3 is verified by actually running hearth-deploy switch / go3-deploy switch rather than a build, and the loop ends its turn at card boundaries so the user has a window to /compact. Use when the user says "/convey-her". For the unmodified loop use conveyor-local-loop; for exactly one card, conveyor-local-task.
---

# Convey-Her

Follow [conveyor-local-loop](../conveyor-local-loop/SKILL.md) exactly — the
same iteration order, claiming filters, WIP=1, pack rules, parked protocol and
pacing table — with the three amendments below.

Two things people expect to find here are **already the base skill's default**
and are deliberately not restated: merging your own passing PRs into `dev`
(a Ground rule), and verify-or-park-with-a-question (Execute-and-finish step 4
plus the Parked protocol). A merged PR moves its card to ReviewDev on its own;
you never set that status by hand.

## 1. Finish a PR before you start another card

This exists because the failure it prevents is the observed one: PRs pile up
in ReviewPR while the loop keeps claiming new cards, and nothing reaches
`dev`.

The base skill's Execute-and-finish step 6 says to confirm CI started and let
"later iterations babysit". **That is overridden here.** It is the mechanism
by which PRs accumulate — every iteration defers the merge to the next one.

- **WIP=1 applies to pull requests, not just cards.** At most one
  loop-opened PR may be open at the end of an iteration.
- **Green means merge now, in the same iteration that finds it green.** Wait
  for checks with a bounded loop that reports on both outcomes, then merge.
  In this repo the wait is short: there are no workflows under
  `.github/workflows/`, so the only check is GitGuardian and it reports in
  seconds.
- **The Babysit tier is a gate, not a courtesy.** If a loop-opened PR is
  open when an iteration starts, resolve it — merge it, fix its CI, or park
  it — *before* claiming anything new.
- **An open PR needs a named blocker**, recorded in the card chat. Exactly
  three qualify: red CI, an unresolved review comment, or a verification only
  the user can perform (they must type a password, look at a screen, or
  approve a risky live action). "A later iteration will get to it" is not a
  blocker; it is the bug.
- **Say the number out loud.** Every iteration summary states how many
  loop-opened PRs are open and, for each, which of those three reasons keeps
  it open. A count that only grows is the signal to stop claiming and drain.

Unchanged from the base skill: never merge someone else's PR, and a pack's
finale PR into `dev` is still the user's call.

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

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
