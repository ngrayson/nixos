# Backport hyprwm/Hyprland#15833 (merged to main 2026-08-11 as a269fd77, carried
# in no release as of 0.56.2): reset m_draggingTiled per drag.
#
# Without it the flag survives a completed drag of a TILED window, and the next
# drag that dragBegin() rejects -- window not mapped, no workspace, or a
# fullscreen workspace -- re-enters dragEnd() with the stale value. dragEnd()
# then forces a FLOATING window into the dwindle tree and segfaults in
# CDwindleAlgorithm::addTarget, taking the whole session with it. That happened
# on Tawa 2026-09-06 (signal 11, v0.55.4, commit a0136d8c).
#
# Bumping the nixpkgs pin does not help: its newest release is 0.56.2, which
# predates the fix. Drop this overlay once the pinned hyprland contains
# a269fd77 -- check with
#   nix eval --raw '.#nixosConfigurations.Tawa.pkgs.hyprland.version'
# against the upstream changelog.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      hyprland = prev.hyprland.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./patches/hyprland-15833-reset-draggingTiled.patch];
      });
    })
  ];
}
