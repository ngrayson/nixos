---
name: conveyor-plan-watch
description: Event-driven Conveyor planning watch for the WizOs repo (formerly conveyor-plan-loop) — arms a persistent conveyor-wait Monitor that wakes the session the moment a card enters Planning, then hands each unplanned card to a fable subagent that runs conveyor-plan on it. Run with "/loop /conveyor-plan-watch" (no interval) after putting the session on a cheap model (/model sonnet or haiku); the session only pays for real wakes and only planning runs on fable. Use when the user says "/conveyor-plan-watch" or wants unplanned cards and suggestions planned automatically as they appear. For one card, in this session, use conveyor-plan.
---

# Conveyor Plan Watch

Formerly `/conveyor-plan-loop`; renamed on 2026-09-06 when it stopped polling
on a timer and started waking on Conveyor board events.

Keep the Planning column empty of unplanned cards without paying a frontier
model to discover that nothing changed. The split is deliberate:

- **Waiting runs on the session model, and only on board events.** A `/model`
  choice is the user's (it is a CLI built-in no agent can call), so the caller
  sets a cheap one before starting the watch. A persistent `conveyor-wait`
  Monitor wakes the session when a card enters Planning; the timer is a
  once-an-hour fallback, so idle wakes are rare rather than forty a day.
- **Planning runs on a fable subagent.** The `Agent` tool takes a `model`
  override, so the one step that needs research quality gets it, per card,
  and nothing else does.

This skill only selects and delegates. The card itself is planned by
the `conveyor-plan` skill, loaded inside the subagent.

## Setup (the caller does this once)

1. `/model sonnet` (or `haiku`). The loop inherits whatever the session runs.
2. `/loop /conveyor-plan-watch` — no interval. The Monitor armed in step 5
   below is the wake signal; `/loop`'s dynamic mode re-invokes this skill on
   each wake.

A skill directory created mid-session is not visible to `/` autocomplete or
the Skill tool until the CLI restarts. Restart, then start the loop.

## One iteration

1. **Read the board.** `mcp__conveyor__list_tasks` with `status: "Planning"` and
   `typeFilters: ["task", "incident", "suggestion"]`. The type filter is not
   optional: without it incidents and suggestions are silently excluded.
2. **Skip what is not yours to plan.** From the result, drop cards with
   `hasPlan: true`, and cards with an `agentId` or `githubBranch` (another
   agent has claimed them). For each card left, `mcp__conveyor__get_task`
   and read the chat: a standing note from Nick that says to stay Planning or
   park it (the wiztow.org suggestion is the long-running example) means
   skip. Do not cache this judgement across ticks — re-derive it from
   Conveyor every time, because Nick unparks cards in the chat.
3. **Delegate each remaining card, one at a time.** Call `Agent` with
   `subagent_type: "general-purpose"`, `model: "fable"`,
   `run_in_background: false` (the report is needed before the next card,
   and two planners on one board race each other), and the brief below with
   the card id and slug filled in.
4. **Relay.** The subagent's report is not shown to the user. Repeat the
   part that matters: card slug, story points and tags identification set,
   whether `agentId` is populated, and any warning the planner left in chat.
5. **Wake on board events, not on a timer.** Nick asked for this on
   2026-09-06 after watching idle ticks burn requests. On the first iteration
   (and on any later one where `TaskList` shows no such monitor running), arm
   a persistent `Monitor` around `conveyor-wait` — a CLI in
   `@rallycry/conveyor-mcp` that exits the moment a card ENTERS the filtered
   state:

   ```bash
   set -a; source "$HOME/.config/conveyor/env"; set +a
   while true; do
     out=$(npx -y -p @rallycry/conveyor-mcp@latest conveyor-wait \
       --statuses Planning --scope all --types task,incident,suggestion \
       --timeout 3500 2>/dev/null)
     rc=$?
     if [ $rc -ne 0 ]; then echo "conveyor-wait FAILED exit=$rc: $out"; sleep 120; continue; fi
     case "$out" in *'"reason":"event"'*) echo "$out" ;; esac
   done
   ```

   `--statuses Planning` is the lane new tasks, incidents and suggestions land
   in; `--scope all` because the planner plans regardless of assignee. Only
   `event` lines are echoed — timeouts re-arm silently. Sourcing
   `~/.config/conveyor/env` matters: an agent Bash shell never saw the MCP
   server's environment, and that file is where `scripts/conveyor-mcp.sh`
   reads credentials too. The event's card is advisory — run steps 1–3 again
   on wake rather than trusting it, since another agent may have got there.

   Under `/loop`, pass `noop: true` when no card was delegated and
   `noop: false` when one was. The `ScheduleWakeup` is now only a fallback
   heartbeat for a silently dead monitor: use 3600 s, never a shorter cadence.

   **Do not trust that heartbeat to fire.** In this skill's sessions every
   observed wake came from the Monitor or from Nick, never demonstrably from
   `ScheduleWakeup`, and one 3600 s wakeup sat unfired for 13 h. So on each
   wake, run `CronList` and `date`: a `(one-shot)` entry already past its
   minute did not fire — `CronDelete` it and note it in the relay, after first
   ruling out a reboot or a resumed session, which explain a stale entry
   without any bug. Then arm the heartbeat as a background `Bash`
   `sleep 3600; echo PLAN-WATCH-HEARTBEAT` alongside the `ScheduleWakeup`,
   one only, `TaskList` first. See convey-her amendment 4 for why.

## The subagent brief

Send this verbatim, substituting the two placeholders. It carries the rules
the planner cannot see because it starts cold.

```
Plan Conveyor card <CARD_ID> (slug <CARD_SLUG>) in the WizOs repo at
/home/wiz/.config/nixos. Load the `conveyor-plan` skill with the Skill tool
and follow it for this existing card — write the plan onto this card, never
create a new one.

Before writing anything, `mcp__conveyor__get_task` the card again and stop
if it now has an agentId, a githubBranch, a plan, or a chat message claiming
it: another agent got there first. Report that instead of overwriting.
Concurrent local-loop executors claim cards on this board within minutes.

Order of operations is fixed: update_task with title/description/plan while
still in Planning, then post_to_chat with the story-point recommendation,
one-line rationale, tag suggestion and any executor warnings, then
update_task status Open (that triggers identification, which reads the
chat), then get_task to confirm Open and an agentId. Never call start_task.

Research rules for this repo: confirm claims against the live machine or the
source rather than from memory (run the command, read the file, cite the
line). Every plan step names exact repo-relative files and symbols. Testing
means runnable commands plus what a person observes — a build passing is a
gate, not verification. Nick runs os-rebuild switch himself; hearth-deploy
and go3-deploy are the agent's to run. Personal data — coordinates, secret
URLs, tokens — never goes into card text, chat, or a commit. A bug noticed
along the way is filed as its own card with mcp__conveyor__create_task, not
fixed or merely mentioned.

Report back in under 200 words: card URL, recommended SP and tags, what
identification filled in, and anything the executor must know that is not
already on the card.
```

## Ground rules

- **Conveyor is the state store.** This session spans days and gets
  compacted; nothing about which cards are parked or planned survives except
  what the board says.
- **All Conveyor tools fully-qualified** (`mcp__conveyor__list_tasks`; bare
  names fail).
- **Never plan in the session itself while the watch runs on a cheap model.**
  If the user asks for a plan directly, they can `/model` up and use
  `/conveyor-plan`; this skill's job is to keep the session cheap.
- **One planner at a time.** Serial delegation is a feature: two subagents
  on the same board can both pass the "not yet claimed" check.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
