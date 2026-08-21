# Phase 6 (low priority): smart-home + media ecosystem research

Candidates to evaluate for Hearth once Jellyfin is stable. Research only — no
installs planned yet. All of these have first-class NixOS modules unless noted.

## Hub

- **Home Assistant** (`services.home-assistant`): the obvious integration hub
  for everything below (lighting, sensors, media control). Native NixOS module
  is well maintained; component list is declarative (`extraComponents`).
  Alternative: run the official container via `virtualisation.oci-containers`
  if component packaging becomes a fight (Tawa's docker pattern exists).
- **Mosquitto** (`services.mosquitto`): MQTT broker; prerequisite for
  zigbee2mqtt/ESPHome-over-MQTT patterns.

## Audio

- **Music Assistant** (`services.music-assistant`): multi-room audio,
  integrates with Home Assistant and can use Jellyfin libraries as a source.
- **Navidrome** (`services.navidrome`): lightweight Subsonic-compatible music
  server — only if Jellyfin's music UX disappoints.
- **Snapcast** (`services.snapserver`): synchronized multi-room playback;
  pairs with MPD or Music Assistant.
- Note: the repo already has spotifyd (HM, workstation hosts) and librespot;
  a Spotify Connect endpoint on Hearth would be a tiny addition.

## Lighting

- **zigbee2mqtt** (`services.zigbee2mqtt`): needs a Zigbee USB coordinator
  (SONOFF ZBDongle-E / ConBee III). Best path for Hue/IKEA/Aqara without
  vendor hubs; feeds Home Assistant via MQTT.
- **ESPHome** (`services.esphome`): custom ESP32 lighting/LED strips (WLED is
  the simpler firmware alternative for addressable strips — no NixOS service
  needed, just the flasher).

## Plant water / moisture detection

- **ESPHome + capacitive soil moisture sensors** on ESP32: cheapest and most
  hackable; dashboards + alerts via Home Assistant.
- **Xiaomi MiFlora / HHCC BLE sensors**: off-the-shelf; Home Assistant reads
  them over BLE — the Surface's Bluetooth radio could do this directly, or an
  ESP32 BLE proxy extends range.
- Alerting path: Home Assistant automation -> phone notification when moisture
  drops below threshold.

## Adjacent media services (later maybes)

- **Audiobookshelf** (`services.audiobookshelf`): audiobooks/podcasts.
- **Immich** (`services.immich`): photo library; heavier (ML), watch RAM on
  the Surface.
- **The *arr stack** (`services.sonarr`/`radarr`/`prowlarr`): media
  acquisition automation; pairs with the existing deluge usage on workstations.
- **Frigate** (`services.frigate`): camera NVR — likely too heavy for this
  machine; note only.

## Hardware constraints to keep in mind

Surface Pro: limited RAM/storage, single internal disk, USB ports scarce (a
powered hub would be needed for Zigbee dongle + external media disk). Prefer
services that are idle-cheap; Home Assistant + Mosquitto + zigbee2mqtt +
Jellyfin is a realistic ceiling.

## Suggested evaluation order

1. Home Assistant (core value, zero extra hardware)
2. MiFlora BLE plant sensors (uses built-in Bluetooth)
3. Music Assistant or Spotify Connect endpoint
4. zigbee2mqtt + dongle (lighting)
5. ESPHome projects (custom sensors/lighting)
