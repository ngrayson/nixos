# plate — "what's on my plate" digest

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
| `cv.mjs` | tiny CLI over the Conveyor MCP: `node cv.mjs list`, `node cv.mjs call <tool> '<json>'` |
| `preload.cjs` | routes the MCP's websocket through `HTTPS_PROXY` when set; no-op on Hearth |
| `module.nix` | NixOS module: `services.plate` — systemd timer + `plate-now` command |
| `package.json`, `package-lock.json` | pinned deps (`@rallycry/conveyor-mcp` 5.x) |

## Local run

    cp .env.example .env    # fill in; never commit
    npm ci
    node digest.mjs         # print only
    node digest.mjs --post  # print + Discord

## Hearth (WizOs)

1. Drop this folder into the flake, e.g. `pkgs/plate/`, and import `module.nix`
   in the Hearth host config.
2. Put the five `KEY=value` lines from `.env.example` in an encrypted secret
   (age/sops, whatever `secrets/` already uses) and point
   `services.plate.environmentFile` at its decrypted path.
3. `services.plate.enable = true;` — default schedule `Sat 10:00` host-local
   (`onCalendar` to change). `Persistent = true` so a missed Saturday fires on
   next boot.
4. First `hearth-deploy build` fails on `npmDepsHash = lib.fakeHash` and prints
   the real hash; paste it in and build again.
5. On demand: `plate-now` (or `systemctl start plate.service`).

## Tuning

- `ME` in `digest.mjs` is your Conveyor user id.
- Cards are "yours" when `agentId` is null and status is Open/Planning/InProgress.
- Release cards are matched by title `/^Release \d/`.
- Per-status limit is 50 cards; raise `limit` in the `list_tasks` call if a
  project's review queue grows past that.

## Later

- Notion "Plate" DB (priority + due) merged into "Waiting on you".
- `PLATE_OUT=/var/lib/plate` to keep `digest.json` for a Go3 dashboard panel.
