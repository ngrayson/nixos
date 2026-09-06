---
name: conveyor-plan-loop
description: Cheap-poll, expensive-plan Conveyor planning loop for the WizOs repo — one invocation polls the Planning column on the session model and hands each unplanned card to a fable subagent that runs conveyor-plan on it. Run continuously with "/loop /conveyor-plan-loop" (no interval) after putting the session on a cheap model (/model sonnet or haiku); idle ticks then cost the cheap model and only real planning runs on fable. Use when the user says "/conveyor-plan-loop" or wants unplanned cards and suggestions planned automatically without paying the frontier model for idle polling. For one card, in this session, use conveyor-plan.
---

# Conveyor Plan Loop

Keep the Planning column empty of unplanned cards without paying a frontier
model to discover that nothing changed. The split is deliberate:

- **Polling runs on the session model.** A `/model` choice is the user's (it
  is a CLI built-in no agent can call), so the caller sets a cheap one before
  starting the loop. Roughly forty idle ticks a day is the normal rhythm.
- **Planning runs on a fable subagent.** The `Agent` tool takes a `model`
  override, so the one step that needs research quality gets it, per card,
  and nothing else does.

This skill only selects and delegates. The card itself is planned by
the `conveyor-plan` skill, loaded inside the subagent.

## Setup (the caller does this once)

1. `/model sonnet` (or `haiku`). The loop inherits whatever the session runs.
2. `/loop /conveyor-plan-loop` — no interval; `/loop`'s dynamic mode paces it
   and re-invokes this skill each tick.

A skill directory created mid-session is not visible to `/` autocomplete or
the Skill tool until the CLI restarts. Restart, then start the loop.

## One iteration

1. **Poll.** `mcp__conveyor__list_tasks` with `status: "Planning"` and
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
5. **Pace.** Under `/loop`, pass `noop: true` when no card was delegated and
   `noop: false` when one was. 1500 s is the working cadence; widen to 1800 s
   after a few quiet ticks. There is no board event to arm a Monitor on for
   the Planning column, so time is the only wake signal.

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
- **Never plan in the session itself while the loop runs on a cheap model.**
  If the user asks for a plan directly, they can `/model` up and use
  `/conveyor-plan`; this skill's job is to keep the session cheap.
- **One planner at a time.** Serial delegation is a feature: two subagents
  on the same board can both pass the "not yet claimed" check.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
