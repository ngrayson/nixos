# Phase 4 — Rice: aesthetic overhaul

**Goal:** Make the system **look and feel cohesive** — typography, color, icons, shell prompt, bar, launcher, notifications, and wallpaper — without sacrificing the stability from earlier phases.

**Related:** [06 — § E](./06-implementation-checklist.md#e--rice) (checklist), [02 — WM / hotkey notes](./02-functional-improvements.md#wm--hotkey-notes) (bindings in parallel), [08](./08-dotfiles-migration-plan.md) (dotfile ownership).

## Principles

- **One source of truth (per phase)** — while tuning, **Plasma System Settings** owns colors/fonts; later, **Stylix** (or Nix) can own the same palette declaratively. Avoid running **Stylix + aggressive Plasma overrides** until you know what you want.
- **Contrast and readability** — test in daylight and at night; avoid ultra-low contrast themes for long sessions.
- **Performance** — heavy blur and transparency shaders can cost battery on a laptop; tune after you like the look.

## Strategy — Plasma first, then Stylix

| Phase | Goal | What you do |
|--------|------|-------------|
| **1 — Plasma only** | Lock **colors, fonts, Qt (Kvantum Qt5+Qt6), GTK, icons, wallpaper** in **System Settings** until you are **happy** with how Qt and GTK apps look side by side. | No **Stylix** yet. Use **Colors**, **Fonts**, **Application style**, **GTK application style**, **Global Theme** / window decorations as needed ([Investigation](#investigation--theseus-plasma-6--wayland--framework-13)). Optionally **screenshot** or **export** color scheme names / hex notes for phase 2. |
| **2 — Add Stylix** | Encode the **same** palette and fonts in **`configuration.nix` / Home Manager** and extend consistency to **GRUB, Plymouth, Flatpak GTK**, terminals, etc. | Enable **[Stylix](https://github.com/nix-community/stylix)** per [docs](https://nix-community.github.io/stylix). Expect **some Plasma manual steps** ([upstream note](https://nix-community.github.io/stylix)); treat Stylix as **additive** once phase 1 is stable. |

**Why this order:** Stylix is powerful but **Plasma integration is still evolving**; nailing the look **only in Plasma** avoids fighting two owners. Once colors are settled, Stylix becomes a **declarative copy** of the same decisions rather than a moving target.

## Color categories (phase 1, Plasma)

You do **not** need a giant custom palette on day one. **System Settings → Appearance → Colors** already exposes **roles**; decide how each *family* should behave, then pick or edit a scheme. These categories match how **KDE**, **Kvantum**, and **GTK** themes think about color:

| Category | What it covers | Why it matters |
|----------|----------------|----------------|
| **Surfaces** | **Window** background, **view** / content area, **alternate** list/table rows, **tooltip** background | Layering: what feels “back” vs “card” vs “row stripe”. |
| **Text** | **Normal**, **inactive/disabled**, **placeholder**; text on **selection** (often inverted) | Readability; WCAG-style contrast on your panel resolution. |
| **Accent & focus** | **Selection** background/foreground, **focus** ring/highlight, **hover** (where exposed) | One or two hues carry “this is active / chosen”. |
| **Links** | **Link**, **visited link** (optional distinction) | Browsers and many apps inherit these. |
| **Chrome** | **Titlebar** (active vs inactive), **borders**, **separators** | Window drag targets; tiling borders ([02](./02-functional-improvements.md#framework-ergonomics)). |
| **Controls** | **Button** background/foreground, **input** fields | Kvantum + GTK should feel like the same family. |
| **Semantic** | **Positive / neutral / negative / information** (Plasma uses these in notifications, some widgets) | Errors vs success without inventing new hues ad hoc. |
| **Optional — terminal** | **Kitty** ANSI / theme (often **after** GUI is stable) | Can **match** accent + surfaces or stay deliberately separate. |

**Minimum viable set:** lock **surfaces + text + one accent + selection** first; add **semantic**, **links**, and **chrome** tweaks once the base feels right. **Kvantum** themes ship with their own fills, but they should **harmonize** with the **Plasma color scheme** you pick (or you tune Kvantum after choosing a scheme).

**Custom scheme file:** Save/edit as **`~/.local/share/color-schemes/<Name>.colors`** (e.g. **`LilacAsh.colors`**). The format is plain text (INI-style **`[Colors:…]`** groups + **`Color=…`** lines). After saving, choose that scheme under **System Settings → Appearance → Colors** so Plasma picks it up; **restart** or re-open apps if something caches the old scheme. Keep this file for **Stylix phase 2** or backup.

## Investigation — Theseus (Plasma 6 · Wayland · Framework 13)

**Stack:** **KDE Plasma 6** on **Wayland** — default **panel**, **KRunner** / application launcher, **Spectacle**, **Plasma notifications**. You are **not** on Sway/Hypr/Waybar unless you add them later; ricing here means **System Settings** + **declarative Nix** where it helps.

**Already on the system (NixOS):** **`tokyonight-gtk-theme`**, **Kvantum (Qt5)** (`libsForQt5.qtstyleplugin-kvantum`), **`gtk-engine-murrine`**, **`sassc`**, **`gnome-themes-extra`**, **`kdePackages.kdeplasma-addons`** — confirm in **`~/.config/nixos/configuration.nix`** (`# ricing` / GTK blocks). For **Plasma 6 (Qt6)**, add **`qt6Packages.qtstyleplugin-kvantum`** if not already present ([§ Kvantum](#kvantum--what-it-is-research)). **Investigation:** **Application Style → Kvantum**, **Colors**, **GTK** (GTK2/GTK3), **Kvantum Manager** theme.

| Track | What to try |
|--------|-------------|
| **Plasma shell** | **Workspace behavior → Desktop effects** — blur/transparency vs battery; **Window management → Window decorations** — theme and border width (pairs with **tiling plugin** and “minimum width” issues in [02](./02-functional-improvements.md#framework-ergonomics)). |
| **Fonts** | **System Settings → Fonts** — one **UI** family and one **fixed width**; align **Kitty** (`~/.config/kitty/kitty.conf`) and **fastfetch** so the terminal does not fight Plasma. Optional later: **`fonts.packages`** in **`configuration.nix`** for reproducible font installs. |
| **Icons & cursor** | **Icons** (e.g. Breeze / Papirus); **cursor size** for **125–150%** scaling on the laptop panel. |
| **Wallpaper** | **Image** or **slideshow**; avoid huge files on slow storage at login. |
| **SDDM** | Greeter theme matches session dark/light if you care about the boot → login transition. |
| **Kitty** | Colors + font + optional background — last mile after global font/theme choices ([Phase 2](./02-functional-improvements.md) defers “skin” here). |
| **Reuse Omarchy palette (optional)** | Old **Hypr/Waybar** configs were removed from chezmoi; if you still have **hex values** or exports (backup, screenshots), map them into **Plasma color scheme** + **Kvantum** / **Kitty** rather than re-tuning from scratch. |

**Parallel work:** **[Hotkeys](./02-functional-improvements.md#wm--hotkey-notes)** — layout and bindings are separate from theme, but **tiling + borders** touch both (same **Window rules** / plugin settings).

## Kvantum — what it is (research)

[Kvantum](https://github.com/tsujan/Kvantum) is an **SVG-based theme engine for Qt** (author: Pedram Pourang / Tsu Jan). It is aimed at **KDE** and **LXQt**: it draws **Qt widgets** (buttons, sliders, tabs, menus, toolbars, scrollbars, etc.) using **SVG assets** and a flexible ruleset, so themes can look flat, photorealistic, minimal, or anything in between. The idea descends from **QuantumStyle** / **QSvgStyle**; some code heritage comes from **QtCurve**, **Oxygen**, **Bespin**, etc. ([upstream README](https://github.com/tsujan/Kvantum/blob/master/Kvantum/README.md).)

### What you use it for

| Use | Detail |
|-----|--------|
| **Qt application appearance** | Set **System Settings → Appearance → Application style** to **Kvantum** so **Qt** apps (Dolphin, many KDE apps, Qt-based tools) use your chosen **Kvantum theme** instead of Breeze-only widget styling. |
| **Theme selection & tuning** | **Kvantum Manager** (`kvantummanager`) lists installed themes, previews them, and exposes **per-theme options**: translucency, blur, shadows, button sizes, toolbar behavior, **compositing-related** effects, etc. |
| **Per-application overrides** | You can assign **different Kvantum themes** to specific apps if something clashes (e.g. one app needs a lighter variant). |
| **Custom / third-party themes** | Themes are **folders of SVG + config**; you can install community packs or build your own ([Theme-Config](https://github.com/tsujan/Kvantum/tree/master/doc), [Theme-Making PDF](https://github.com/tsujan/Kvantum/blob/master/doc/Theme-Making.pdf) in the repo). |

### What it does *not* do

- **GTK apps** (Firefox default toolkit, many GNOME apps) — use your **GTK** theme (**Settings → Appearance → Colors** / GTK settings, or **`tokyonight-gtk-theme`** on disk). Kvantum only affects **Qt**.
- **Plasma “chrome” wholesale** — panels, Plasma dialogs, and **window decorations** are partly **Plasma / KWin** theming; Kvantum mainly shapes **client-side Qt widgets** inside windows. You still align **Global Theme**, **Colors**, and **Window decorations** with your Kvantum choice for a coherent look.
- **Non-Qt applications** — no effect.

### Plasma 6 and NixOS

- **Plasma 6** uses **Qt 6** apps. Kvantum **1.1.x** targets Qt6 by default upstream. On **NixOS**, install the **Qt6** style plugin — e.g. **`qt6Packages.qtstyleplugin-kvantum`** — so **Application style → Kvantum** works for Qt6 apps. If you only have **`libsForQt5.qtstyleplugin-kvantum`**, that covers **Qt5** apps; **add the Qt6 package** for a Plasma 6 session ([nixpkgs](https://search.nixos.org/packages) search `kvantum`). Optional: **`qt6Packages.qtstyleplugin-kvantum` themes** / built-in theme sets depending on how nixpkgs splits them.
- After installing, pick **Kvantum** under **Application style**, then open **Kvantum Manager** to select a theme (e.g. **KvSimplicityDark**, **KvMojave**, or a Tokyo Night–like pack if you install one).

### Trade-offs

- **Translucency / blur** in Kvantum can look great but may cost **GPU / compositor** work on a laptop — tune in Kvantum Manager if you care about **power** (ties to [Principles](#principles) and **Desktop effects** in Plasma).

## Typography

- Pick **one UI font** and **one monospace** (NixOS: e.g. Inter, JetBrains Mono, Iosevka — declared via `fonts.packages` or Home Manager).
- Set **hinting / subpixel** expectations (Wayland + your toolkit may differ from X11).

## Color and themes

- **GTK / Qt** — match dark/light and set a single theme (and Qt platform plugin for Wayland if needed).
- **Cursor / icons** — consistent icon theme; cursor size for HiDPI.

## One palette everywhere? (Qt5, Qt6, GTK, fonts, “the rest”)

There is **no single cross‑platform standard** where one config file forces **Qt5, Qt6, GTK2/3/4, Electron, SDDM, and the shell** to read identical colors. In practice you **stack mechanisms** until things look aligned:

| Layer | What propagates |
|--------|-------------------|
| **Fontconfig** | **Fonts** — used by GTK, most Qt apps, terminals, and many GUI toolkits if you set families in Plasma and in **Kitty**/editors. NixOS: **`fonts.packages`** + **`fonts.fontconfig`** (optional). |
| **Plasma (manual but integrated)** | **System Settings → Appearance:** **Colors** (Qt / Plasma), **Fonts**, **Application style** (e.g. Kvantum), and **“Application Style → Configure GNOME/GTK application style”** (or **Colors → GTK**) so **GTK** apps follow a GTK theme that **matches** your Qt look. This is the **native KDE** way to keep GTK beside Qt without extra Nix modules. |
| **Qt5 vs Qt6** | Two widget stacks → often **two style plugins** (e.g. **`qt5`** and **`qt6Packages`** Kvantum). **qt5ct** / **qt6ct** can pin Qt theme settings if something ignores Plasma. |
| **Stylix** ([nix-community/stylix](https://github.com/nix-community/stylix), [docs](https://nix-community.github.io/stylix)) | The closest thing to an **off‑the‑shelf, declarative “one theme”** on **NixOS** + **Home Manager**: **colors, fonts, wallpaper**, and hooks for **GTK**, **Qt**, **GRUB**, **Plymouth**, **some terminals**, **Flatpak** (GTK), etc. **Caveat:** upstream notes **KDE Plasma support is still a work in progress** — expect **some manual steps** or rough edges on Plasma until you validate a config. Good fit if you want **everything in `configuration.nix` / HM** and are willing to tune. |
| **Palette‑only generators** | **[nix-colors](https://github.com/Misterio77/nix-colors)**, **base16.nix** — output **theme fragments** you wire into apps yourself; more control, more assembly. |
| **Flatpak / sandboxed apps** | May need **themes inside the sandbox** or **xdg-desktop-portal** + Stylix/GTK options; Stylix documents GTK Flatpak behavior. |
| **Electron / Chromium / some IDEs** | Often **do not** follow GTK/Qt; **per‑app** dark mode or color overrides may still be needed. |

**Practical takeaway for Theseus:** Follow **[Strategy — Plasma first, then Stylix](#strategy--plasma-first-then-stylix)** — **Plasma Settings + fontconfig + matching GTK + Kvantum (Qt5+Qt6)** first; add **Stylix** only after colors are locked. Until then, **do not** enable Stylix, or keep it minimal so it does not override your Plasma work in progress.

## Compositor / DE layer

**Plasma default:** **panel** + **tray** + **clock** — customize widgets and spacing before adding **Waybar** / **polybar** (extra moving parts on Wayland).

**Other stacks (only if you ever change compositor):** e.g. **Sway/i3/Hypr** — **Wallpaper** / **bar** / **launcher** / **notifications** tooling differs from Plasma’s defaults; **not** on the roadmap for this machine; **KDE/Plasma** is the ricing surface here.

## Shell prompt and CLI polish

- **Prompt** — Starship, powerline, or minimal — keep latency low in large repos.
- **LS colors / fzf** — small wins for daily use.

## Framework display

- **Scaling** — align GTK/Qt/terminal font sizes so UI does not look blown up or tiny on the laptop panel.
- **External monitor** — separate scaling or monitor profiles if you dock often (tooling varies by WM/DE).
- **Keyboard backlight at night** — even **1%** in firmware or DE sliders can still be **too bright** in a dark room. **Investigate** whether you can set a **lower floor** manually (e.g. `**brightnessctl`**, paths under `**/sys/class/leds/**`, Framework + Linux docs, or vendor-specific interfaces) and document what works on your machine.
- **Optional — tie to evening / night mode** — if **night mode** or **reduced blue light** turns on **at sunset** (Redshift, KDE **Night Color**, GNOME **Night Light**, etc.), explore **hooking the same moment** to **dim or cap** keyboard backlight (user script, **systemd** timer/service, or DE-specific automation) so you are not adjusting it by hand every evening.

## Checklist — investigation (in progress)

Work in any order; tick when satisfied or superseded.

- [ ] **Plasma:** Application style (Kvantum + Tokyo Night or chosen theme), **Colors** (dark/light), **GTK** consistent with Qt.
- [ ] **Fonts:** Plasma **Fonts** + **Kitty** + monospace in editors you use daily.
- [ ] **Window decorations:** border width / theme; sanity-check with **tiling plugin** ([02 — Framework ergonomics](./02-functional-improvements.md#framework-ergonomics)).
- [ ] **Icons + cursor** — one coherent set; size for scaling.
- [ ] **Wallpaper** — chosen; login (**SDDM**) does not clash badly with session.
- [ ] **Kitty** — color scheme aligned with Plasma (or deliberately independent).
- [ ] **Optional:** **Night Color** / redshift behavior + **keyboard backlight floor** ([Framework display](#framework-display)).
- [ ] **Optional:** **Omarchy** palette / wallpaper notes recovered from backups (not chezmoi source today).
- [ ] **NixOS:** decide whether to pin **`fonts.packages`** / theme packages declaratively vs Settings-only (Home Manager later: [03](./03-home-manager.md)).
- [ ] **Phase 1 — Plasma only:** [Strategy](#strategy--plasma-first-then-stylix); [color categories](#color-categories-phase-1-plasma); [One palette everywhere?](#one-palette-everywhere-qt5-qt6-gtk-fonts-the-rest) (Kvantum Qt5+Qt6, GTK, fonts).
- [ ] **Phase 2 — Stylix:** after colors are **happy**, add [Stylix](https://nix-community.github.io/stylix) to match Nix-wide ([Stylix docs](https://nix-community.github.io/stylix)).

## Done when

- A screenshot would show **consistent** font, colors, and chrome across terminal, panel, and apps you use most.
- You are not fighting **random** light/dark mismatches after reboot.

## Inspiration (optional)

- Save links to themes you liked in a short list below — not required for done.
- [Kvantum install / build notes](https://github.com/tsujan/Kvantum/blob/master/Kvantum/INSTALL.md) (you already use the **Nix** package; doc is upstream context).
- Tiling windows with **visible borders** — Plasma tiling plugin + **window decorations** (see [Investigation — Theseus](#investigation--theseus-plasma-6--wayland--framework-13)).
- Reuse **palette / wallpaper** from Omarchy — see checklist **Optional** row and archived configs if any.
- (Very optional) **Light/dark toggle** for coding — Plasma **dark/light** session, **Night Color**, or timed schemes.

## Notes

