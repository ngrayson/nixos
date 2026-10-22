# Ponytail audit — WizOs, 2026-10-22

Audited commit `ab99619` (`dev`) with the `ponytail-audit` skill from ponytail 5.3.2. Five read-only passes covered the deploy scripts, secrets and network exposure, the Hearth dashboard, scry and the Python tools, and the desktop scripts and QML. Every finding below was re-read in the source at that commit before it was kept.

What this repo does: It is one NixOS flake that builds five machines for one person: Tawa (desktop), Theseus (laptop), Hearth (a home server for Jellyfin, backups, a dashboard and a Discord digest bot), Go3 (a wall kiosk) and Gcp (a cloud host that is not running). Shell scripts build on Tawa and switch the other machines over SSH. Load assumed: one user, a handful of devices on the tailnet and one TV; never many users, but many timers, scripts and bar processes running at the same time.

**Must fix**

1. **Private calendar links are copied into the world-readable Nix store** (`hosts/Hearth/intranet-calendar.nix:L5-21`)
   - **What this is:** The Hearth dashboard merges your Google calendars. Each calendar's private feed URL (the "secret address in iCal format") is read from a gitignored config file.
   - **Problem:** `pkgs.writeText` puts those URLs into `/nix/store/…-hearth-calendar-feeds.json`. Every file in the Nix store can be read by every account on the machine, on Hearth and on Tawa, which builds it, and the store path is copied to Hearth on every deploy. Anyone holding one of those URLs can read that whole calendar.
   - **Fix:** Store the feed list as a sops secret owned by `hearth-intranet`, and have the fetch script read it from `/run/secrets` at run time. `desktop-calendar-ics` in `common/sops.nix` already works this way.
   - **If we skip it:** Any service account on Hearth, including the LAN-reachable Jellyfin user, can read your calendars, and the URLs live in old store paths until garbage collection.
   - Card: `private-calendar-feed-urls-are-written-into-the-world-readab`

2. **The `hearth-deploy` menu keeps going after its own safety checks say stop** (`scripts/hearth-deploy.sh:L755-757, L768-773, L959-972`)
   - **What this is:** Running `hearth-deploy` with no arguments opens a menu. Each choice calls `run_build` or `run_deploy`, which first check that the dashboard's local config files exist and that untracked files are staged.
   - **Problem:** The menu calls them as `run_build || true`. In bash that turns off `set -e` for everything inside, and these checks only stop the run through `set -e`. The script prints "Missing …/weather/config.nix", or "Refusing to build", and then builds and deploys anyway.
   - **Fix:** In `run_build` and `run_deploy`, write `require_local_intranet_config || return 1` and `offer_stage_untracked || return 1`.
   - **If we skip it:** A deploy from the menu can quietly put the example (wrong-city) weather and transit settings on Hearth, and the health check still passes.
   - Card: `hearth-deploy-menu-ignores-its-own-missing-config-and-stagin`

3. **`--from-checkout` checks the last commit but deploys uncommitted files** (`scripts/hearth-deploy.sh:L155-166, L262-266`)
   - **What this is:** Before a switch, the script refuses changes to shared folders (`common/`, `home/`, `profiles/`, `flake.*`) that have not been promoted through `main`.
   - **Problem:** With `--from-checkout`, the check compares `origin/main` to the committed `HEAD`, but the deploy builds the working tree, including uncommitted edits. An uncommitted change to `common/` passes the check and lands on Hearth. Separately, if `git diff` itself fails (for example, no `origin/main` ref), its empty output also counts as "no shared paths".
   - **Fix:** When deploying from the checkout, also check `git diff --name-only HEAD -- <shared paths>` for uncommitted changes. Treat a failing `git diff` as a refusal, not a pass.
   - **If we skip it:** Hearth can become the first machine to run an untested shared change, which is the exact case the guard exists to prevent.
   - Card: `hearth-deploy-from-checkout-checks-head-but-deploys-the-dirt`

4. **"Fast-forward to dev" moves the Hearth pin before the safety check and the confirm** (`scripts/hearth-deploy.sh:L788, L808, L824-826`)
   - **What this is:** The interactive switch offers to fast-forward `deploy/hearth` to `dev` and then deploy it.
   - **Problem:** The `git push` that moves the pin (L788) runs before the shared-path refusal (L808) and before the "Run 'switch' on Hearth?" question (L824). If either one says no, the remote pin has already moved.
   - **Fix:** Move the fast-forward after the refusal and after the confirm, just before activation.
   - **If we skip it:** A deploy you cancelled leaves `origin/deploy/hearth` pointing at `dev`, and the next `--yes` or pin deploy ships it.
   - Card: `hearth-deploy-fast-forward-moves-the-pin-before-its-safety-c`

5. **A Conveyor outage makes the digest post an empty report and exit as a success** (`pkgs/scry/digest.mjs:L34-38, L46-52`)
   - **What this is:** The weekly Scrying Orb digest asks Conveyor for each project's cards and posts them to Discord.
   - **Problem:** `call()` ignores the tool's `isError` flag. An error text such as "Unauthorized" is returned as a string, and the caller treats anything that is not a list as "no cards". An expired token gives a digest with every project empty, and the job exits 0, so the new failure notice (`scry-failed@`) never fires.
   - **Fix:** In `call()`, throw when `r.isError` is set or when the text is not JSON. The run then fails and the failure notice reports it.
   - **If we skip it:** A dead Conveyor token looks like "nothing to do" every Saturday until someone notices.
   - Card: `scry-digest-posts-an-empty-report-and-exits-0-when-conveyor`

6. **The hearth-tui disk menu can offer the wrong action** (`home/programs/hearth-tui/src/hearth_tui/widgets.py:L608-612`, `home/programs/hearth-tui/src/hearth_tui/disk_action.py:L239-247`)
   - **What this is:** The Hearth TUI runs `hearth-disk status` and offers "Park COLD" or "Mount COLD & resume", depending on the state.
   - **Problem:** `hearth-disk` prints `[ok]` lines to stdout and `[fail]` lines to stderr, and the widget joins `stdout + stderr`, so every ok row comes first. The decision then reads rows by position (row 1 = mounted, row 2 = Jellyfin). With COLD plugged in but not mounted, "mounted" reads as true and the menu never offers "Mount COLD & resume". With Jellyfin crashed, it reads the Syncthing row and offers Park.
   - **Fix:** Find each row by its text ("is mounted", "Jellyfin is active") instead of by position, or run `hearth-disk status 2>&1` so the order is kept.
   - **If we skip it:** The one-key disk menu gives the wrong advice in exactly the states it exists for.
   - Card: `hearth-tui-disk-menu-reads-status-rows-by-position-and-offer`

7. **The lock helper can report "locked" while the old lock screen is closing** (`home/hypr/scripts.nix:L104-117`)
   - **What this is:** `quickshell-lock` starts the lock screen and waits until a lock instance exists. The before-sleep hook calls it, so the machine only suspends once it is locked.
   - **Problem:** After an unlock, the old lock instance stays alive for about 1 to 2.5 seconds while it quits (`quickshell/lock.qml`). During that time `-n` refuses to start a new instance, and the wait loop sees the dying one and reports success.
   - **Fix:** After the wait loop, confirm the instance is actually locked (an IPC query on the lock instance), or wait for the old instance to exit before starting a new one.
   - **If we skip it:** Unlocking and then closing the lid within about two seconds suspends the machine unlocked, and it wakes unlocked.
   - Card: `quickshell-lock-reports-success-against-a-lock-instance-that`

8. **The dashboard calendar shows missing or wrong events** (`hosts/Hearth/intranet/src/widgets/Calendar.jsx:L63-77, L300-326`, `hosts/Hearth/intranet-calendar.nix:L73-75`)
   - **What this is:** The calendar card fetches `/calendar.ics` and lays out three weeks of events.
   - **Problem:** There are three separate faults.
     - It fetches once, when the page loads, and only parses the three weeks visible then (L300-326). After a week on the kiosk, the last week is always empty, and new events never appear.
     - The 400-occurrence safety cap counts from the series' first date (L63-77). A daily meeting that started in early 2025 has passed the cap and disappears.
     - The ICS merger strips trailing spaces from every line (L73-75). That joins words across Google's 75-character line folds ("Dinner withBob").
   - **Fix:** Re-fetch and re-parse on a 15-minute timer, as the weather card does. Count only occurrences that fall inside the window. Use `rstrip("\r\n")` instead of `rstrip()`.
   - **If we skip it:** The wall calendar quietly drops recurring events and goes blank in its third week.
   - Card: `dashboard-calendar-never-refetches-drops-long-running-series`

9. **"Stop when the running card finishes" can wait forever and block Start** (`home/services/conveyor-vm-status.nix:L298-319`)
   - **What this is:** The bar's Conveyor VM pill can stop the VM once its running card finishes. A background loop polls `vm pods` every 30 s.
   - **Problem:** If the VM stops some other way (the resource guard, a crash, a manual `vm stop`), `vm pods` fails and the loop reads "unknown", never 0, so it never exits. Its pending file keeps the pill on "Stopping after the running card", and every Start is refused as busy.
   - **Fix:** Before each poll, check `vm status`. If the VM is no longer running, clear the pending file and exit.
   - **If we skip it:** After one unusual stop, the pill is stuck and Start does nothing until someone runs `qs-conveyor-vm-ctl cancel-stop` by hand.
   - Card: `conveyor-vm-pill-drain-loop-never-exits-once-the-vm-stops-so`

10. **Two secrets are visible in the process list** (`hosts/Hearth/syncthing.nix:L71, L81`, `pkgs/scry/module.nix:L80-81`)
    - **What this is:** The Syncthing pairing script calls Syncthing's local API, and the scry failure notice posts to Discord. Both use curl.
    - **Problem:** Both pass the secret as a curl argument (`-H "X-API-Key: …"` and the webhook URL). Any account on Hearth can read another process's arguments with `ps`. The Syncthing key gives full control of Syncthing. The webhook lets anyone post as the Scrying Orb.
    - **Fix:** Pass them on stdin with `curl --config -`, as `hosts/Hearth/hearthchime.nix` already does, with a comment explaining why.
    - **If we skip it:** A compromised service account on Hearth (Jellyfin is reachable from the LAN) can take over Syncthing's sharing, or spam the Discord channel.
    - Card: `syncthing-api-key-and-scry-webhook-url-are-passed-on-curl-s`

**Should fix**

11. **The AirNow and OneBusAway API keys are also copied into the Nix store** (`hosts/Hearth/intranet-aqi.nix:L36-37`, `hosts/Hearth/intranet-transit.nix:L19-20`)
    - **What this is:** The air-quality and bus pollers read their API keys from gitignored config files.
    - **Problem:** `writeText` puts both keys in world-readable store files, the same way as finding 1. Both keys are free and rate-limited, so the harm is someone using up your quota.
    - **Fix:** Move both keys to sops when finding 1 is fixed, using the same pattern.
    - **If we skip it:** A local account can exhaust the quota and blank the AQI and bus cards.

12. **The only backup copy can be deleted by the `jellyfin` group** (`hosts/Hearth/restic.nix:L33-41`, `hosts/Hearth/host.nix:L113-119`)
    - **What this is:** restic backs up Hearth, including the sops key, into a repository on the COLD disk.
    - **Problem:** COLD is NTFS, mounted as `gid=989` (the jellyfin group) with `umask=0002`, so every file in the backup is group-writable. The Jellyfin service (open on the LAN) and Syncthing (talks to the internet) both run in that group. restic's encryption protects the contents but not against deletion.
    - **Fix:** Mount the backups folder separately with `umask=0022`, or keep the restic repository off COLD.
    - **If we skip it:** One compromised media service can erase the only backup of Hearth's secrets.

13. **Any member of the Discord server can see your Notion Area names** (`pkgs/scry/bot.mjs:L56-60`)
    - **What this is:** The `/task` command autocompletes its area option from your Notion Areas.
    - **Problem:** The autocomplete branch runs before the owner check on L63. Any server member who types `/task` sees up to 25 of your private Area names.
    - **Fix:** Check `isOwner(i.user.id)` at the top of the autocomplete branch, and return an empty list for anyone else.
    - **If we skip it:** Private project names leak to everyone in that server.

14. **Two hyprsunset writers share one temp file** (`home/services/hyprsunset/scripts.nix:L349, L516`)
    - **What this is:** The 30 s tick and `hypr-sunset-ctl` both edit `override.json` with `jq … > override.json.tmp && mv`.
    - **Problem:** They use the same temp name and each reads the old file first. If gamemode's `pause` runs while the tick is clearing an expired `disabledUntil`, the tick's `mv` lands last and drops `hold`. `publish_state` already uses a per-process temp name for this exact reason.
    - **Fix:** Use `override.json.$$.tmp`, and take a `flock` around the read and the write.
    - **If we skip it:** Occasionally the game-mode hold is lost and warmth pushes happen during a match.

15. **Bus countdowns freeze between polls** (`hosts/Hearth/intranet/src/widgets/Buses.jsx:L11-14, L115`)
    - **What this is:** The bus card shows minutes until each arrival.
    - **Problem:** Minutes are counted from `r.currentTime`, the server's time when the poller ran, not from now. A carried-over row (rate-limited stops keep rows for up to 300 s) still says "8 min" four minutes later.
    - **Fix:** Use `Date.now()` and re-render on the existing 30 s clock tick.
    - **If we skip it:** You can miss a bus that the board says is still minutes away.

16. **`go3-deploy switch` exits 0 when the kiosk stays down** (`scripts/go3-deploy.sh:L142-145`)
    - **What this is:** After a switch, `ensure_kiosk` restarts the kiosk if it is not running.
    - **Problem:** It is called as `ensure_kiosk || true`, followed by `return 0`, so "Kiosk still down after a restart" is printed and the deploy still reports success. The comment at L158-169 says this code exists to prevent a "blank wall behind a succeeded deploy".
    - **Fix:** Drop `|| true` and return its status.
    - **If we skip it:** A blank wall screen passes as a successful deploy.

17. **A failed restic run shows "(no snapshots yet)"** (`home/programs/hearth-tui/src/hearth_tui/widgets.py:L777-792`)
    - **What this is:** The TUI's backup panel lists restic snapshots.
    - **Problem:** The exit code is never checked, and restic writes its error to stderr. With COLD parked, stdout is empty and is parsed as an empty list.
    - **Fix:** If the return code is not 0, show the last stderr line in red.
    - **If we skip it:** A missing or broken backup repository looks like a fresh, empty one.

18. **Nothing tests the deploy guards or the feed parsers** (`scripts/hearth-deploy.sh:L262-266`, `hosts/Hearth/intranet-calendar.nix:L73-75`, `pkgs/scry/task.mjs:L229-242`)
    - **What this is:** The shared-path guard, the ICS merger, and the inbox and due-date parser decide what gets deployed, shown or filed.
    - **Problem:** Findings 2, 3 and 8 all sit in code with no test. The inbox parser also reads "PR #482" as area `482` and refuses the task, and it accepts "feb 30" as March 2.
    - **Fix:** Add one small test per parser to the flake checks, in the same shape as `tests/hypr-sunset/run.sh`: the guard against a scratch repo, the ICS merger against a folded line, and the inbox parser against a title containing `#`.
    - **If we skip it:** The next edit to these paths breaks them silently again.

**Nice to have**

19. **`qs-nixos-status` writes two files nothing reads** (`home/hypr/scripts.nix:L709-719, L750-751`)
    - **What this is:** The bar's update check writes `fingerprint` and `local.json` into its cache.
    - **Problem:** Nothing reads them. They are only written here and deleted (`home/hypr/scripts.nix:L638`, `documentation/nixos-framework-setup/os-rebuild.sh:L597`). Computing the fingerprint hashes `git diff --binary HEAD` on every 60 s poll.
    - **Fix:** Delete `fingerprint()` and both writes, and the two `rm` lines.
    - **If we skip it:** About 20 lines and a full diff hash per minute, for nothing.

20. **Two leftover files at the repo root** (`nixos-switch.log`, `keybinds.kksrc`)
    - **What this is:** `nixos-switch.log` is a 29-byte log whose only line is "sudo: a password is required", committed in `13538b5`. `keybinds.kksrc` is an 11 KB KDE shortcuts export from before the move to Hyprland.
    - **Problem:** No Nix file references either one. They make the root look like it holds configuration it does not.
    - **Fix:** `git rm` both, and add `*.log` to `.gitignore`.
    - **If we skip it:** Nothing breaks. It is clutter.

23 smaller findings were left out. Among them:
- the Hearth desktop notification text is split word by word over ssh;
- `go3-deploy status` prints two values for a stopped unit;
- gallery file names are not URL-encoded;
- the weather card never marks stale data;
- the Server Status card ignores the age of `status.json`;
- the site sync's `rsync --delete` is not atomic for the kiosk;
- the transit poller can exceed its 90 s start timeout;
- a single over-long Notion title can exceed Discord's 2000-character limit;
- Conveyor lists stop at 50 cards per status;
- a quick double reaction can file an inbox message twice;
- hearth-tui's log view swallows `[fail]` markers;
- the Tailscale warning's debounce does not survive a suspend;
- `hypr-sunset-ctl disable sunrise` silently does nothing without a location fix;
- `qs-usb-open` passes Dolphin a hex-escaped path for labels with spaces;
- bar audio actions are dropped while the previous one runs;
- the Conveyor pill's pending file is check-then-spawn racy;
- the os-rebuild Hearth bootstrap evaluates as root and so falls back to the example dashboard configs;
- Caddy's admin API listens on localhost.

Verdict: Fix the secrets first (1, then 10 and 11), then the `hearth-deploy` guards (2-4), because they are the safety net for every Hearth change. Then the digest's silent failure (5).
Lean: -40 lines, -0 dependencies possible.
Not checked:
- Binary assets (wallpapers, the fastfetch gif), `kvantum/**` themes, both `package-lock.json`, the `secrets/**` ciphertext, `hosts/*/hardware-configuration.nix`, `documentation/**` prose and the GLSL shaders.
- The QML other than `shell.qml` and `WindowSwitcher.qml`, beyond its entry points.
- Two candidates that depend on Quickshell runtime behaviour, which cannot be confirmed by reading: a USB eject killed when the bar's 5 s refresh rebuilds its delegate, and the full-screen OSD window taking clicks for 1.2 s.
- Nothing was run on any host.
- Network exposure was evaluated for all five hosts with `nix eval` and has not regressed since PR #209: every open port is set by a module default and carries a comment.
- There are no `shortcut:` markers in the tree.
