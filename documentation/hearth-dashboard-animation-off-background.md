# Hearth dashboard "animation off" background — measurement record

Evidence for the Conveyor card *"Investigate a nicer 'animation off' background
than a flat color."* Nick's ask: when the dashboard's **Animate background**
toggle is off it falls back to a flat `--void` color — could we instead render
the shader **once** and leave it frozen, and would that cost more GPU than the
flat fill? Plus his follow-up idea: run the shader **only in the top bar**
(fewer pixels = lighter load?). The card's required deliverable is this
document; implementation is deferred to Nick's aesthetic pick (see
Recommendation).

Related: PR #142 (the "unmount when off" decision and the 112%/85°C finding
behind it), the animation-toggle and theme-picker cards (shipped), and
`hearth-intranet-deploy` (PR #162/#163) — the fast dashboard sync used to
iterate the states below.

## Method

The dashboard renders on the **Go3 wall kiosk** (cage + Chromium), and Go3's
own fanless package temperature is the constraint that made "off" a flat color
in the first place — so the measurement has to be Go3's, not a proxy. Sampled
Go3's loopback stats service (`hosts/Go3/stats-server.nix`,
`http://127.0.0.1:18090/stats.json`) over SSH: `cpu_pct` (whole-system, from
`/proc/stat`) and `cpu_temp_c` (the `x86_pkg_temp` thermal zone), 30 samples at
3 s (20 for the hot full-animated reference), after giving the kiosk ≥130 s to
pick up each build via its `build-id.txt` poll.

Each state was a throwaway probe build (`frameloop`/container forced per state,
Settings/motion gates bypassed) shipped with `hearth-intranet-deploy` and then
reverted; **nothing from the harness is committed** — only this document. The
live dashboard was restored (flat "off") at the end.

Two measurement caveats, stated up front:

- **Report the median, not the mean.** Every state shows brief CPU spikes to
  20–100 % that recur on a ~30 s cadence *regardless of the background* — they
  are the dashboard's own widget/stats-poll compositing, not the shader. They
  inflate the mean; the median is the honest steady-state figure.
- This is whole-system `cpu_pct` + package temperature. PR #142's oft-quoted
  **112 %** was Chromium's `gpu-process` specifically (a different meter); the
  directly comparable PR #142 number here is its **85 °C** package temp.

## Results (Go3, 2026-09-04)

| State | What it is | CPU median | CPU mean* | temp median | temp max |
|---|---|---:|---:|---:|---:|
| **(a) flat "off"** | current behaviour — Canvas unmounted, flat `--void` | ~11 % | 16.3 % | 40–41 °C | 45 °C |
| **(b) frozen geometry** | default shader mounted, `frameloop="never"` (render once) | **11.1 %** | 14.4 % | **41 °C** | 43 °C |
| **(c) frozen Shadertoy** | a toy port (`starfield-gleam`) frozen, `frameloop="never"` | **11.5 %** | 14.2 % | **41 °C** | 45 °C |
| **(d) top-bar live** | shader confined to a 72 px strip, `frameloop="always"` | 45.7 % | 46.3 % | 53 °C | 55 °C |
| **(ref) full animated** | full-screen live shader (the PR #142 state) | 45.7 % | 47.4 % | **81 °C** | 82 °C |

\*mean shown only to expose how much the background spikes skew it; the median
is the figure to compare.

## What the numbers say

1. **A frozen shader frame costs no more than the flat color — this is the
   headline answer.** States (b) and (c) sit at median **11 %** CPU and
   **41 °C**, indistinguishable from the flat "off" baseline (a). Once
   `frameloop="never"` has rendered its single frame, the WebGL context is
   inert and the browser's compositor just re-presents a static bitmap — there
   is no per-vsync redraw, which is the entire cost of the animated state. So
   "render the shader once and leave it static" is a real, GPU-free option, and
   the current unmount-when-off design is stricter than it needs to be for the
   *cost* reason (it remains correct for the `prefers-reduced-motion` reason —
   see below).

2. **Confining the shader to the top bar does NOT buy the cost back — Nick's
   idea, tested and answered.** State (d) is **45.7 %** CPU / **53 °C**, ~4× the
   static states and essentially the same CPU as the full-screen animation. A
   `frameloop="always"` canvas wakes the GPU every vsync no matter how few
   pixels it covers; shrinking it cuts fragment-shading heat (53 °C vs the
   reference's 81 °C) but not the wake-up cost. The top-bar route is a live
   animation with most of the price and less of the payoff — not a "low-GPU"
   option.

3. **The rig detects load and matches history.** The full-animated reference
   hit **81–82 °C** package temp, in line with PR #142's 85 °C, confirming the
   sampling actually captures the expensive state rather than missing it.

## Recommendation (implementation is Nick's aesthetic call)

The numbers make two options clear winners on **cost**; the **looks** decision
is Nick's, so this stops at the recommendation rather than implementing:

- **Nicer default: a frozen shader frame (`frameloop="never"`)** — as cheap as
  flat, but shows the actual background art. *Aesthetic caveat:* freezing an
  `iTime`-driven toy at t≈0 catches an arbitrary moment that may not look good
  (a plasma mid-sweep, a half-populated starfield). The **geometry** shader
  (static wireframe solids) is the safe one to freeze; the toys need an eyeball
  per shader, and possibly a short warm-up before the freeze rather than t=0.
- **Or a theme-derived CSS gradient** — zero JS, zero GPU, guaranteed to look
  intentional, and it follows the active theme automatically (the theme picker
  already exposes `window.hearthThemes`). Not separately measured because a
  static CSS gradient cannot exceed the flat fill's cost.
- **Reject the top-bar-only live shader** on the numbers above.
- **Keep a genuinely-minimal-GPU floor in Settings regardless** (Nick's hard
  constraint, 2026-09-02): the flat color or a CSS gradient. A frozen frame
  measures just as cheap, but the floor option should be one with *no* WebGL
  context at all.
- **Leave the `prefers-reduced-motion` path untouched.** That gate must still
  fully unmount the Canvas — it is an accessibility signal, independent of the
  cost question this document answers.

## Reproducing / open items

- **No screenshots were captured** — Go3 has no `grim` and this run avoided
  installing anything on the kiosk, so the *visual* eyeball (which frozen shader
  looks good static) is still Nick's to do. Any single state can be re-deployed
  on request for him to view on the wall.
- To re-run: re-create the per-state probe (force `frameloop` and the container
  in `hosts/Hearth/intranet/src/visuals/Atmosphere.jsx` / `src/App.jsx`),
  `hearth-intranet-deploy`, wait ~130 s for the kiosk reload, then sample
  `http://127.0.0.1:18090/stats.json` on Go3 and take the **median**.
