# scry — the Scrying Orb digest

Formerly "plate". Posts to Discord as **Scrying Orb**.

Walks every Conveyor project the token can see, filters shared projects to
cards assigned to / reviewed by you, and posts a Discord digest:

1. **Waiting on you** — open Conveyor decisions, cards with no agent (design
   calls, physical tasks), verify-live / approve-PR, Notion tasks assigned to
   Nick or Collaboration (overdue → due ≤7d → priority), stale release cards
   collapsed.
2. **Projects** — one line of counts per Conveyor project.
3. **Areas** — one line per Notion area: status, next action, days quiet,
   whether agents left notes; plus the count of tasks queued for agents.

New Conveyor projects and Notion areas show up automatically.

## Format

Discord markdown headers: `# 🔮 Scrying Orb — <date>`, then `# Due soon` (the
next `maxItems` Notion tasks with a due date, sub-tasks included, soonest first
with a long date and a relative countdown; overdue ones get a ⚠; omitted when
nothing is dated), then `# General` (your Notion
tasks), then `# Projects` with one `## [<project>](<board link>) — <counts>`
per Conveyor project and the items waiting on you directly beneath it, oldest
first: open decisions, your no-agent cards, open incidents, verify-live,
approve-PR. Notion areas are still fetched into `digest.json` but not
rendered; only a `-# N tasks queued for agents` line follows the projects.
Every item title links to its Conveyor card or Notion page, PR numbers link
to the PR, and posts set `flags: 4` so Discord shows no link previews.

- `services.scry.maxItems` (default 4, exported as `SCRY_MAX_ITEMS`) caps
  each group; the rest collapse to a `-# …and N more` subtext line.
- `services.scry.runOnChange` (default true) adds `scry-on-change.service`,
  which posts once during the switch that changes the scry package (a new
  format or a dependency bump) and records it in `/var/lib/scry/last-format`.
  Reboots and switches that leave the package alone post nothing.

## Filing a task

`sudo scry-task <text>` on Hearth files one row in **Nick's Tasks** and prints
its Notion URL (hearth-tui's *Scry — file a task* calls it over ssh). Inline
tokens, anywhere in the text:

- `p0`–`p3` → Priority
- `#area` → Area relation (a Nick's Areas name; unknown names are rejected
  with the list)
- `due:2026-10-04` · `due:oct 4` · `due:fri` · `due:+3d` · `due:tomorrow`
- `@agent` / `@collab` → Type (default Nick)

Example: `sudo scry-task "Replace COLD drive p2 #hearth due:fri"`. The
integration needs Notion's *Insert content* capability to create pages.
`task.mjs` exports the parser and `createTask` for the future Discord bot.

## Notion setup (once)

1. notion.so/profile/integrations → new internal integration "plate", read +
   update content. Copy the token → `NOTION_TOKEN`.
2. Share both databases with it: **Nick's Tasks** and **Nick's Areas**
   (page ··· → Connections → plate).
3. Data-source ids default to the current DBs; override with
   `NOTION_TASKS_DS` / `NOTION_AREAS_DS` if they're ever recreated.

Without `NOTION_TOKEN` the digest still runs (Conveyor only) and says so.

## Files

| file | role |
|---|---|
| `digest.mjs` | the digest; `--post` sends to Discord |
| `task.mjs` | one Notion task from inbox-grammar text; behind `scry-task` |
| `cv.mjs` | tiny CLI over the Conveyor MCP: `node cv.mjs list`, `node cv.mjs call <tool> '<json>'` |
| `preload.cjs` | routes the MCP's websocket through `HTTPS_PROXY` when set; no-op on Hearth |
| `module.nix` | NixOS module: `services.scry` — systemd timer + `scry-now` command |
| `package.json`, `package-lock.json` | pinned deps (`@rallycry/conveyor-mcp` 5.x) |

## Local run

    cp .env.example .env    # fill in; never commit
    npm ci
    node digest.mjs         # print only
    node digest.mjs --post  # print + Discord

## Hearth (WizOs)

1. Drop this folder into the flake, e.g. `pkgs/scry/`, and import `module.nix`
   in the Hearth host config.
2. Put the five `KEY=value` lines from `.env.example` in an encrypted secret
   (age/sops, whatever `secrets/` already uses) and point
   `services.scry.environmentFile` at its decrypted path.
3. `services.scry.enable = true;` — default schedule `Sat 10:00` host-local
   (`onCalendar` to change). `Persistent = true` so a missed Saturday fires on
   next boot.
4. First `hearth-deploy build` fails on `npmDepsHash = lib.fakeHash` and prints
   the real hash; paste it in and build again.
5. On demand: `scry-now` (or `systemctl start scry.service`).

## Tuning

- `ME` in `digest.mjs` is your Conveyor user id.
- Cards are "yours" when `agentId` is null and status is Open/Planning/InProgress.
- Release cards are matched by title `/^Release \d/`.
- Per-status limit is 50 cards; raise `limit` in the `list_tasks` call if a
  project's review queue grows past that.

## Later

- Notion "Plate" DB (priority + due) merged into "Waiting on you".
- `SCRY_OUT=/var/lib/scry` to keep `digest.json` for a Go3 dashboard panel.
