---
name: conveyor-workflows
description: How to work with Conveyor from any repo it manages — connect or repair the Conveyor MCP, create and plan cards, decide task vs suggestion vs incident, build packs, start or monitor agent builds, open PRs the non-duplicating way, and review completed work. Use when asked "how do I use conveyor", "create a card", "file this in conveyor", "start a build", "review this conveyor task", when Conveyor MCP tools are missing or erroring, or when a PR was auto-closed or a duplicate card appeared.
---

# Conveyor Workflows

Conveyor is the task source of truth for this repo. Cards must let the next
agent or human pick up cold: search before creating, keep task chat current,
and let Conveyor's own automation do the linking.

## Connect and resolve context

- All Conveyor tools are called fully-qualified (`mcp__conveyor__get_task`);
  bare names fail with "No such tool available".
- Start with `mcp__conveyor__get_connection_context`. No default project?
  `mcp__conveyor__list_projects` and match `githubRepoOwner/Name` against the
  cwd's `git remote`. Conveyor MCP is multi-project — pass `projectId`
  explicitly when working across projects.
- **A mistyped `projectId` surfaces as "Insufficient permissions", not "not
  found".** Re-check the ID character-for-character before concluding you lack
  access.
- MCP missing, stale, or unauthenticated → [references/mcp-setup.md](references/mcp-setup.md).
- Two MCP surfaces exist with different arg shapes: the in-pod agent tools
  (`post_to_chat` takes `message`) and the standalone `@rallycry/conveyor-mcp`
  server for external clients (`content`, plus `taskId`/`comment` variants).
  You are on the in-pod surface when Conveyor provisioned your workspace;
  external when the MCP was configured by hand. Each accepts the other's
  field name as an alias where possible, but read the tool's schema — don't
  guess across surfaces.

## Cards: create, classify, plan

- **Search first**: `mcp__conveyor__search_tasks` on 2-3 keyword variants
  (`typeFilters` to include incidents/suggestions); use
  `mcp__conveyor__list_tasks` when filtering by status/assignee instead of
  text (results are priority-ordered). A card may already exist — attach to
  it (post your context to its chat) rather than forking a duplicate.
- **Classify**: buildable work → `mcp__conveyor__create_task`; an
  idea/improvement you are NOT committing to build →
  `mcp__conveyor__create_suggestion`; incidents (production breakage) are
  filed by monitoring and users through Conveyor's incident tooling — you
  will usually *work* incident cards, not create them.
- **Mechanics**: `create_task` takes the title, description, `plan`
  (markdown), and optional status/tags; cards start in `Planning`. Every
  status change you make goes through `mcp__conveyor__update_task`
  (`status: "Open"` / `"InProgress"` / `"Cancelled"`, plus plan/description
  edits). Review-side transitions are NOT yours — see the PR section.
- **Description vs plan**: the description is capped at 255 chars — 1-2 plain
  sentences a non-engineer can read. All technical detail goes in the plan.
- **Plan quality bar**: a context-free reader must be able to execute — exact
  repo-relative files and symbols, runnable testing commands, decisions
  already made recorded in Notes. Format and sizing:
  [../conveyor-plan/references/plan-format.md](../conveyor-plan/references/plan-format.md).
  For research-backed planning that ends in a handoff card, use the
  `conveyor-plan` skill.
- **One card per deliverable/PR** (mirror packs below are the documented
  exception). Multi-PR work becomes a pack: children via
  `mcp__conveyor__create_subtask` (new children) or
  `mcp__conveyor__set_task_parent` (adopt an existing card into the pack, or
  detach one with `parentTaskId: null`), with
  `mcp__conveyor__add_dependency` edges. Orchestration packs run children as
  their own builds/PRs; mirror packs (children created with
  `followParentStatus: true` on `create_subtask`) document already-done work
  shipping in ONE PR on the parent. Don't pack below
  genuinely-multiple-independent-pieces scope.
- **Identification is Conveyor's job**: moving a card beyond Planning
  (`update_task` → `status: "Open"`) auto-fills story points, icon, agent,
  and tags — for pack children too. Post your SP/tag recommendation to chat
  BEFORE the flip; never set icon or points yourself.

## Tags are the project glossary

Tags are the shared vocabulary humans and agents align on, not just board
labels. Each tag carries a `description` (≤255 — the summary), an `overview`
(the full markdown spec: philosophy, mechanics, invariants), `contextPaths`
(where the code/rules live), and parent/child tags (a sub-type taxonomy).

- **Read**: `mcp__conveyor__list_tags` for the inventory (names, descriptions,
  hierarchy, `contextPaths`, `hasOverview`) — the context links ship inline, so
  auditing what the glossary wires up takes one call, not one per tag;
  `mcp__conveyor__get_tag` (id or exact name) for one term's full entry —
  overview, linked files, hierarchy, and recent revisions with their reasons. When a card or chat message deep-links a term
  (`@[tag:<id>]` — the web composer offers this when you type a tag name),
  `get_tag` is how you pull its full context. To deep-link a term yourself,
  write `@[tag:<name>]` with the tag's exact name — chat posts and card
  plans/descriptions are canonicalized to the id token at write time, so you
  never need the id. An unknown name stays plain text.
- **Write**: `mcp__conveyor__manage_tags` (Moderate+). Whenever your work
  changes how a tagged system behaves, update that tag's `overview` and pass a
  one-line `reason` — it lands in the tag's revision history (in-pod agents
  get their current card auto-stamped too), so the team sees why the glossary
  changed. Any loaded term worth a definition deserves a tag.
- **The PR nudge**: `create_pull_request` may append a "Touched glossary
  areas" line — your diff's files matched against tag `contextPaths`. Treat it
  as a checklist prompt, not an order: update a listed tag's
  overview/description only when your change altered what the term means, add
  the tag to the card only when the work is genuinely about that area, and
  skip freely otherwise. Never bulk-assign tags from path matches alone.

## Execute

- **Status reflects reality**: claiming a card = `update_task` →
  `status: "InProgress"` plus a chat note saying who/where is working it.
  Never hand-move a card to `ReviewPR` or set its PR link — that transition
  belongs to `create_pull_request` / the PR sync.
- **Cloud or local**: `mcp__conveyor__start_task` boots a cloud agent
  environment for an Open card (that agent run is the card's "build" —
  `mcp__conveyor__get_build_status` reports it). To execute cards on the
  local machine instead, use the `conveyor-local-loop` skill. Don't do both —
  a started task's agent will duplicate local work. That loop idles on
  `conveyor-wait`, a CLI in `@rallycry/conveyor-mcp` that blocks until a card
  becomes claimable, so an idle loop wakes on a board event instead of a timer.
- **Reserved-branch trap**: a card with an assigned agent may have a reserved
  `githubBranch`. Check `get_task` before pushing: if set, push to THAT
  branch; a PR from any other branch gets auto-closed and unlinked.
- **Chat is the log**: post at real milestones — claim, blocking discovery,
  decisions, gates green, PR — not play-by-play. Findings (root causes, dead
  ends, verification results) belong in task chat, not just your session.
- **Files**: `mcp__conveyor__upload_attachment` hosts images/video/files on
  the card; the returned URL is reusable in PR bodies. Attach visual evidence
  for UI changes before opening the PR.
- **Found-but-not-fixed** → a follow-up card with enough context to execute
  cold, not a TODO in chat.

## Open the PR — two paths, pick exactly ONE

| Situation | Path |
| --- | --- |
| A card exists (found or created) | `mcp__conveyor__create_pull_request` — one call opens the PR, links the card, moves it to ReviewPR. Pass `head:` if the card has no branch. |
| No card exists | Open the PR with your git host's normal tooling and STOP — Conveyor's PR sync spawns and links a card itself. |

Card linking belongs to exactly one actor, never you by hand. Mixing paths is
the known failure mode: a hand-moved card linked to nothing plus a
sync-spawned duplicate.

## Monitor and review

- Monitor with `mcp__conveyor__get_task`, `mcp__conveyor__read_task_chat`,
  and `mcp__conveyor__get_build_status`.
- Reviewing a ReviewPR card: inspect the diff and task chat; approve with
  `mcp__conveyor__approve_task` only if the PR implements the plan and
  follows repo patterns — it advances the card through the review pipeline
  (and, per project settings, approves/merges the PR). Otherwise
  `mcp__conveyor__request_changes` with specific feedback, which returns the
  card to the builder. Manual test checklists ride
  `mcp__conveyor__set_manual_tests` and surface for human sign-off at the
  review stage.
- Don't approve or merge your own PRs unless the project's policy explicitly
  allows it.
- Remote workspace access (SSH/preview) goes through
  `mcp__conveyor__workspace_start_tunnel` / `workspace_stop_tunnel` — one
  canonical tunnel per task, torn down when done.

## Reliability gotchas

- **A mutating call that errors may have already landed.** "Session not
  found" / timeout on `create_*`, `post_*`, `approve_*`, merge → check the
  effect (`read_task_chat`, `get_task`, the PR) before re-firing; cap
  identical retries at one. Blind re-fires double-post and double-approve.
- **Git ground truth is remote-first** in agent pods and shared workspaces:
  on a surprising conflict, failed push, or dirty tree, run `git ls-remote
  origin <branch>` and `git merge-base --is-ancestor` before rebuilding
  anything locally — platform autosync may have already pushed for you, and a
  dirty tree may belong to a concurrent session.

## Improve This Skill

If this skill was insufficient or slowed the work down, file it with
`mcp__conveyor__create_suggestion` on your current project: the issue,
evidence, and proposed fix.
