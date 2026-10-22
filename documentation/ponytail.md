# Ponytail in Claude Code

[Ponytail](https://github.com/DietrichGebert/ponytail) (MIT) is a Claude Code
plugin that pushes every agent toward the smallest change that fully solves
the task: no unrequested abstractions, the standard library first, and never
cutting validation, error handling or security to get there. It ships six
skills (`ponytail`, `ponytail-review`, `ponytail-audit`, `ponytail-debt`,
`ponytail-gain`, `ponytail-help`) and three Node hooks (`SessionStart`,
`SubagentStart`, `UserPromptSubmit`) that inject its ruleset into each session
and each subagent. It adds about 640 tokens to every session.

## Where it lives

It is installed at **user scope**, so it is on in every repo on the machine,
in the terminal CLI and in the VS Code Claude Code panel (both read
`~/.claude/settings.json`). It is not Nix-declared: `~/.claude/settings.json`
is mutable and user-owned (see the end of `home/programs/claude-skills.nix`),
the same standing as the gitkraken plugin and the VS Code extension. No repo
carries a `.claude/settings.json` entry or a copy of ponytail's own
`AGENTS.md` for it.

Install on a new machine (Theseus included), once:

```sh
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail
claude plugin list        # ponytail@ponytail … Scope: user … enabled
```

Auto-update is off (third-party marketplace default) and stays off, so a
session's behaviour cannot change under the build loop. Update deliberately
with `claude plugin update ponytail@ponytail`. Remove with
`claude plugin uninstall ponytail@ponytail`, then
`claude plugin marketplace remove ponytail`.

Ponytail writes small state files outside any repo:
`~/.claude/.ponytail-active` (the current level),
`~/.claude/.ponytail-statusline-nudged` (its one-time statusline offer was
made), and `~/.config/ponytail/` (a persisted default level, and the band's
CSVs). The statusline offer was consumed during the install check on Tawa;
to get the badge anyway, copy the plugin's `hooks/ponytail-statusline.sh`
and point `statusLine` at it yourself. Agents never edit `statusLine`.

## When it is on

- **`full`, in every session and every repo, by default.** That includes the
  convey-her build loop and the plan watch.
- `/ponytail lite` is fine for a documentation-only or planning session if
  its reply compression gets in the way. `/ponytail off` lasts for that
  session only; never persist it in `~/.config/ponytail/config.json`.
- **AGENTS.md wins any conflict.** Ponytail's "skip the test" never
  overrides a suite this repo already runs (`tests/hypr-sunset/run.sh` under
  `nix flake check`), and "standard library first" here means the NixOS or
  Home Manager option before a script.
- Run `/ponytail-review branch` (or `uncommitted`) before opening a card's PR
  with `mcp__conveyor__create_pull_request`.
- `/ponytail-audit` runs only when a card asks for it. Deferred shortcuts are
  marked with `shortcut:` comments, and `/ponytail-debt` lists them.

## Where it does not run

- **Conveyor cloud sessions and pods.** They do not load plugins installed on
  this machine, so Under the Stars builds in the Lima VM are unaffected.
- **The band** (the cost and token strip) needs Claude Code 2.1.290 or later.
  The host CLI is the nixpkgs `claude-code` from the locked input (2.1.223 on
  2026-10-22), so skills and hooks work and the band is absent until that
  input is bumped. The band never shows in the VS Code panel either way.
