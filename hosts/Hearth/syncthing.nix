# Seedbox ingest transport (plan.md H8). The Ultra.cc slot downloads and
# hardlinks into its own organized library; Hearth pulls that tree down over
# plain Syncthing. Hearth never seeds and never torrents locally.
#
# Plain Syncthing, no tailnet join and no VPN: Ultra.cc's app catalogue has no
# Tailscale, and Syncthing does not need one — device-ID auth over its own TLS,
# with hole-punching and relay fallback across Hearth's double NAT. Do not
# install Ultra's WireGuard as a substitute, and do not put the FrootVPN
# workstation stack (common/vpn-vortix.nix) on this host.
#
# TWO UNIDIRECTIONAL FOLDERS, not one bidirectional:
#
#   hearth-library  slot ~/library      Send Only  -> /mnt/cold/share   Receive Only
#   hearth-upload   /mnt/cold/upload    Send Only  -> slot ~/upload     Receive Only
#
# A single Send & Receive folder makes deletions round-trip: when the routing
# step moves a file out of /mnt/cold/share, Syncthing would propagate that
# deletion up to the slot's ~/library, where Sonarr/Radarr mark the episode
# missing and re-grab it — an unbounded re-download loop against a shared-disk
# quota. Splitting the directions removes the class of problem.
#
# /mnt/cold/share is a LANDING ZONE, never the library. Anything consuming it
# must hardlink out into /mnt/cold/media/{movies,tv}, never move: moving a file
# out of a Receive Only folder leaves it permanently out-of-sync, and the only
# remedy Syncthing offers ("Revert Local Changes") re-downloads everything.
#
# Identifying values — device ID, both folder IDs, slot paths — live encrypted
# in secrets/hearth-seedbox.yaml because this repo is public. They are applied
# at runtime by syncthing-seedbox-pair below rather than written into the Nix
# store, which is world-readable. Until that file exists this module still
# evaluates: Syncthing runs, and only the pairing step is skipped.
{
  config,
  lib,
  pkgs,
  ...
}: let
  seedboxSecrets = ../../secrets/hearth-seedbox.yaml;
  haveSeedbox = builtins.pathExists seedboxSecrets;

  secretPath = name: config.sops.secrets."hearth-seedbox-${name}".path;

  # Reconciles the device and the two folders against Syncthing's live config.
  # Idempotent: existing entries are updated in place, missing ones created.
  pairScript = pkgs.writeShellApplication {
    name = "syncthing-seedbox-pair";
    runtimeInputs = [pkgs.curl pkgs.jq];
    text = ''
      set -euo pipefail

      config_xml="/var/lib/syncthing/.config/syncthing/config.xml"
      gui="http://127.0.0.1:8384"

      for _ in $(seq 1 30); do
        [ -r "$config_xml" ] && break
        sleep 2
      done
      if [ ! -r "$config_xml" ]; then
        echo "syncthing config.xml never appeared; nothing to pair" >&2
        exit 1
      fi

      api_key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$config_xml" | head -1)
      if [ -z "$api_key" ]; then
        echo "could not read Syncthing API key" >&2
        exit 1
      fi

      # Wait for the REST API to answer before configuring anything.
      for _ in $(seq 1 30); do
        if curl -sf -H "X-API-Key: $api_key" "$gui/rest/system/ping" >/dev/null; then
          break
        fi
        sleep 2
      done

      device_id=$(cat "$DEVICE_ID_FILE")
      folder_library=$(cat "$FOLDER_LIBRARY_FILE")
      folder_upload=$(cat "$FOLDER_UPLOAD_FILE")

      api() { curl -sf -H "X-API-Key: $api_key" -H "Content-Type: application/json" "$@"; }

      # Device: the Ultra.cc slot. "dynamic" lets discovery and relays find it.
      device_json=$(jq -n --arg id "$device_id" '{
        deviceID: $id,
        name: "ultra-seedbox",
        addresses: ["dynamic"],
        autoAcceptFolders: false
      }')
      if api "$gui/rest/config/devices/$device_id" >/dev/null 2>&1; then
        api -X PUT --data "$device_json" "$gui/rest/config/devices/$device_id" >/dev/null
      else
        api -X POST --data "$device_json" "$gui/rest/config/devices" >/dev/null
      fi

      # Folders. Receive Only for acquisitions down, Send Only for the offsite
      # copy up. File Versioning for hearth-upload lives on the slot side.
      #
      # ignorePerms is mandatory, not a preference: both paths are on COLD,
      # which is NTFS via ntfs-3g mounted uid=0 gid=989 umask=0002. Permission
      # bits come from the mount options and chmod(2) is not supported, so with
      # the default (sync permissions) every pull dies with
      #   handling dir (setting permissions): chmod ...: operation not permitted
      # and Syncthing aborts the WHOLE folder cycle and backs off — files land
      # as .syncthing.*.tmp and are never renamed into place.
      put_folder() {
        folder_id="$1"; label="$2"; path="$3"; type="$4"
        folder_json=$(jq -n \
          --arg id "$folder_id" --arg label "$label" \
          --arg path "$path" --arg type "$type" --arg dev "$device_id" '{
            id: $id,
            label: $label,
            path: $path,
            type: $type,
            devices: [{deviceID: $dev}],
            fsWatcherEnabled: true,
            rescanIntervalS: 3600,
            ignorePerms: true
          }')
        if api "$gui/rest/config/folders/$folder_id" >/dev/null 2>&1; then
          api -X PUT --data "$folder_json" "$gui/rest/config/folders/$folder_id" >/dev/null
        else
          api -X POST --data "$folder_json" "$gui/rest/config/folders" >/dev/null
        fi
      }

      put_folder "$folder_library" "hearth-library" "/mnt/cold/share" "receiveonly"
      put_folder "$folder_upload" "hearth-upload" "/mnt/cold/upload" "sendonly"

      echo "paired Ultra.cc slot; folders hearth-library (receiveonly) and hearth-upload (sendonly) applied"
    '';
  };
in {
  # /mnt/cold/share already exists (hosts/Hearth/jellyfin.nix tmpfiles). The
  # upload side is new and belongs to this module.
  systemd.tmpfiles.rules = [
    "d /mnt/cold/upload 0775 wiz jellyfin -"
  ];

  sops.secrets = lib.mkIf haveSeedbox {
    hearth-seedbox-device-id = {
      sopsFile = seedboxSecrets;
      key = "syncthing/device_id";
      owner = "wiz";
      group = "jellyfin";
      mode = "0440";
    };
    hearth-seedbox-folder-library = {
      sopsFile = seedboxSecrets;
      key = "syncthing/folder_hearth_library";
      owner = "wiz";
      group = "jellyfin";
      mode = "0440";
    };
    hearth-seedbox-folder-upload = {
      sopsFile = seedboxSecrets;
      key = "syncthing/folder_hearth_upload";
      owner = "wiz";
      group = "jellyfin";
      mode = "0440";
    };
  };

  services.syncthing = {
    enable = true;
    # Runs as wiz so it can write /mnt/cold/share (wiz:jellyfin 0775).
    user = "wiz";
    group = "jellyfin";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/.config/syncthing";

    # GUI stays on loopback. Reach it over the tailnet with an SSH tunnel; it
    # must never be exposed to GiGstreem/WAN.
    guiAddress = "127.0.0.1:8384";

    # Opens 22000/tcp+udp and 21027/udp — the sync protocol and local
    # discovery, which DO need to reach the internet for the Ultra leg. This
    # option does not open the GUI port.
    openDefaultPorts = true;

    # The device and folders are applied at runtime from sops, so the module
    # must not prune what it cannot see declared here.
    overrideDevices = false;
    overrideFolders = false;

    settings = {
      options = {
        urAccepted = -1;
        relaysEnabled = true;
        natEnabled = true;
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
      };
    };
  };

  # Syncthing's state and both synced trees live on COLD.
  systemd.services.syncthing = {
    after = ["mnt-cold.mount"];
    wants = ["mnt-cold.mount"];
    unitConfig.RequiresMountsFor = ["/mnt/cold"];

    # The upstream module only creates dataDir for its own `syncthing` user
    # (users.users is guarded by `cfg.user == defaultUser`, with createHome).
    # This host runs the daemon as wiz instead, so nothing creates
    # /var/lib/syncthing and the daemon dies on every start with
    # "mkdir /var/lib/syncthing: permission denied" until it hits the restart
    # limit, taking syncthing-init and syncthing-seedbox-pair down with it.
    # StateDirectory makes systemd create it owned by User/Group.
    serviceConfig = {
      StateDirectory = "syncthing";
      StateDirectoryMode = "0700";
    };
  };

  systemd.services.syncthing-seedbox-pair = lib.mkIf haveSeedbox {
    description = "Pair Hearth's Syncthing with the Ultra.cc slot";
    after = ["syncthing.service"];
    requires = ["syncthing.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "wiz";
      Group = "jellyfin";
      ExecStart = lib.getExe pairScript;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    environment = {
      DEVICE_ID_FILE = secretPath "device-id";
      FOLDER_LIBRARY_FILE = secretPath "folder-library";
      FOLDER_UPLOAD_FILE = secretPath "folder-upload";
    };
  };
}
