# H0 remote access — the 2026-08-22 ops accept

Narrative moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H0 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H0's shipped status and the rule
that it is not to be re-opened as a flake task; this file keeps the record of
how it was accepted.

## What shipped

`hosts/Hearth/remote-access.nix` enables key-only `sshd` and Tailscale
(`--ssh`, `--accept-dns=false`). Authorized pubkeys are GitHub `ngrayson`
ed25519 and Tawa `wiz@Tawa` (`~/.ssh/id_ed25519` on the builder).

## Ops accept, 2026-08-22, run from Tawa

Hearth was on GiGstreem `172.16.141.38` at the time; AncientGlade
`192.168.0.133` had no route. `sshd`, `tailscaled`, `jellyfin` and
`display-manager` were all active. Trusted-users `@wheel` and passwordless
sudo were already present on the running generation, so no on-box switch was
needed.

`ssh hearth` over MagicDNS resolved to **Tailscale SSH**, which
`hearth-deploy doctor` warned about because `nix-copy` wants a real sshd. The
OpenSSH path is the LAN address `172.16.141.38` with the Tawa key, so
`Host hearth` in `home/programs/ssh-hearth.nix` targets that IP directly.
MagicDNS Tailscale SSH remains available as `Host hearth-tailnet`.

`hearth-deploy doctor` from Tawa is the standing check.

## Leftovers

Extra Go 2 / Theseus keys and a recorded GC of old Plasma generations are still
outstanding **ops** work — they are not missing flake modules.
