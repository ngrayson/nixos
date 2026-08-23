# Conveyor MCP Setup

Use this when Conveyor MCP tools are missing, stale, or unauthenticated.

## Preferred install path

Ask the user to open Conveyor, choose the target project, then go to
**Settings → User Settings** (`/projects/<project>/user-settings`). The
**Connect Claude Code** section generates the exact install command / MCP JSON
for their account and project — use that, not Project Settings and not the
MCP Tools reference page.

## Manual repair (Claude Code)

```bash
claude mcp remove conveyor -s local 2>/dev/null;
claude mcp add conveyor -s local \
  -e CONVEYOR_API_URL=<api-url> \
  -e CONVEYOR_USER_TOKEN=<user-token> \
  -e CONVEYOR_PROJECT_ID=<project-id> \
  -- npx -y @rallycry/conveyor-mcp@latest
```

- Run from the repo folder; `-s local` scopes the server there.
- The `remove` prefix makes token rotation idempotent.
- Keep `@latest`; avoid unbuilt local packages.
- `CONVEYOR_API_URL` and `CONVEYOR_USER_TOKEN` are required;
  `CONVEYOR_PROJECT_ID` sets the default project (omit it to pass `projectId`
  per call).
- Non-Claude MCP hosts use the same command/env/package shape in their own
  config format.

After install, restart or reload MCP servers, then verify with
`mcp__conveyor__get_connection_context` or `mcp__conveyor__list_tasks`.

## Auth failure vs permission failure

- Expired/invalid token → tools error with authentication failures; re-run
  the connect flow above to mint a fresh token.
- "Insufficient permissions" on a call that should work → check the
  `projectId` first (a typo produces this exact error), then ask a project
  admin about your role: mutations (tasks, builds, PRs) need Moderate access
  or higher.
