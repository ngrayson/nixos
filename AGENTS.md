# Agent rules

The rules for any coding agent working in this repo. Formerly split between
this file and `.cursor/rules/*.mdc` (Cursor-only, glob-scoped); this file is
now the single source and applies for the whole session regardless of which
files you touch.

Canonical tree: `~/.config/nixos` (flake `github:ngrayson/nixos`). Hosts:
**Theseus** (Framework laptop), **Tawa** (desktop), **Hearth** (Surface media
host), **Go3** (Surface Go 3 kiosk), **Gcp**.

## Agent workflow

- **`main` is stable, `dev` is unstable.** New hosts stay on `main`. Daily
  work happens on `dev` until you promote. Never `git switch` the user's
  checkout unless they ask.
- `os-rebuild` uses the **active checkout** and must tell the user which
  branch/lane they are on. It does not pick a branch. `hearth-deploy`
  **builds** the checkout; **switch/boot** default to `origin/deploy/hearth`
  unless `--from-checkout`.
- Edit files here; do not duplicate config under Stellarium `projects/`.
- Activate **this machine** with `os-rebuild switch` (alias). Never run
  `sudo` yourself: give the user the command plus a check (`readlink
  /run/current-system`, or `qs-nixos-status`).
- **Do not commandeer the user's live session without asking.** Moving the
  mouse cursor, sending synthetic input, taking screenshots, locking or
  blanking the screen, and restarting the bar or compositor all seize shared
  hardware: the machine you run on is usually the machine the user is sitting
  at, and none of those is a scoped, undoable edit. Prefer verification that
  stays inside the repo; when only a live check will do, say what you are
  about to do and ask first. Restore whatever you took over — cursor
  position, monitor power, anything left on screen — and crop screenshots to
  the region under test rather than grabbing whole outputs.
- **Hearth** is built on Tawa and activated with `hearth-deploy`
  (`scripts/hearth-deploy.sh`) from **Tawa's current branch**. Do not
  `os-rebuild switch --host Hearth` on Tawa, and do not routine-switch Hearth
  on-box. Exception: the first on-box Hearth switch after
  `hosts/Hearth/remote-access.nix` trust/sudo changes.
- Git flake: **untracked files are invisible** to the build. `git add`
  anything Nix must see (new host fragments, QML, scripts).
- Never commit plaintext secrets or PII. Encrypted files under secrets/ are
  fine; private age keys stay in Bitwarden. See [Secrets](#secrets) below.
- Commit **after** a successful rebuild, not before. `os-rebuild` records
  `~/.cache/qs-nixos-status/applied.json` so the bar wrench does not
  false-fire (dirty-tree hash ≠ committed hash).
- One logical change per switch. Before asking the user to activate, run
  `os-rebuild build` (this host) or `hearth-deploy build` (Hearth) and only
  ask if it succeeds; then give them `os-rebuild switch` / `hearth-deploy
  switch` plus a check (`readlink /run/current-system` or `qs-nixos-status`).
  Hardware / kernel / disk / Hearth headless flip: the user runs
  `dry-activate` then `boot`, then reboots.
- **Check the command before trusting its answer.** A wrong-but-plausible
  result is worse than an error, and these three produce them silently:
  - Never read `$?` through a pipe — a pipeline reports the **last** command's
    status, so `deploy.sh build | tail` returns `tail`'s. Redirect to a file
    and check, or use `${PIPESTATUS[0]}`.
  - Guard a derived path before using it (`[ -d "$X" ] || exit 1`). An unset
    variable expands to nothing, so `"$X/etc/..."` silently becomes `/etc/...`
    and you inspect this machine instead of the one you meant.
  - Ask the authoritative source, do not infer: `nix build --print-out-paths`,
    not `ls -dt` globbing `/nix/store` (which happily returns a `.drv`);
    `systemctl show -p <prop> --value`, not grepping log text.
- **Print only derived properties of a secret, never its contents** — byte
  count, line count, `grep -c`, a match/no-match boolean. "Show me the first
  line to check the header" leaks the whole key when the file turns out to be
  one line.
- Do not `nix flake update` unless asked. Do not copy hardware UUIDs between
  hosts.

```bash
# ✅ live QML without a rebuild
quickshell -d -p ~/.config/nixos/quickshell
# ✅ persist (user runs)
os-rebuild switch
```

## Hearth deploy

`scripts/hearth-deploy.sh`, exposed as `hearth-deploy` via `~/.local/bin`
(and a zsh alias). Daily loop for host **Hearth**: evaluate and build on
Tawa, copy + activate over OpenSSH. If a shell says command-not-found, run
`bash ~/.config/nixos/scripts/hearth-deploy.sh` — the alias only exists after
a Tawa Home Manager switch.

- Run it on **Tawa** (or Theseus). Refuse activation if `hostname` is
  `Hearth`.
- Before asking the user to `hearth-deploy switch` or `boot`, run
  `hearth-deploy build` (same no-sudo gate as `os-rebuild build` on this
  host) and only ask if it succeeds.
- `build` / `health` / `doctor` use the builder checkout and must print its
  branch and lane. `boot` / `dry-activate` default to `origin/deploy/hearth`.
  Interactive `switch` asks: current checkout, pin `origin/deploy/hearth`
  (hearthDeploy), or fast-forward that pin to `origin/dev` then activate it.
  `--yes` keeps the pin. `--from-checkout` skips the menu. Print both the pin
  and the checkout.
- Path filter: refuse `origin/main...<pin>` if it touches `common/`, `home/`,
  `profiles/`, `flake.nix`, or `flake.lock`, unless
  `HEARTH_DEPLOY_ALLOW_SHARED=1` or trailer `Hearth-Deploy: allow-shared`.
- The fix for that refusal is **promotion, not the override**: activate on
  Tawa, merge `dev` → `main` (a merge, never a squash — the three-dot range
  needs `dev` reachable from `main`), fast-forward `deploy/hearth`, then
  deploy clean. Shared paths also feed Tawa/Theseus, so Hearth must not be
  the first machine to prove them. Full order in `BRANCHING.md`. When the
  exception is deliberate, prefer the trailer over the env var so `git log`
  carries the reason.
- Command: `nixos-rebuild <switch|boot|dry-activate> --flake <pin-or-checkout>#Hearth
  --target-host hearth --use-remote-sudo`. deploy-rs is not the activator
  (`boot` is unsupported). Omit `--build-host` so the build stays local.
  `hearth` is the SSH Host alias (`~/.ssh/config.d/hearth`); do not pass the
  raw MagicDNS name or host-key checks fail.
- Talk to `sshd` on port 22 (MagicDNS / tailnet), not Tailscale SSH.
- Do not `os-rebuild switch --host Hearth` on Tawa (activates the wrong
  machine). Do not write Tawa's `applied.json` after a Hearth deploy.
- After a successful `switch`, run `scripts/hearth-healthcheck.sh` on Hearth
  over OpenSSH (`sshd`, Tailscale `Self.Online`, `jellyfin`, `/mnt/cold`
  UUID, every Jellyfin library `.mblink` resolving to a real directory,
  Jellyfin `/health`, `caddy`, `home.wizt.org/status.json`). Non-zero check
  fails `hearth-deploy`. On that health-fail path only,
  `scripts/hearth-notify.sh` posts to Discord Hearthchime if
  `/run/secrets/hearth-discord-webhook` (or `HEARTH_NOTIFY_WEBHOOK_FILE`)
  exists. Notify is fail-open: missing file or curl error must not change
  the deploy exit code. No Discord on build, dry-activate, successful
  switch, boot, or rebuild failure. `hearth-deploy health` runs the same
  probes without a rebuild. After `boot`, skip the live check until Hearth
  reboots. Do not auto-rollback.
- Jellyfin library paths are **server state under
  `/var/lib/jellyfin/root/default/<Lib>/`**, not `hosts/Hearth/jellyfin.nix`.
  Renaming a media directory or a tmpfiles rule does not move them; edit
  `<Lib>.mblink` *and* that library's `options.xml`, then restart `jellyfin`
  and rescan. Write the mblink with `printf`, never `echo` — Jellyfin does
  not trim the trailing newline, and COLD is mounted case-sensitively, so a
  stray newline and a wrong capital both surface as "inaccessible or empty,
  skipping" with the tracks unread. The health check fails the deploy on all
  three mistakes.
- After a successful `switch` whose health check passed, dunst on Hearth
  gets a notification if wiz is in a graphical session and at least one
  output is DPMS-on.
- Kernel, initrd, disk, or the H4 headless flip: `boot`, then reboot Hearth.
  `test` is not a rollback.
- One-time Hearth settings live in `hosts/Hearth/remote-access.nix`
  (`trusted-users`, passwordless wheel sudo). Those need one on-box Hearth
  `os-rebuild switch` before the first remote deploy.

Scope: `scripts/hearth-deploy.sh`, `scripts/hearth-healthcheck.sh`,
`hosts/Hearth/**`, `home/programs/ssh-hearth.nix`.

## NixOS host expansion

Safely adding or modifying NixOS hosts, shared modules, and profiles.

- Treat `flake.nix` and `flake.lock` as the only source of external inputs;
  do not add channel paths, `builtins.fetchTarball`, or unlocked
  `builtins.getFlake` calls.
- Add a host under `hosts/<Name>/` with `configuration.nix` and `host.nix`.
  Tawa/Theseus/Hearth also need that machine's generated
  `hardware-configuration.nix`. **Gcp has none** — the GCE image module owns
  disk/boot; `scripts/gcp/` is the image path.
- Add the case-sensitive host output to `nixosConfigurations` in
  `flake.nix`; put `nixos-hardware` modules in its module list.
- Never copy hardware UUIDs, LUKS mappings, swap devices, or resume offsets
  between machines.
- Set `system.stateVersion` once in `host.nix` to the machine's initial
  install release; do not bump it during upgrades.
- Put server-safe defaults in `common/base.nix`. Tawa/Theseus import
  `profiles/workstation.nix` (display managers, gaming, VPN, Home Manager).
  Do not grow `common/base.nix` with those. Hearth uses
  `profiles/media-desktop.nix`; Gcp uses `profiles/server.nix`.
  `common/system.nix` is a deprecated re-export of the workstation profile.
- Validate a host in this order: `nix flake check --no-build`, `os-rebuild
  build --host <Name>`, then `os-rebuild dry-activate --host <Name>`.
- Prefer `boot` for kernel, initrd, disk, LUKS, or hibernation changes. Ask
  the user before rebooting or restarting their graphical session.
- Do not activate a host whose placeholder hardware configuration still
  contains all-zero UUIDs.

Scope: `flake.nix`, `hosts/**/*.nix`, `common/**/*.nix`, `profiles/**/*.nix`.

## os-rebuild

`documentation/nixos-framework-setup/os-rebuild.sh` (zsh alias
`os-rebuild`). Full Nix log stays in `~/.cache/os-rebuild/`; the terminal is
a **readable summary**.

- Filter Slippi `trace:`, crane eval warnings, and `warning: Git tree is
  dirty`. Wrap to `$COLUMNS`; shorten `/nix/store/<hash>` to 7 chars + `…`.
- After a successful `switch`/`test`, print `nix store diff-closures` vs the
  previous generation (that is the impact).
- Print the active git branch and lane (`main` = stable, `dev` = unstable)
  in the Target block. Do not switch branches.
- Before asking the user to `switch`, run `os-rebuild build` (no sudo).
  `dry-activate` / `switch` / `boot` need sudo, so those commands go to the
  user.
- Commit dirty files **only after** `nixos-rebuild` succeeds (`--no-commit`
  to skip), on the current branch. Then write
  `~/.cache/qs-nixos-status/applied.json` and bump the bar
  (`qs-nixos-status`).
- Untracked flake inputs: prompt to `git add` them (default yes). `--yes`
  stages without asking; declining still refuses the build.
- Skip `nix flake check` on `switch`; use `os-rebuild check` when validation
  of all outputs is the goal.
- Wrench on the bar: flake-relevant dirty paths, or HEAD/generation ≠
  applied stamp. Docs-only dirt does not count.

Scope: `documentation/nixos-framework-setup/os-rebuild.sh`.

## Quickshell

Bar source: `quickshell/shell.qml`. Colors come from `Theme.qml` /
`~/.config/quickshell/theme.json` (home/theme). Icons: `IosevkaTermSlab NF`
via `String.fromCodePoint(0xF…)`, never paste PUA glyphs (editors mangle
them).

**Layout (right side):** media pill | tray pill | **one status cluster** |
clock. Cluster order: updates (rebuild wrench, flake-input count, origin
commits to pull), qs-reload (only if `quickshell/*.qml` changed since last
start), wifi, bluetooth, screen-warmth (only once the scheduler has a location
fix), brightness, battery, resize-move (only while that
mode is on), keep-awake, mic, volume, power. Keep click/scroll/tooltip behavior per icon; do not split those back
into separate pills. Network-online status polls `git fetch` about every 10
minutes (`qs-nixos-status --online`); left-click on origin-behind is
`qs-nixos-term pull`.

**OSD:** volume and brightness (incl. keyboard backlight) use the centered
modal (`showOsd`), not a percent on the pill. Audio IPC:
`qs-quickshell-ipc call audio notifyChange` (follows the live bar after
reload).

**Screen warmth (f.lux replacement):** `home/services/hyprsunset.nix`.
hyprsunset is the gamma backend and **must be the only colour-transform-matrix
writer** — a second writer (gammastep, wlsunset, a stray `hyprctl hyprsunset`
call) makes the screen flicker between them. gammastep is not an option
regardless: wlr-gamma is dead on Tawa's outputs ("Zero outputs support gamma
adjustment", see PR #173/#174).

hyprsunset runs with `--identity` and **no** `profile` entries; all timing is
`hypr-sunset-apply`, a 30s idempotent tick that recomputes the target from the
clock and pushes only on change. That shape is what buys smoothing, geolocation
and suspend-recovery — hyprsunset's built-in profiles are fixed wall-clock
cutovers that cannot ramp and do not re-apply after a resume. The ramp is a
smoothstep over the `transitionMin` window ending at sunrise/sunset; sun times
come from `sunwait`, coordinates once from geoclue into
`$XDG_RUNTIME_DIR/hypr-sunset/location.json` (**personal data — never commit
them**; a hand-written `~/.config/hypr-sunset/location.json` overrides and
skips geoclue entirely).

Discrete changes — toggle, pause, a settings edit — ease over
`discreteRampSec` (default 10s) via `hypr-sunset-apply --ramp`, using the same
smoothstep, one step every `rampStepMs` (default 500ms). **Duration and step
interval are deliberately separate settings**: duration is how the ease feels,
interval is what it costs, and welding them together (the original
`steps = sec * 4`) meant a longer ease could only be bought with more pushes
per second. The ramp also skips any push whose eased integer has not moved —
measured 10 of 20 gamma pushes in a full sweep are byte-identical, and
hyprsunset does not skip them for you. Two rules make that safe, and both were bugs before they were
rules: a ramp registers a PID in `ramp.pid` and the 30s tick **skips entirely
while one is live** (the tick's value IS the ramp's endpoint, so a tick landing
mid-ramp snaps to the end) — but the lock is honoured only when `kill -0`
confirms the PID, because a stale file would otherwise freeze the screen at one
colour forever. The ramp's `TERM`/`INT` traps must `exit`; a trap that only
cleans up leaves the loop running, so the disarm is swallowed and two ramps
interleave. `publish_state` writes a per-PID temp file for the same reason.

The bar reads `$XDG_RUNTIME_DIR/hypr-sunset/state.json` and never calls
`hyprctl hyprsunset` — every action goes through `hypr-sunset-ctl`
(`toggle` / `disable <seconds>|sunrise` / `set <key> <value>`), preserving the
single-writer rule. Both scripts honour `HYPR_SUNSET_STATE_DIR`,
`HYPR_SUNSET_CONFIG_DIR`, `HYPR_SUNSET_NOW` and `HYPR_SUNSET_HYPRCTL`, so the
whole schedule can be exercised at an arbitrary clock against a scratch tree
with no compositor. Use that rather than waiting for real dusk.

Reading a boolean out of the override file uses `if .enabled == false`, never
`.enabled // true` — jq's `//` treats `false` as empty, which silently breaks
the toggle.

**Resize-move pill:** state is pushed by `hypr-resize-move-toggle`
(`qs-quickshell-ipc call resizemove enter <seconds>` / `… leave`), never
polled — that script is the only thing that enters or leaves the mode. The
mode's deadline is idle-based, so `enter` is re-sent every second with the
seconds left against whichever deadline binds first, and the number climbs
back up whenever the cursor moves. The bar must therefore never run its own
countdown; it clears the pill only when the pushes go stale (~3s). The IPC
calls are best-effort, so the mode still works with the bar dead; the pill
can go stale, the compositor state cannot.

**Tooltips:** `barWindow.armTip(item, kind)` / `disarmTip()`. One
`PopupWindow` on the `PanelWindow`, never nested inside a pill (that
crashes).

**Helpers:** `home/hypr/scripts.nix` `writeShellScriptBin`, put on PATH in
`home/wayland/hyprland.nix` `home.packages`. Nix `''` strings: bash `${`
must be `''${`.

**Reload after QML change:** click the cluster refresh pill
(`qs-quickshell-reload`), or `qs-quickshell-reload`. Session `exec-once` and
reload both use `-p ~/.config/nixos/quickshell`. `~/.config/quickshell` is
the Home Manager copy (fallback only).

**Every reload leaves a dead layer surface behind, so never count bar layers
without filtering.** When a Quickshell instance exits, its layer surfaces stay
in Hyprland's list with `pid: -1`, one per output, and nothing short of a
compositor restart reclaims them (`hyprctl reload` does not). A session with
many reloads shows dozens, which reads as "the bar is running many times" and
is not. Count only the live ones:

```sh
hyprctl -j layers | jq -r 'to_entries[] | "\(.key): live=\([.value.levels[][]? | select(.namespace=="quickshell") | select(.pid != -1)] | length)"'
```

Measured on Tawa 2026-09-03: exactly one leaks per output per instance death
on the clean `quickshell kill` path — so the reload script's KILL escalation
is not the cause — at about **11 kB each** (Hyprland RSS grew 508 kB over 45
of them). They take no
exclusive zone — `reserved` stays `[0,32,0,0]` however many accumulate — and
45 of them moved IPC latency not at all. So this is inert bookkeeping, not a
performance problem: **do not attribute desktop slowness to it** without
measuring first. Surfaces the client destroys explicitly, such as the lock
preview, are reclaimed normally; only what a *disconnecting* client leaves
behind persists, which is why the `qs-lock-preview` cleanliness check above
stays reliable.

**Locking is a user-confirmed action:** ask before `qs-quickshell-ipc call
lock activate` **or** `call lock preview`. Locking seizes every monitor, not
a window, and `activate` also runs `hypr-dpms-side-off`, which DPMS-blanks
every output but one.

**One definition of the centre output.** Quickshell's `centerOutputScreen()`
is the only place that decides which output is "centre" — it prefers
`Hyprland.focusedMonitor` and falls back to the desktop-midpoint walk. It
passes the keep-lit name to `hypr-dpms-side-off <name>`; that script must
never derive it again. It used to, from `hyprctl monitors -j`, whose
`width`/`height` are **pre-transform** where `Quickshell.screens` are
**post-transform** — so a rotated panel is 2560 wide to one and 1440 to the
other, and a disagreement would blank the only monitor showing the password
prompt. Do not "fix" the two APIs to agree; keep one decision.
`hypr-dpms-side-off` fails open (unknown or empty name blanks nothing), and
`hypr-dpms-side-on` deliberately restores **every** output rather than
mirroring the exclusion — refusing to blank is harmless, refusing to restore
leaves a locked machine dark. Always clear your own test — `qs-quickshell-ipc call
lock cancelPreview` for the preview, `hyprctl dispatch dpms on` to re-light
blanked monitors — and confirm you are clean: `hyprctl layers | grep
qs-lock-preview` returns nothing, and `hyprctl monitors -j | jq '.[] |
select(.dpmsStatus == false)'` returns nothing. There is no `deactivate` IPC
for a real lock, by design, so have an SSH session open before locking
anything.

Scope: `quickshell/**/*.qml`, `home/hypr/scripts.nix`,
`home/wayland/hyprland.nix`.

## Secrets

Never commit plaintext secrets or PII.

- Never commit plaintext secrets, private keys, API tokens, webhook URLs,
  Wi-Fi PSKs, or personal mailboxes.
- Encrypted sops files under `secrets/` **are** commit-ok. They must look
  like the existing files (`ENC[` payload and a `sops:` header). Pattern:
  `secrets/placeholder.yaml`, `secrets/acme-cloudflare.env`.
- Public age keys in `.sops.yaml` are commit-ok. Private halves
  (`AGE-SECRET-KEY-1…`, `keys.txt`, `*.agekey`,
  `/var/lib/sops-nix/key.txt`) live in Bitwarden Pro only.
- New secret files go through `sops secrets/<name>.(yaml|yml|json|env)` so
  `.sops.yaml` `creation_rules` encrypt for Tawa, Theseus, and Hearth. Do not
  invent extra age keys. Do not add Gcp until that host exists
  (`NEW-SYSTEM.md` §4).
- Do not `git add` gitignored plaintext: `.gitignore` already lists
  `keys.txt`, `*.agekey`, `age-key.txt`, `secrets/*.plain.yaml`,
  `secrets/*.plaintext.yaml`.
- Committed git identity stays the GitHub noreply in `home/programs/git.nix`.
  The human mailbox is an H5 sops consumer — do not put it back in the
  flake.
- `os-rebuild` prompts to `git add` untracked flake inputs and defaults to
  yes (`--yes` stages without asking). Refuse to stage anything that looks
  like a secret, even if the rebuild needs it.
- GitHub Actions secrets are CI-only, never host-side delivery (Hearth
  `plan.md` H5).
