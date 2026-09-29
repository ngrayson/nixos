---
name: convey-her-watch
description: Event-driven build watch for the WizOs repo — the convey-her rules without /loop or timed wakeups. Builds any claimable Open card in this session, then idles on a conveyor-wait Monitor that wakes the session the moment an implementation card enters Open (mine or unclaimed), and is switched off while a card is in hand. Run as "/convey-her-watch" (no /loop). Use when the user says "/convey-her-watch" or wants Open cards built as they appear, paired live in this session. For planning use conveyor-plan-watch; for the timer-paced loop use convey-her.
---

# Convey-Her Watch

Nick, 2026-09-28: *"instead of having a loop, can we make a command to watch
for implementation tasks going into open, similarly to how the plan watch task
works?"* — and, asked who builds: **this session**, so the work stays paired
with him live (as on the Pixel Composer resize card that day). This is the
convey-her loop with its pacing replaced by a board watch. It is the build-side
twin of `conveyor-plan-watch`, except the session does the work itself rather
than delegating it.

**Everything about how a card is worked comes from
[convey-her](../convey-her/SKILL.md)** — claiming filters, WIP=1, pack rules,
parked protocol, merging your own green PRs (amendment 1), deploy-as-
verification for Hearth/Go3 (2), ending the turn at card boundaries (3), and
card hygiene (5). Read it and follow it. Only its pacing (amendment 4 and
*Idle means a standing watch*) is replaced by the section below: no `/loop`, no
`ScheduleWakeup`, no hourly `sleep 3600` heartbeat.

## Start (and every wake)

Run one convey-her iteration: Rule B's stale-wakeup check is moot here, so
start at the Babysit tier (loop-opened PRs: merge green, name blockers), then
enumerate the Open queue with `typeFilters: ["task", "incident",
"suggestion"]` and apply the claiming filters. Then exactly one of:

- **A card is claimable** → claim it and build it (conveyor-build). The watch
  must be OFF while it is in hand (below). When it reaches ReviewDev, or
  ReviewPR with a named blocker, or is parked, go to *Card boundary*.
- **Nothing claimable** → *Idle*.

## Idle: arm the watch

One `Monitor`, `timeout_ms: 1800000`, that re-arms silently on timeout and
**exits at the first event**:

```bash
set -a; . "$HOME/.config/conveyor/env"; set +a
while true; do
  out=$(npx -y -p @rallycry/conveyor-mcp@latest conveyor-wait \
    --statuses Open --scope mine,unclaimed \
    --timeout 1700 < <(sleep 1710))
  rc=$?
  case "$out" in
    *'"reason":"event"'*)   echo "$out"; exit 0 ;;
    *'"reason":"timeout"'*) : ;;
    *) echo "conveyor-wait DIED exit=$rc: ${out: -200}"; sleep 120 ;;
  esac
done
```

Why the env source, the process-substitution stdin and the unredirected stderr
are all mandatory is in convey-her, *The board-event wake needs credentials
this repo hides, and an open stdin*. The same liveness check applies, about 25
s after arming: a live `node …/conveyor-wait` with `--statuses Open` (the
plan-watch agent's `--statuses Planning` watch does not count) AND `Watching N
card(s)` in the Monitor's output file. Never report the watch as running on
the strength of having launched it. Before arming, make sure no Open watch is
already live — never two.

Then end the turn with a one-line status: watching, and the count of
loop-opened PRs with each one's blocker (amendment 1's "say the number").

## Wakes

- **Monitor event** (`"reason":"event"`) → the watch has exited on its own.
  Run *Start*. The payload card is advisory; re-enumerate.
- **Monitor expiry notice** → if no card is in hand, run the liveness check,
  re-arm, and end the turn — no queue scan. Every 30-minute expiry doubles as
  the heartbeat that proves the watch is still alive, which is why no timed
  heartbeat is needed.
- **`DIED` line** → a broken watch: fix it (credentials, stdin, npx), do not
  fall back to timers.
- **Nick in the session** → do what he asks. A chat reply that un-parks a card
  already in Open is invisible to the watch (nothing *enters* the lane), so
  when he says he answered a card, run *Start*.

## A card in hand: the watch is off

WIP is 1, so an event mid-card can only interrupt (Nick, 2026-09-28: *"only
one card at a time … no need to keep checking now"*). The moment a card is
claimed — by an event, at *Start*, or because Nick picked it — `TaskStop` any
Open watch and confirm with the liveness check that none is left. Do not
re-arm on expiry while a card is in hand. Cards that arrive meanwhile stay Open
and are found at the next *Start*.

## Card boundary

convey-her amendment 3 still holds: end the turn between cards so Nick can
`/compact` or redirect, and say which card is next. Because there is no `/loop`
to wake the session again, pick the wake by what comes next:

- **More claimable cards are waiting** → arm one background `Bash`
  `sleep 90; echo NEXT-CARD` and end the turn. Its completion notification
  runs *Start*. This is the only timed wake in this skill, and it exists only
  to leave the compact window open.
- **Queue empty** → *Idle*.
- **The card is parked on Nick and he is here** → ask him, and wait for his
  answer rather than arming anything.

## Stopping

Nick says stop: `TaskStop` the Open watch and any `NEXT-CARD` sleep, and
confirm with `pgrep` that no `--statuses Open` watch is left. The plan-watch
agent's Planning watch is not this skill's to stop.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
