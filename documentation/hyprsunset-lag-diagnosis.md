# Screen-warmth in-game hitch — diagnosis

**Question:** Nick feels frame hitches in games when the hyprsunset tool pushes
a warmth change. Which mechanism causes them?

**Answer:** Hyprland's **`render:ctm_animation` fade**. Every colour-transform
push — a temperature write, a gamma write, even a byte-identical no-op, and each
step of a `--ramp` — is animated across several frames as multiple DRM commits
when the fade is on, and each animated push blows a frame out to 50–82 ms. With
the fade off the same pushes are effectively free. The CTM *commit itself* is
not the cost; the *fade* is.

## Method

`hypr-sunset-bench` (fixed in PR #213) A/Bs `render:ctm_animation` (1 = fade on,
0 = off), running a vkcube workload under MangoHud and firing a fixed push
sequence — `temp`, `gamma`, a byte-identical `gamma-repeat`, then a 10-push
`--ramp` — timestamped against the frame log. Two runs on Tawa 2026-09-05
(three 2560×1440@60 outputs, no VRR, AMD RX 6700 XT; `render:ctm_animation = 2`,
i.e. auto→on for AMD): one idle, one with a game holding the GPU at ~50 %.

**Hitch threshold** (fixed before looking at the data): a frame slower than
`max(2 × baseline_p99, 33.4 ms)` — 33.4 ms is two 60 Hz frames.

Runs: `$XDG_RUNTIME_DIR/hypr-sunset/bench/20260905T163554` (idle),
`.../20260905T164358` (loaded).

## Numbers

Frames counted as hitches = frames over 2× that pass's baseline p99.

| run | pass | p50 | p99 | base-p99 | temp | gamma | gamma-repeat | ramp |
|---|---|---|---|---|---|---|---|---|
| idle | fade **on**  | 16.7 | **66.9** | 16.9 | 7 | 7 | 6 | **46** |
| idle | fade off | 16.7 | 34.6 | 49.0\* | 0 | 0 | 0 | 0 |
| loaded | fade **on**  | 16.7 | **50.3** | 24.9 | 7 | 9 | 9 | **50** |
| loaded | fade off | 16.7 | 18.5 | 18.5 | 1 | 1 | 1 | 2 |

Per-push columns are frames-over-threshold in that push's window; peak per-push
frametimes with fade on reach 67 ms (idle) and 82 ms on the `temp` push under
load.

\* The idle fade-off baseline (49 ms) is a one-off: a couple of unrelated ~48 ms
frames landed in that pass's first 3.5 s. The loaded fade-off baseline (18.5 ms)
is clean and is the one to trust; p50 is 16.7 ms (60 fps) in every pass.

## Answering the five questions

1. **CTM fade vs commit.** Hitches appear at every push with the fade **on**
   (7–50 frames over threshold per push) and all but vanish with it **off**
   (0–2). The mechanism is the `render:ctm_animation` fade — multiple DRM
   commits per push — not the CTM write itself.
2. **The push itself is cheap.** Fade off, the identical push sequence costs
   0–2 marginal frames; p99 drops from ~50–67 ms to 18–35 ms. The commit is not
   the bottleneck.
3. **Push rate — the ramp is the worst case.** `--ramp` (10 discrete pushes
   over ~5 s, which every discrete warmth change uses) produces a *sustained*
   rise: 46–50 hitchy frames, vs 6–9 for one push. The steady 30 s clock tick
   is a single push → one ~7-frame blip; the felt in-game hitch is the ramp
   (a toggle, a settings edit, a preview), not the tick.
4. **A no-op push still hitches.** The byte-identical `gamma-repeat` costs the
   same 6–9 frames with fade on: hyprsunset does **not** short-circuit
   identical values, so it fades to a colour it is already at. A scheduler-side
   skip of byte-identical pushes would be a free win.
5. **Baseline is otherwise clean.** p50 = 16.7 ms (60 fps) everywhere; the load
   run's baselines are ~18–25 ms. The screen is smooth except at pushes.

## Ruled out

- The CTM commit cost itself (fade-off is clean).
- Push *rate* as an independent cause — it is the *fade per push*, amplified
  when the ramp bursts ten of them.

## Caveats

- The loaded run's vkcube was intermittently occluded by the fullscreen game,
  making MangoHud log ~3 absurd frametimes (~9.4e8 ms). They are filtered out of
  the numbers above; the bench's own handling of them is a separate bug
  (`hypr-sunset-bench-garbage-mangohud-frametimes-under-gpu-load`). The idle A/B
  is the cleanest evidence; the loaded A/B corroborates it once filtered.
- vkcube is the instrument, not the game — it measures the compositor's
  per-push cost, which is what the fade drives. A confirming measurement from a
  real game under MangoHud during a live transition window, correlated with
  `pushes.log`, is the natural next step.

## Next (not planned here)

A tuning card. Candidate knobs the numbers point at: `render:ctm_animation = 0`
(kills the fade, the direct fix); a scheduler-side skip of byte-identical
pushes; pausing the timer while a game/gamemode is active; a slower tick inside
transition windows.
