---
name: conveyor-plan
description: Turn a raw feature or bug idea into a research-backed, immediately-buildable Conveyor card for a claudespace agent to execute later. Use when the user says "/conveyor-plan <idea>", "plan this as a conveyor card", "write this up for a claudespace agent", or wants deep planning that ends in a handoff card rather than local implementation. Runs plan-mode-quality research (codebase + prior Conveyor cards + prod logs), asks clarifying questions only when scope is genuinely ambiguous, then creates the card and moves it to Open so identification auto-fills story points, tags, icon, and agent.
---

# Conveyor Plan → Handoff Card

Produce ONE artifact: a Conveyor card whose plan a fresh claudespace agent can
execute with zero session context. Everything the executor needs must be ON the
card — it never sees this conversation.

The division of labor is fixed: **you research and recommend; Conveyor's
identification decides.** Moving the card to Open fires identification
automatically (story points, icon, agent, and tags if you set none). Never set
icon or story points yourself, and never `start_task` unless the user asks.

## Phase 0 — Resolve context

1. `mcp__conveyor__get_connection_context` (all Conveyor tools fully-qualified;
   bare names fail). No default project? `mcp__conveyor__list_projects` and
   match `githubRepoOwner/Name` to the cwd's `git remote`. Ambiguous → ask.
2. Copy project IDs exactly — a mistyped `projectId` surfaces as
   "Insufficient permissions", not "not found". Verify the ID before
   concluding you lack access.

## Phase 1 — Research (parallelize)

Scale to the idea's size; a one-file tweak needs minutes, not a survey.

- **Glossary first**: `mcp__conveyor__get_tag` on every tag the idea's text
  mentions (`@[tag:id]` deep-links or plain loaded terms — "task", "school",
  an entity name) before searching the codebase. A tag's overview + linked
  files often replace a grep sweep, and the description catches
  wrong-term-for-the-concept early (`mcp__conveyor__list_tags` shows the
  inventory with hierarchy).
- **Codebase**: use a code-graph or architecture skill if the repo provides
  one for architecture/flow questions; `rg` for exact strings. Fan out
  Explore subagents for broad sweeps.
- **Prior art**: `mcp__conveyor__search_tasks` on 2-3 keyword variants
  (`typeFilters` to include incidents/suggestions when relevant), then
  `mcp__conveyor__get_task` on the closest hits. You're looking for duplicates
  (stop and surface), related shipped work (reuse its patterns), and
  cancelled attempts (learn why before re-proposing).
- **Prod signals** (only when the feature touches live behavior):
  `mcp__conveyor__query_gcp_logs` / `mcp__conveyor__query_grafana_logs` for
  error rates, actual usage, current behavior.
- **Blast radius**: enumerate callers/consumers of every surface the plan
  touches (shared packages, DB schema, published packages, webhooks, other
  cards in flight on the same files). Unintended impact goes in the plan's
  Notes, not in your head.

## Phase 2 — Clarify (only if needed)

Ask the user only decisions that change the plan's shape — scope cuts, UX
choices, irreversible tradeoffs. Batch them in one round; never drip. Facts
the repo can answer are yours to find, not theirs.

## Phase 3 — Draft the plan

Use the plan format in [references/plan-format.md](references/plan-format.md):
Objective / Approach / Implementation Steps / Testing / Notes.

Actionability bar — every step must survive a context-free reader:

- Name exact repo-relative files and symbols, with the pattern to follow
  ("mirror `apps/api/src/services/task/methods/mutations.ts`").
- Testing = runnable commands + observable acceptance criteria.
- Notes = risks, blast radius, dependencies, and decisions already made (so
  the executor doesn't relitigate them).
- No "as discussed", no links to this chat, no TODOs the executor must
  research from scratch.

Size it: 1 SP default, 2 multi-file, 3 complex patterns/design, 5 hard. Larger
→ propose a pack (parent + `mcp__conveyor__create_subtask` children with
`mcp__conveyor__add_dependency` edges) instead of one mega-card.

Show the user title + description + plan + SP/tag recommendation before
touching Conveyor, unless they asked you to just ship it.

## Phase 4 — Create and hand off (order matters)

Identification fires the moment the card lands beyond Planning and reads task
chat for your recommendation — so chat BEFORE the status flip:

1. `mcp__conveyor__create_task` — `status: "Planning"`, concise imperative
   title, 2-4 sentence description (the board-card summary), full plan.
   Optionally `tags`: only names from `mcp__conveyor__list_tags` that clearly
   fit (unknown names are rejected; pre-set tags make identification skip tag
   assignment — when unsure, omit and let it choose).
2. `mcp__conveyor__post_to_chat` — one message: recommended SP + one-line
   rationale, tag suggestion, any executor warnings.
3. `mcp__conveyor__update_task` — `status: "Open"` (+ `risk` when the plan
   touches critical surface). This triggers identification.
4. Verify with `mcp__conveyor__get_task`: status Open, `agentId` set. SP and
   tags are NOT in the `get_task` response — confirm on the board if needed.
5. Report the card URL (`<project url>/cards/<slug>`), what identification
   filled, and that it's ready for `start_task`. Park-in-Planning instead if
   the user wants to review first; offer (don't run) `start_task`.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on the Conveyor project: the issue,
evidence, and proposed fix.
