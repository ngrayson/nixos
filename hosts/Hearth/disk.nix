# COLD park/resume: operator script + udisks2 + udev remount on plug-in.
# man systemd-fstab-generator does not list x-systemd.device-bound, so do not
# pass it. Replug starts mnt-cold.mount via udev; park is the graceful unplug.
# park runtime-masks mnt-cold.mount for the unmount->power-off window: the
# fstab-generated mount is WantedBy=local-fs.target and Required by every
# RequiresMountsFor consumer, so the first unit to start after the unmount
# (a per-minute timer, udisks2's own D-Bus activation) re-pulls the mount and
# Jellyfin with it. /run/systemd/system (runtime masks) outranks
# /run/systemd/generator, so the mask beats the generated unit. resume and
# status clean up a mask left behind by an interrupted park.
{pkgs, ...}: let
  # Same UUID as hosts/Hearth/host.nix and scripts/hearth-healthcheck.sh.
  coldUuid = "22C21140C2111A1D";
  hearth-disk = pkgs.writeShellApplication {
    name = "hearth-disk";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.systemd
      pkgs.curl
      pkgs.udisks2
      pkgs.psmisc
      pkgs.procps
    ];
    text = ''
      set -euo pipefail
      # Same UUID as hosts/Hearth/host.nix and scripts/hearth-healthcheck.sh.
      COLD_UUID="${coldUuid}"
      COLD_DEV="/dev/disk/by-uuid/$COLD_UUID"
      COLD_MNT="/mnt/cold"
      COLD_UNIT="mnt-cold.mount"
      # Read-only readers such as hearth-tui's `restic snapshots` (~9 s on the
      # NTFS USB disk) or a daily backup (~13 s) finish on their own; wait
      # them out rather than abort.
      HOLDER_WAIT_SEC=30
      JELLYFIN_HEALTH="http://127.0.0.1:8096/health"

      ok() { printf '[ok]   %s\n' "$*"; }
      fail() { printf '[fail] %s\n' "$*" >&2; }

      usage() {
        cat <<'EOF'
      hearth-disk — park or resume Hearth's USB COLD disk and Jellyfin.

      From Tawa:  hearth-unmount   (zsh alias) or  ssh hearth sudo hearth-disk park
      On Hearth:  sudo hearth-disk park

      Commands:
        status   Probe device, mount UUID, Jellyfin, and :8096/health (no changes)
        park     Stop Jellyfin/Syncthing, wait <=30s for readers, unmount COLD
                 (mount masked meanwhile), power off the enclosure (not the hub)
        resume   Mount COLD and start Jellyfin after the drive is plugged in
      EOF
      }

      need_root() {
        local cmd="$1"
        if [[ "$(id -u)" -ne 0 ]]; then
          fail "hearth-disk $cmd must run as root (stops Jellyfin, unmounts /mnt/cold, powers off the COLD enclosure — not the USB hub)."
          printf 'From Tawa:  hearth-unmount   or   ssh hearth sudo hearth-disk %s\n' "$cmd" >&2
          printf 'On Hearth:  sudo hearth-disk %s\n' "$cmd" >&2
          exit 1
        fi
      }

      device_present() { [[ -e "$COLD_DEV" ]]; }

      mount_uuid() {
        findmnt -n -o UUID "$COLD_MNT" 2>/dev/null || true
      }

      mount_src() {
        findmnt -n -o SOURCE "$COLD_MNT" 2>/dev/null || true
      }

      mount_matches() {
        local uuid src
        uuid="$(mount_uuid)"
        src="$(mount_src)"
        [[ "$uuid" == "$COLD_UUID" ]] || [[ "$src" == *"$COLD_UUID"* ]]
      }

      unexpected_holders() {
        local pid comm leftover=0
        # fuser prints PIDs on stdout; ignore the fuse driver that *is* the mount.
        for pid in $(fuser -m "$COLD_MNT" 2>/dev/null || true); do
          comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
          comm="''${comm## }"
          case "$comm" in
            ntfs-3g|mount.ntfs|mount.ntfs-3g|"") continue ;;
            *)
              leftover=1
              printf 'still using %s: pid %s (%s)\n' "$COLD_MNT" "$pid" "$comm" >&2
              ;;
          esac
        done
        return "$leftover"
      }

      # mask/unmask daemon-reload the manager by default; that reload is what
      # makes the mask bite, so never pass --no-reload.
      mask_mount() { systemctl mask --runtime --quiet "$COLD_UNIT"; }
      # Runs from the EXIT trap and from resume on a machine that may have no
      # mask, so it must never fail the caller.
      unmask_mount() { systemctl unmask --runtime --quiet "$COLD_UNIT" 2>/dev/null || true; }
      mount_masked() { [[ "$(systemctl is-enabled "$COLD_UNIT" 2>/dev/null || true)" == masked-runtime ]]; }

      probe_status() {
        local failed=0
        if device_present; then
          ok "device $COLD_DEV present"
        else
          fail "COLD device missing ($COLD_DEV) — enclosure unplugged or still spinning up"
          failed=1
        fi
        if findmnt "$COLD_MNT" >/dev/null 2>&1 && mount_matches; then
          ok "$COLD_MNT is mounted (UUID $COLD_UUID)"
        else
          fail "$COLD_MNT is not mounted with UUID $COLD_UUID"
          failed=1
        fi
        if systemctl is-active --quiet jellyfin; then
          ok "Jellyfin is active"
        else
          fail "Jellyfin is not active ($(systemctl is-active jellyfin 2>/dev/null || true))"
          failed=1
        fi
        if systemctl is-active --quiet syncthing; then
          ok "Syncthing is active"
        else
          fail "Syncthing is not active ($(systemctl is-active syncthing 2>/dev/null || true))"
          failed=1
        fi
        if curl -fsS --max-time 5 "$JELLYFIN_HEALTH" >/dev/null; then
          ok "Jellyfin health $JELLYFIN_HEALTH"
        else
          fail "Jellyfin health URL failed ($JELLYFIN_HEALTH)"
          failed=1
        fi
        # Keep this row LAST: hearth-tui's decide_disk_action reads the rows
        # positionally (device, mounted, jellyfin, ...).
        if mount_masked; then
          fail "$COLD_UNIT is masked (a park was interrupted) — run: sudo hearth-disk resume"
          failed=1
        else
          ok "$COLD_UNIT is not masked"
        fi
        return "$failed"
      }

      cmd_park() {
        need_root park
        # Every exit path -- success, an abort below, a dropped ssh -- leaves
        # no mask behind (only SIGKILL skips the trap).
        trap unmask_mount EXIT
        # Both services hold files open on COLD. Syncthing especially: it
        # watches share/ and upload/ with fsWatcherEnabled, so a running
        # instance shows up in the unexpected_holders check below and aborts
        # the park. RequiresMountsFor only pulls it down once the mount unit
        # actually stops, which is after that check -- too late.
        systemctl stop jellyfin
        systemctl stop syncthing
        if findmnt "$COLD_MNT" >/dev/null 2>&1; then
          # unexpected_holders names every holder on each call; print them on
          # the first miss and at the abort, not once a second.
          local waited=0 holders
          until holders="$(unexpected_holders 2>&1 >/dev/null)"; do
            if ((waited == 0)); then printf '%s\n' "$holders" >&2; fi
            if ((waited >= HOLDER_WAIT_SEC)); then
              printf '%s\n' "$holders" >&2
              fail "park aborted: those processes still have $COLD_MNT open after ''${HOLDER_WAIT_SEC}s. Close them and retry. Jellyfin and Syncthing are already stopped; the disk is still mounted."
              exit 1
            fi
            printf 'waiting for %s to be released (%ss)\n' "$COLD_MNT" "$waited"
            sleep 1
            waited=$((waited + 1))
          done
          # Mask BEFORE stopping: any unit starting in the next second re-pulls
          # the fstab-generated mount through local-fs.target /
          # RequiresMountsFor. A masked unit can still be stopped; it cannot
          # be started.
          mask_mount
          systemctl stop "$COLD_UNIT"
        else
          # Unmounted but still plugged: the first start job would remount it
          # before udisksctl gets to power it off.
          mask_mount
        fi
        local waits=0
        while findmnt "$COLD_MNT" >/dev/null 2>&1 && ((waits < 50)); do
          sleep 0.1
          waits=$((waits + 1))
        done
        if findmnt "$COLD_MNT" >/dev/null 2>&1; then
          fail "park aborted: $COLD_MNT did not unmount after stopping mnt-cold.mount. Jellyfin and Syncthing are already stopped; the disk is still mounted."
          exit 1
        fi
        if device_present; then
          udisksctl power-off -b "$COLD_DEV" || {
            if device_present; then
              fail "park aborted: $COLD_MNT is unmounted but udisksctl could not power off $COLD_DEV. Do not unplug yet; check the enclosure (leave the USB hub on — fans live there)."
              exit 1
            fi
          }
        fi
        printf 'COLD is safe to unplug. Leave the USB hub plugged in (fans). Replug the enclosure, then run resume to remount and start Jellyfin and Syncthing.\n'
      }

      cmd_resume() {
        need_root resume
        # A park killed between mask and unmask would otherwise make replug
        # (udev) and this start fail with "Unit mnt-cold.mount is masked".
        # Before the device check so resume on an unplugged disk still clears
        # it for the next plug.
        unmask_mount
        if ! device_present; then
          fail "resume aborted: COLD is not plugged in (missing $COLD_DEV)."
          printf 'Plug the enclosure into the hub, wait for the disk to appear, then: sudo hearth-disk resume\n' >&2
          exit 1
        fi
        systemctl start mnt-cold.mount
        systemctl start jellyfin
        # RequiresMountsFor stops a unit when its mount goes away but never
        # starts it again when the mount returns, so this has to be explicit.
        # After jellyfin, which has already proven the mount is usable.
        systemctl start syncthing
        probe_status
      }

      cmd="''${1:-}"
      case "$cmd" in
        status) probe_status ;;
        park) cmd_park ;;
        resume) cmd_resume ;;
        -h|--help|"") usage ;;
        *)
          usage >&2
          exit 1
          ;;
      esac
    '';
  };
in {
  services.udisks2.enable = true;
  environment.systemPackages = [hearth-disk];

  # systemd will not retry mnt-cold.mount after a missed nofail wait, so udev
  # starts it when the UUID appears (late spin-up or replug).
  services.udev.extraRules = ''
    ACTION=="add", ENV{ID_FS_UUID}=="${coldUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-cold.mount"
  '';
}
