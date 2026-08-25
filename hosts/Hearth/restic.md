# Hearth restic restore

Encrypted snapshots of **Hearth mutable state** on COLD. The flake still
builds the OS. This file is the restore runbook.

Repo: `/mnt/cold/backups/hearth-restic`  
Unit: `restic-backups-hearth.service` (daily timer, 7 daily + 4 weekly)  
Password: Bitwarden → `secrets/hearth-restic-password.yaml` (`password:`).
Never print it. After a Hearth switch that includes the secret, the
decrypted file is `/run/secrets/hearth-restic-password` (root, `0400`).

## When to restore

Use a snapshot when **COLD survived** and Hearth lost state on the NVMe:

- NVMe died or you reinstalled; COLD still has the repo
- Jellyfin metadata / users / watches are gone (media on `/mnt/cold/media` is fine)
- Tailscale node key, ACME certs for `home.wizt.org` / `tv.wizt.org`, the
  host age key, or HUD widget `config.nix` copies need to come back

Do **not** restore for:

- The media library — it already lives on COLD, outside this repo
- `/nix/store` or a broken generation — `hearth-deploy` / the flake
- COLD itself missing — there is no snapshot; off-box (Tawa/B2) is a follow-on

## What a snapshot contains

`/var/lib/jellyfin` (no `transcodes` / `cache`), `/var/lib/tailscale`,
`/var/lib/acme`, `/var/lib/sops-nix/key.txt`,
`/var/lib/hearth-intranet/config` (builder copies of gitignored
`hosts/Hearth/intranet/config/*/config.nix`).

## How to restore

1. **Rebuild the OS first** from Tawa so users, units, and mount points
   exist. `hearth-deploy switch` (or `--from-checkout` if the pin is behind).
   Do not `os-rebuild switch --host Hearth` on Tawa.
2. Confirm COLD is mounted (`/mnt/cold` UUID `22C21140C2111A1D`) and the
   repo directory exists.
3. Stop writers for the paths you will replace:

   ```bash
   ssh hearth sudo systemctl stop jellyfin
   # only if restoring Tailscale identity:
   # ssh hearth sudo systemctl stop tailscaled
   ```

4. Restore **into a staging directory**, then place files. Do not
   `restic restore --target /` onto a live root.

   ```bash
   ssh hearth 'restic=$(systemctl cat restic-backups-hearth.service | grep -o "/nix/store/[^ ]*/bin/restic" | head -1)
   sudo "$restic" -r /mnt/cold/backups/hearth-restic \
     --password-file /run/secrets/hearth-restic-password snapshots
   sudo mkdir -p /root/restic-restore
   sudo "$restic" -r /mnt/cold/backups/hearth-restic \
     --password-file /run/secrets/hearth-restic-password \
     restore latest --target /root/restic-restore
   '
   ```

   Use a snapshot id instead of `latest` if you need an older day.
5. Copy the trees you need (examples):

   ```bash
   ssh hearth sudo rsync -a /root/restic-restore/var/lib/jellyfin/ /var/lib/jellyfin/
   ssh hearth sudo rsync -a /root/restic-restore/var/lib/acme/ /var/lib/acme/
   ssh hearth sudo rsync -a /root/restic-restore/var/lib/hearth-intranet/config/ \
     /var/lib/hearth-intranet/config/
   # Tailscale / age key: same pattern; replacing key.txt needs a Hearth switch
   # afterward so sops-nix sees the restored key.
   ```

6. Start services and check: `ssh hearth sudo systemctl start jellyfin` then
   `hearth-deploy health`.
7. Remove `/root/restic-restore` when done.

If `restic` says the repo is locked, `unlock` first (a piped `ls | head`
can leave a stale lock). `check` is integrity only — it does not restore.

Module: `hosts/Hearth/restic.nix`. Missing COLD fails only the backup unit.
`hearth-deploy` recopies widget `config.nix` after switch/boot; a restore of
`/var/lib/hearth-intranet/config` is for when those files are gone on the
builder too.
