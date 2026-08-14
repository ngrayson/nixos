#!/usr/bin/env bash
# Download/verify the official NixOS graphical ISO and write it to a USB stick.
# Safe defaults: remount/non-removable disks are rejected; write requires typing YES.
set -euo pipefail

CHANNEL="${NIXOS_CHANNEL:-nixos-26.05}"
VARIANT="${NIXOS_ISO_VARIANT:-graphical}"
ARCH="${NIXOS_ISO_ARCH:-x86_64-linux}"
CACHE_DIR="${NIXOS_ISO_CACHE:-$HOME/.cache/nixos-installer}"
ISO_BASENAME="latest-nixos-${VARIANT}-${ARCH}.iso"
ISO_URL="${NIXOS_ISO_URL:-https://channels.nixos.org/${CHANNEL}/${ISO_BASENAME}}"
SHA_URL="${NIXOS_ISO_SHA_URL:-${ISO_URL}.sha256}"
ISO_PATH="${CACHE_DIR}/${ISO_BASENAME}"
SHA_PATH="${CACHE_DIR}/${ISO_BASENAME}.sha256"

info()  { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m[ok]\033[0m   %s\n' "$*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--download-only | --write /dev/sdX]

  --download-only   Fetch and verify the ISO, then exit.
  --write DEVICE    Write the verified ISO to DEVICE (destructive).
  -h, --help        Show this help.

Env overrides: NIXOS_CHANNEL, NIXOS_ISO_VARIANT, NIXOS_ISO_ARCH,
               NIXOS_ISO_CACHE, NIXOS_ISO_URL, NIXOS_ISO_SHA_URL
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "Missing required command: $1"
    exit 2
  }
}

download_and_verify() {
  require_cmd curl
  require_cmd sha256sum
  mkdir -p "$CACHE_DIR"

  info "Channel:  $CHANNEL"
  info "ISO URL:  $ISO_URL"
  info "SHA URL:  $SHA_URL"
  info "Cache:    $ISO_PATH"

  info "Fetching published SHA-256…"
  curl -fsSL "$SHA_URL" -o "$SHA_PATH"
  local published
  published="$(awk 'NF { print $1; exit }' "$SHA_PATH")"
  if [[ ! "$published" =~ ^[0-9a-f]{64}$ ]]; then
    error "Could not parse SHA-256 from $SHA_PATH"
    cat "$SHA_PATH" >&2 || true
    exit 1
  fi
  info "Published SHA-256: $published"

  if [[ -f "$ISO_PATH" ]]; then
    local existing
    existing="$(sha256sum "$ISO_PATH" | awk '{ print $1 }')"
    if [[ "$existing" == "$published" ]]; then
      ok "Cached ISO already matches published SHA-256"
      ls -lh "$ISO_PATH"
      return 0
    fi
    warn "Cached ISO hash mismatch; re-downloading cleanly"
    rm -f "$ISO_PATH"
  fi

  info "Downloading ISO…"
  # Do not use curl -C / --continue-at here: a completed file can get
  # trailing bytes appended and fail verification.
  curl -fL --retry 3 -o "$ISO_PATH" "$ISO_URL"

  info "Verifying SHA-256…"
  local actual
  actual="$(sha256sum "$ISO_PATH" | awk '{ print $1 }')"
  if [[ "$actual" != "$published" ]]; then
    error "SHA-256 mismatch"
    error "  published: $published"
    error "  actual:    $actual"
    exit 1
  fi
  ok "ISO verified: $ISO_PATH"
  ls -lh "$ISO_PATH"
}

is_removable_disk() {
  local dev="$1"
  local name rm tran
  name="$(basename "$dev")"
  [[ -b "$dev" ]] || return 1
  # Reject partitions; require whole-disk node.
  [[ -e "/sys/block/$name" ]] || return 1
  rm="$(cat "/sys/block/$name/removable" 2>/dev/null || echo 0)"
  tran="$(lsblk -dn -o TRAN "$dev" 2>/dev/null || true)"
  [[ "$rm" == "1" || "$tran" == "usb" ]]
}

device_is_mounted() {
  local dev="$1"
  findmnt -S "$dev" >/dev/null 2>&1 && return 0
  # Also refuse if any partition of this disk is mounted.
  local part
  while read -r part; do
    [[ -n "$part" ]] || continue
    findmnt -S "$part" >/dev/null 2>&1 && return 0
  done < <(lsblk -ln -o PATH "$dev" | tail -n +2)
  return 1
}

list_usb_candidates() {
  info "Removable / USB whole-disk candidates:"
  local found=0
  local path model size tran rm
  while read -r path model size tran rm; do
    [[ -n "$path" ]] || continue
    if [[ "$rm" == "1" || "$tran" == "usb" ]]; then
      printf '  %s  %s  %s  tran=%s removable=%s\n' "$path" "$size" "$model" "$tran" "$rm"
      found=1
    fi
  done < <(lsblk -dn -o PATH,MODEL,SIZE,TRAN,RM -e 7,11)
  if [[ "$found" -eq 0 ]]; then
    warn "No removable USB disks detected."
  fi
}

write_iso() {
  local target="$1"
  require_cmd lsblk
  require_cmd dd
  require_cmd sync

  if [[ ! -b "$target" ]]; then
    error "Not a block device: $target"
    exit 2
  fi
  if ! is_removable_disk "$target"; then
    error "Refusing to write: $target is not a removable/USB whole-disk device."
    list_usb_candidates
    exit 2
  fi
  local bytes
  bytes="$(lsblk -bn -o SIZE "$target" 2>/dev/null || echo 0)"
  if [[ -z "$bytes" || "$bytes" -eq 0 ]]; then
    error "Refusing to write: $target reports size 0 (No medium / ejected)."
    error "Unplug the USB stick, plug it back in, wait a few seconds, then re-check with:"
    error "  lsblk -o NAME,PATH,MODEL,SIZE,TRAN,RM,LABEL"
    list_usb_candidates
    exit 2
  fi
  if device_is_mounted "$target"; then
    error "Refusing to write: $target (or a partition on it) is mounted."
    error "Unmount first, then re-run."
    lsblk "$target"
    exit 2
  fi
  if [[ ! -f "$ISO_PATH" ]]; then
    error "ISO missing; run download first."
    exit 2
  fi

  # Re-verify before destructive write.
  download_and_verify

  echo
  info "About to DESTROY all data on:"
  lsblk -o NAME,MODEL,SIZE,TYPE,TRAN,RM,MOUNTPOINTS "$target"
  echo
  warn "This will overwrite $target with the NixOS ${CHANNEL} ${VARIANT} installer."
  printf 'Type YES to continue: '
  local confirm
  read -r confirm
  if [[ "$confirm" != "YES" ]]; then
    warn "Aborted."
    exit 0
  fi

  info "Writing ISO with dd (bs=4M, conv=fsync)…"
  sudo dd if="$ISO_PATH" of="$target" bs=4M status=progress conv=fsync oflag=direct
  sync
  ok "Write complete. You can eject the USB and boot the Framework (Secure Boot off)."
}

main() {
  local mode="" target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --download-only) mode=download ;;
      --write)
        mode=write
        shift
        target="${1:-}"
        [[ -n "$target" ]] || { error "--write requires a device path"; exit 2; }
        ;;
      -h|--help) usage; exit 0 ;;
      *) error "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
  done

  if [[ -z "$mode" ]]; then
    usage
    echo
    list_usb_candidates
    exit 2
  fi

  case "$mode" in
    download)
      download_and_verify
      list_usb_candidates
      ;;
    write)
      download_and_verify
      write_iso "$target"
      ;;
  esac
}

main "$@"
