# Phase 2 — Functional improvements (packages and working setup)

**Goal:** Install what you need for **real work**, and verify each area works (network, sound, display, input, printing, etc.).

**Prior install:** For settings and packages worth reusing from your last NixOS config (network, audio, zsh, Steam, shopping list, Plasma vs tiling), see [05-previous-nixos-config-extract.md](./05-previous-nixos-config-extract.md).

**Status snapshot (2026-04-17):** **Phase C (session)** — **session polish done**: **zsh** + **Kitty** + **Plasma + tiling**; **hotkey** table ([below](#wm--hotkey-notes)) filled to satisfaction; min-width/HiDPI **acceptable**. **Rice (Phase E)** — **complete** (LilacAsh-style pass, `themes/`) per [04](./04-ricing.md) and [06 — § E](./06-implementation-checklist.md#e--rice). **Dotfiles (08):** as before. **`outside` CLI** [deferred](./08-dotfiles-migration-plan.md#deferred--later). **Home Manager (Phase D)** [deferred](./06-implementation-checklist.md#d--home-manager-phase-d-migration-deferred). **Optional** extras: **suspend drain / `deep`**, **hotel** VPN retest. **Bluetooth** / **VPN + stunnel** / **fingerprint** — as documented. See [06 — Current status](./06-implementation-checklist.md#current-status-rolling).

## Core tooling

- [x] **Terminal editor env** — **`micro`** for `EDITOR` / `VISUAL` / `SYSTEMD_EDITOR` ([Q9](./00-audit-priorities-and-risks.md#q9-editor)) — use **`environment.sessionVariables`** + store paths on NixOS so Plasma/Cursor pick it up.
- [x] **GUI / heavy editors** — **VS Code** or **VSCodium**, **Cursor** for larger projects (declare in Nix; note **unfree** if applicable) — **Cursor** + **`cursor-cli`** in use.
- [x] **Markdown** — **Glow** (`pkgs.glow`) for terminal markdown viewing.
- [ ] **Other editors** — Neovim/Emacs if you add them later.
- [ ] **Git** + SSH keys — `ssh-agent` or `gpg-agent` as you prefer.

## Terminal and shell (required)

**Kitty** is the **default terminal** everywhere that matters: WM “run terminal” binding, launcher, optional URI handler, and `$TERMINAL` / session env so scripts agree.

- [x] **Kitty installed and configured** — font/size, colors (can stay minimal until Phase 4); `programs.kitty` in Home Manager or system config — **installed** from dotfiles; **skin in Phase 4** ([04](./04-ricing.md)).
- [x] **Default terminal behavior** — **Kitty** in system packages; **`TERMINAL`** in **`environment.sessionVariables`**; **chezmoi** **`terminal=kitty`**, **`has_omarchy=false`** for **`kitty.conf`**; `.desktop` launchers use **`kitty`**. Details: [08 — Default terminal](./08-dotfiles-migration-plan.md#default-terminal-kitty--verification). Optional: Plasma shortcut if it still opens Konsole.
- [x] **zsh** — login shell via **`users.users.<name>.shell`** and **NixOS `programs.zsh`** ( **Home Manager later** ).
- [x] **Essential zsh plugins (NixOS)** — **syntax highlighting**, **autosuggestions**, **oh-my-zsh** with chosen plugins — all via **`programs.zsh`** in **`configuration.nix`** until HM migration.
- [x] **Sanity check** — new login / Kitty → **zsh** with **NixOS** OMZ + plugins; no **`~/.oh-my-zsh`** errors.

### Chezmoi bootstrap, then NixOS migration

**Agreed approach:** use **chezmoi once** to **apply** the full tree from [debian-dotfiles](https://github.com/ngrayson/debian-dotfiles/tree/main), then **move** settings you want to own into **`configuration.nix`** (and related NixOS options). For each migrated path, use **`.chezmoiignore`** or remove the template so **NixOS**, not chezmoi, is authoritative — see [LOCKED — Dotfiles strategy](./LOCKED.md#execution-note-rolling).

| Phase | What you do |
|-------|-------------|
| **Bootstrap** | **`chezmoi init`** (your dotfiles repo); **`chezmoi apply`** — Kitty, git, shell snippets, etc. on disk. |
| **NixOS-centric** | Copy or re-express important bits in **`~/.config/nixos/configuration.nix`** (`environment.sessionVariables`, `programs.zsh.shellAliases`, future `programs.git`, etc.). **Ignore** those paths in chezmoi so the next **`apply`** does not overwrite NixOS-managed intent. |
| **Longer term** | Optional **Home Manager** ([03](./03-home-manager.md)) replaces hand-edited duplication; chezmoi can shrink to templates only you still need cross-distro. |

Until migration finishes, **avoid defining the same behavior twice** (e.g. duplicate aliases in **`programs.zsh`** and **`~/.zshrc`**).

**Oh My Zsh on NixOS:** **`~/.oh-my-zsh`** is **not** populated by default. **`programs.zsh.ohMyZsh`** in **`configuration.nix`** installs OMZ under the Nix store and **`/etc/zshrc`** loads it **before** **`~/.zshrc`**. A Debian-style **`~/.zshrc`** that sets **`ZSH=$HOME/.oh-my-zsh`**, **`zsh-defer`**, or **`source $ZSH/oh-my-zsh.sh`** will fail — remove that block and set **theme** / **plugins** in **`configuration.nix`** instead.

When you adopt **Home Manager** ([03](./03-home-manager.md)), move **`programs.zsh`** (and optionally Kitty) into **`home.nix`** per [LOCKED Q6](./LOCKED.md) and shrink overlapping chezmoi paths deliberately.

## Desktop / session (if not already settled)

- [x] **Display manager / session** — **SDDM** + **Plasma** (Theseus).
- [x] **Wayland vs X11** — **Wayland** primary; **XWayland** for games/legacy.

## Games and screen sharing (required)

You want **games** and **screen sharing** to work on the **Wayland** session.

- [x] **XWayland** — in use for the Plasma session as needed.
- [x] **xdg-desktop-portal** — `xdg.portal.enable = true` (and related NixOS options). On **Plasma**, **KDE’s portal** covers screen/window capture in normal use. (**`xdg-desktop-portal-wlr`** only if you move to a wlroots-based compositor later.)
- [x] **PipeWire** — already typical for audio; screen capture/sharing pipelines often depend on it; confirm **WirePlumber** (or default session) is healthy.
- [ ] **Test matrix** — **Browser** (Meet/Discord web), **native Discord** if used, **OBS** or similar, **one native game** + **one Proton/Steam** title if you use Steam.
- [ ] **Graphics stack** — on Framework (Intel/AMD), ensure **Mesa/Vulkan** and permissions are sane; **Steam** + **`allowUnfree`** when you add Steam ([05](./05-previous-nixos-config-extract.md)).

## Window manager: tiling and hotkeys (major priority)

This is core **functionality**, not cosmetics: you need **tiling** on and **bindings** that match your **muscle memory** so daily use feels automatic.

**Decision (Q1):** **KDE Plasma (Wayland) + tiling plugin** — locked daily driver; **Sway** not targeted — see [00-audit-priorities-and-risks.md](./00-audit-priorities-and-risks.md) decisions log.

- [x] **Tiling enabled** — native tiling WM, or a **tiling mode/extension** in your DE (e.g. GNOME/KDE tiling, Pop Shell–style, sway/Hyprland/i3, etc.), declared in NixOS/Home Manager where applicable — **Plasma tiling** on; **some apps enforce a large minimum width** when resizing (see **Framework ergonomics** below).
- [x] **Focus follows mouse** — **keyboard focus** moves to whichever window is under the pointer (no click-to-focus-only); often called *sloppy focus* or *focus on hover*. On **Plasma / KWin**, use **System Settings** “focus follows mouse” (and tiling plugin options). Verify edge cases: dialogs, fullscreen, games.
- [x] **Hotkey map written down** — [WM / hotkey notes](#wm--hotkey-notes) (Theseus: bindings to satisfaction).
- [x] **Conflicts resolved** — for daily use; revisit if tools change.
- [x] **Muscle memory pass** — **done** for current workflow.

## Hardware and media

- [x] **Audio** — PipeWire (typical on modern NixOS); test mic + speakers + Bluetooth headset.
- [x] **Bluetooth** — **`hardware.bluetooth.enable = true;`** and **`hardware.bluetooth.powerOnBoot = true;`** in `configuration.nix` — pair in **Plasma → Settings → Bluetooth**; **A2DP** / audio via PipeWire + WirePlumber — **verified working**.
- [x] **Camera** — test in browser or a simple camera app.
- [ ] **Power management** — test suspend/resume — **goal:** **low-power suspend** (idle + suspend drain, not only “it suspends”); align with [LOCKED](./LOCKED.md) — **no zram**. See **[Low-power suspend](#low-power-suspend-investigation)** below.

### Low-power suspend (investigation)

**Applied (rebuild done):** **`services.logind.settings`** (lid → suspend; docked → ignore), **`powertop`** in **`environment.systemPackages`**. **Deferred:** % drain, **`mem_sleep` / `deep`**, optional **`powertop --auto-tune`** module — run when convenient.

**Already on this machine (from `configuration.nix`):** **`powerManagement.enable`**, **`services.power-profiles-daemon`** (PPD — works with Plasma’s **Power / Energy** settings), **`amd_pstate=active`**, **`nixos-hardware`** Framework profile, **no `zramSwap`** per LOCKED.

**Do not stack aggressively:** **`services.tlp.enable`** and **PPD** both try to own power policy — **pick one**. With PPD + KDE, **avoid enabling TLP** unless you disable PPD and accept the tradeoffs.

#### 1 — Baseline behavior (no new modules yet)

- **Plasma:** **System Settings → Power Management** — on battery: when to **dim**, **sleep** after idle, **suspend** on lid close; on AC: stricter or looser as you like. Align with **`logind`** expectations (lid switch).
- **Manual suspend test:** `systemctl suspend` — wake, unlock, confirm **Bluetooth**, **Wi‑Fi**, **audio**, **fingerprint** still OK (you’ve partly validated this).
- **Logs after a suspend cycle:** `journalctl -b -u systemd-sleep -u NetworkManager --no-pager | tail -80`

#### 2 — Measure drain (facts before tuning)

- **Suspended drain:** full battery → note % → close lid (or `systemctl suspend`) for **30–60 min** → note % drop. **Target** is subjective; **~1–3%/h** is often cited for healthy s2idle on modern laptops; much higher → dig deeper.
- **Idle on battery (screen off):** same kind of %/hour check with **no** heavy apps — establishes whether the problem is **suspend path** vs **idle**.

#### 3 — Sleep depth (`s2idle` vs `deep`)

- **Current modes:** `cat /sys/power/mem_sleep` — you’ll see supported strings (e.g. **`s2idle`** `[deep]`).
- **`s2idle` (freeze):** fast wake; often **higher** suspend drain on some machines.
- **`deep` (S3-style):** lower drain when it works; **wake latency** and **quirks** vary by firmware/AMD.
- **Optional kernel param (test carefully):** `mem_sleep_default=deep` — add to **`boot.kernelParams`** only if `mem_sleep` lists `deep` and you’re willing to test **stability** (wake, USB, Bluetooth). **Revert** if resume or devices break.

#### 4 — `powertop` (analysis vs autotune)

- **Package:** `powertop` is useful for **interactive** tuning suggestions (USB autosuspend, etc.).
- **NixOS:** `powerManagement.powertop.enable` runs **`powertop --auto-tune`** at boot — can help or cause **quirky USB/Bluetooth**; try **manual** `sudo powertop` first, then enable the module only if stable.

#### 5 — Hibernate (optional, advanced)

- **S4 hibernate** needs **swap ≥ RAM** (or compressed swap) and **resume** from swap — with **LUKS**, you must align **resume offset** / unlock ordering — **high effort**; treat as a later project unless you need “off for days” on battery.

#### 6 — When to call it “done” for Phase 2

- [ ] Lid / idle / Plasma settings match how you use the machine.
- [ ] Suspend/resume reliable; **fingerprint**/**BT**/**network** acceptable after wake.
- [ ] Measured suspend drain **acceptable** to you, or **`deep`** (or targeted `powertop`) tried and documented.

### Fingerprint (fprintd)

Framework readers are usually supported via **`libfprint`** / **`fprintd`**. **`services.fprintd.enable = true`** is in **`configuration.nix`**, plus **`security.pam.services`** with **`fprintAuth`** for **`sddm`**, **`login`**, **`sudo`**, **`polkit-1`**, **`kscreenlocker`**. If **`fprintd-list-devices`** is empty after **`nixos-rebuild switch`**, uncomment **`services.fprintd.tod`** + **`libfprint-2-tod1-goodix`** in the same file (Goodix is common on Framework).

- [x] **Daemon + device** — **`fprintd`** active; reader present (**`fprintd-list-devices`** / Goodix TOD if you enabled it).
- [x] **Enroll** — prints enrolled (**Plasma** and/or **`fprintd-enroll`**).
- [x] **PAM** — **`fprintAuth`** for SDDM, TTY login, sudo, polkit, Plasma screen lock (**`kscreenlocker`**).
- [x] **Real-world test** — lock screen, **`sudo`**, **SDDM** (and **after suspend** as applicable) — **tests good**.

## Networking and sync

- [ ] **Browser** — Firefox/Chromium; hardware acceleration if you care.
- [ ] **VPN — OpenVPN + Vortix** — see **[OpenVPN + Vortix (NixOS)](#openvpn--vortix-nixos)** below; **canonical `.ovpn`** in **`~/.config/ovpn/`**; **`vortix import`** that directory (or per file). Runtime deps in **`configuration.nix`**; **Vortix** from upstream **flake**. Secrets: **`sops-nix`** / **`agenix`** for **`auth/`** when needed.

### OpenVPN + Vortix (NixOS)

**[Vortix](https://github.com/Harry-kp/vortix)** — Rust **TUI** for **WireGuard** and **OpenVPN**: profiles (`.conf` / `.ovpn`), telemetry, leak checks, **kill switch** (iptables/nftables), `sudo vortix` for connect/disconnect. **Primary dev on macOS**; **Linux** is supported (CI: Ubuntu/Fedora) with **distro variance** — expect to iterate on **NixOS** (firewall, **NetworkManager**, **systemd-resolved**).

**Not in `nixpkgs`** (`nix eval` → no `pkgs.vortix`). Upstream ships a **[flake](https://github.com/Harry-kp/vortix/blob/main/flake.nix)** (`packages.default` = binary).

| Topic | Notes |
|--------|--------|
| **Install (classic NixOS)** | **`nix profile install github:Harry-kp/vortix`** — puts **`vortix`** on your user **`PATH`** (README: Nix profile installs are **not** broken by `sudo` `secure_path` like **`~/.cargo/bin`**). Alternative: **`nix run github:Harry-kp/vortix`** for one-shot. |
| **Runtime deps** | **`openvpn`**, **`wireguard-tools`**, **`curl`**, **`iptables`** (or nftables backend), **`iproute2`**. **DNS:** WireGuard profiles with **`DNS =`** need **systemd-resolved** / **resolvconf** behavior — NixOS defaults usually OK; Vortix README warns if tools are missing. |
| **Config layout** | **`~/.config/vortix/`**: **`profiles/`** (`.ovpn`/`.conf`), **`auth/`** (per-profile OpenVPN user/pass), **`config.toml`**, logs. **`sudo`** still uses **your** home via **`SUDO_USER`** (not `/root`). |
| **Canonical `.ovpn` source (Theseus)** | You keep provider files in **`~/.config/ovpn/`**. **Import into Vortix:** **`vortix import ~/.config/ovpn/`** (bulk) or **`vortix import ~/.config/ovpn/your.ovpn`** — Vortix copies into **`~/.config/vortix/profiles/`**; edit the **canonical** tree and **re-import** if you change a file, or edit the copy under **`vortix/profiles/`** only if you accept drift. |
| **vs NixOS `services.openvpn`** | **`networking.openvpn.*` / `services.openvpn.servers`** = **declarative, boot-time** tunnels. **Vortix** = **interactive** profile switching and TUI — **complementary**. Pick **one** story per profile to avoid two clients fighting the same tunnel. |
| **Kill switch vs NixOS firewall** | Vortix adjusts **firewall** rules for killswitch — can interact with **`networking.firewall`** / **nftables**. If something breaks, **`sudo vortix release-killswitch`** and tune **firewall** options or Vortix **killswitch** mode (`auto` / `always`). |
| **NetworkManager** | You use **NM** for Wi‑Fi. VPN routes + Vortix + NM sometimes need care (metric, DNS). **Document** what works after first connect. |

**Suggested order:** (1) Runtime packages in **`configuration.nix`**. (2) **`nix profile install github:Harry-kp/vortix`**. (3) **`vortix import ~/.config/ovpn/`** (or per-file) so profiles appear in the TUI. (4) **`sudo vortix`** → connect / test. (5) **`auth/`** for username–password profiles if needed. (6) **FrootVPN stunnel/443** for **restricted Wi‑Fi** — see [§ FrootVPN + Stunnel](#frootvpn--stunnel--vortix-theseus) and [§ Restricted networks](#restricted-networks-hotels-airplane-wi-fi).

### FrootVPN + Stunnel + Vortix (Theseus)

**Provider:** [FrootVPN](https://frootvpn.com) ships a **Stunnel + OpenVPN** bundle (download from [server info](https://frootvpn.com/en/account/server-info)): **`localhost.ovpn`** (OpenVPN to **`127.0.0.1:1194`**) plus per-region **`*.conf`** files for **stunnel** (`accept` / **`connect = <region>.frootvpn.com:443`**). No VPS relay — FrootVPN terminates TLS on **443**.

| Item | Location / action |
|------|-------------------|
| **Canonical bundle** | **`~/.config/ovpn/froot-stunnel-configs/`** — **`localhost.ovpn`**; subfolders contain region **`*.conf`** (hostname for **`connect`**). |
| **TLS CA (stunnel)** | **`~/.config/nixos/frootvpn-stunnel-ca.pem`** — same FrootVPN CA as the **`<ca>`** block in **`localhost.ovpn`**; copied into **`environment.etc`** as **`/etc/frootvpn/stunnel-ca.pem`** so **stunnel** (runs as **`nobody`**) can read it. If FrootVPN rotates the CA, update the PEM and **rebuild**. |
| **NixOS** | **`services.stunnel.enable`** and **`services.stunnel.clients.frootvpn`** in **`configuration.nix`**: **`accept = "127.0.0.1:1194"`**, **`connect`** = chosen region (default in config: **Canada West** — **`ca-west.frootvpn.com:443`**). Rebuild to apply. |
| **systemd** | **`systemctl status stunnel`** — should be **active** before connecting in Vortix. |
| **Vortix** | **`vortix import …/localhost.ovpn`** → profile name **`localhost`**. Use **`sudo vortix`** (or **`vpn`** alias), select **`localhost`**, enter FrootVPN credentials when prompted. |
| **Change region** | Edit **`connect`** in **`configuration.nix`** to the hostname in another region’s **`*.conf`**, **`sudo nixos-rebuild switch`**, then **`systemctl restart stunnel`**. |

### Restricted networks (hotels, airplane Wi‑Fi)

Captive portals and dumb firewalls often **block UDP**, **non‑443 TCP**, or **known VPN ports**. A **second path** that rides **TLS on port 443** survives many of those environments.

- [x] **stunnel on 443 (FrootVPN)** — **`services.stunnel`** client in **`configuration.nix`** + **`frootvpn-stunnel-ca.pem`**; OpenVPN via **`localhost.ovpn`** / Vortix profile **`localhost`** ([§ FrootVPN + Stunnel](#frootvpn--stunnel--vortix-theseus)).
- [x] **Test matrix** — **FrootVPN `stunnel` + `localhost`** verified working on your machine; **optional:** repeat on a **phone hotspot** or **captive** network when convenient (DNS hijacks are the usual edge case).
- [x] **Document** — **open internet** = your usual Vortix profiles; **hotel / restricted** = **`stunnel` running** + Vortix profile **`localhost`** (this section + [06](./06-implementation-checklist.md)).

- [ ] **Tailscale / other** — only if you add them.
- [ ] **Syncthing / Nextcloud client** — if applicable.

## Printing and documents

- [ ] **CUPS / printer** — add printer; test page.
- [ ] **PDF** — viewer you like.

## Framework ergonomics

- [ ] **HiDPI / scaling** — fractional scaling if needed (DE-dependent) — **if tiling leaves “too-wide” minimum window sizes**, try **lowering global scale** or **font/UI size** first; some apps compute a minimum width from DPI/font metrics.
- [ ] **Function keys / brightness** — verify keys or bind in compositor/DE.
- [ ] **Dock / USB-C** — external displays and hubs.

## Done when

- [x] You can do **one full workday** without fighting sound, network, sleep, or display.
- [x] **Screen sharing** and **session needs** at an acceptable level on **Plasma (Wayland)**; games per your use of **XWayland** / stack.
- [x] **Kitty** default terminal; **zsh** + essential plugins as expected.
- [x] **Tiling**, **focus-follows-mouse**, **hotkeys** — session polish **complete** (revisit as needs change).
- [x] Remaining items are **optional** / listed as **P2–P3** in backlog, not day-one blockers.

## Blockers and backlog

- **P2 — Low-power suspend** — **baseline applied**; when ready, measure drain / try **`deep`** per [§ Low-power suspend](#low-power-suspend-investigation) (avoid **TLP + PPD**).
- **P2 — VPN** — **Vortix** from **flake** + runtime deps in Nix; **`auth/`** + profiles via **sops-nix** / **agenix** when ready ([§ OpenVPN + Vortix](#openvpn--vortix-nixos)).
- **P2 — Restricted-network egress** — **Done (FrootVPN):** **`services.stunnel`** + **`localhost`** Vortix profile — **verified on-device**; optional **hotel/captive** retest later ([§ Restricted networks](#restricted-networks-hotels-airplane-wi-fi)).
- **P3 — Tiling minimum width** — **resolved to satisfaction** with HiDPI/fonts/rice; reopen if a new app misbehaves.
- **P3 — Hotkeys** — **session polish done**; tweak [WM / hotkey notes](#wm--hotkey-notes) when bindings change.

## WM / hotkey notes

**Stack:** **KDE Plasma (Wayland)** + **tiling plugin** — locked per [Q1](./00-audit-priorities-and-risks.md).

**Focus:** **Focus-follows-mouse** — working.

**Tiling:** Mostly working; **some windows resist shrinking** past a floor width — see **Framework ergonomics** (HiDPI/fonts).

**Hotkeys:** **Bindings below** — your reference table (Plasma / tiling); update the **Binding** column when you change **System Settings → Keyboard → Shortcuts** (or tiling plugin).

| Action | Binding | Notes / conflicts |
|--------|---------|-------------------|
| Application launcher | *(e.g. Meta+Space — set in Shortcuts)* | KRunner, application launcher, or custom |
| Run terminal (Kitty) | *(override “Launch Konsole” → Kitty)* | Should match **`$TERMINAL`** ([08 — Kitty](./08-dotfiles-migration-plan.md#default-terminal-kitty--verification)) |
| Switch workspace / desktop | *(Plasma virtual desktops)* | |
| Move window to workspace | *(tiling / KWin if bound)* | |
| Tile split / direction | *(tiling plugin defaults)* | Plasma tiling plugin |
| Float / restore | | |
| Fullscreen | | |
| Close window | | |
| Focus next / prev window | | Optional |
| Screenshot / region (if bound) | *(Spectacle or custom)* | |

**IDE / browser / games:** note any **Super** / **Ctrl** overrides (fullscreen, games, modals).

<!-- Super/Ctrl conflicts with IDE/browser — note exceptions (fullscreen, games, modals) -->
