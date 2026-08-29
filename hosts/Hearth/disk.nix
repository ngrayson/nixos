# COLD park/resume: operator script + udisks2 + udev remount on plug-in.
# man systemd-fstab-generator does not list x-systemd.device-bound, so do not
# pass it. Replug starts mnt-cold.mount via udev; park is the graceful unplug.
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
        park     Stop Jellyfin, unmount COLD, power off the enclosure (not the hub)
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
        if curl -fsS --max-time 5 "$JELLYFIN_HEALTH" >/dev/null; then
          ok "Jellyfin health $JELLYFIN_HEALTH"
        else
          fail "Jellyfin health URL failed ($JELLYFIN_HEALTH)"
          failed=1
        fi
        return "$failed"
      }

      cmd_park() {
        need_root park
        systemctl stop jellyfin
        if findmnt "$COLD_MNT" >/dev/null 2>&1; then
          if ! unexpected_holders; then
            fail "park aborted: those processes still have $COLD_MNT open. Close them and retry. Jellyfin is already stopped; the disk is still mounted."
            exit 1
          fi
          systemctl stop mnt-cold.mount
        fi
        local waits=0
        while findmnt "$COLD_MNT" >/dev/null 2>&1 && ((waits < 50)); do
          sleep 0.1
          waits=$((waits + 1))
        done
        if findmnt "$COLD_MNT" >/dev/null 2>&1; then
          fail "park aborted: $COLD_MNT did not unmount after stopping mnt-cold.mount. Jellyfin is already stopped; the disk is still mounted."
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
        printf 'COLD is safe to unplug. Leave the USB hub plugged in (fans). Replug the enclosure to remount and start Jellyfin.\n'
      }

      cmd_resume() {
        need_root resume
        if ! device_present; then
          fail "resume aborted: COLD is not plugged in (missing $COLD_DEV)."
          printf 'Plug the enclosure into the hub, wait for the disk to appear, then: sudo hearth-disk resume\n' >&2
          exit 1
        fi
        systemctl start mnt-cold.mount
        systemctl start jellyfin
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
