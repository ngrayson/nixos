# H4 headless flip — module and home-manager specifics

Detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H4 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H4's status, its ordering rule
and the open battery-policy question; this file keeps the build detail.

## The profile

A new `profiles/media-server.nix`: `base.nix` plus openssh, tailscale and the
Jellyfin prerequisites — and **no** SDDM, Hyprland, PipeWire-desktop or
home-manager GUI modules.

## The slim home-manager set

Home-manager shrinks to shell-only: `zsh`, `git`, `fastfetch`, `micro`. The
Ghost theme survives in kitty and fastfetch as rendered by *client* terminals
over SSH. Wallpaper, Hyprland, quickshell, dunst and albert are all dropped.

## Applying it

Use `boot` plus a reboot for the flip rather than `switch`. The previous
desktop generation stays in systemd-boot as the recovery path.

## Lid policy

With no session running, logind still governs the lid. Keep
`HandleLidSwitchExternalPower = ignore`. Whether to set `HandleLidSwitch =
ignore` as well is the live question: the battery-as-UPS role argues that AC
loss should not suspend the server, while suspend-on-battery preserves the cell
at the cost of killing in-flight streams. Idle suspend is already ruled out by
decision 17. This is open question 4 in plan.md.

## Acceptance

Boots to multi-user with no greeter, all services up, SSH and Tailscale
reachable, and power draw acceptable.
