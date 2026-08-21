# Phase 5: Jellyfin media host

Goal: Hearth serves media via Jellyfin on the LAN, keeps running with the lid
closed on AC power, and can hardware-transcode on the Intel iGPU.

## 1. `hosts/Hearth/jellyfin.nix` (new, adapted from `hosts/Tawa/jellyfin.nix`)

Copy Tawa's module (host-local duplication is deliberate — zero risk to Tawa;
promote to `common/` later only if the two ever need to stay in lockstep):

```nix
# Jellyfin media server. Web UI: http://hearth:8096
{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/media 0775 jellyfin jellyfin -"
    "d /srv/media/movies 0775 jellyfin jellyfin -"
    "d /srv/media/tv 0775 jellyfin jellyfin -"
    "d /srv/media/music 0775 jellyfin jellyfin -"
  ];

  users.users.wiz.extraGroups = ["jellyfin"];
  users.users.jellyfin.extraGroups = ["video" "render"];

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Intel iGPU VAAPI for transcoding (enable VAAPI in Dashboard -> Playback).
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # iHD, Broadwell+
      libva-vdpau-driver
      intel-compute-runtime
    ];
  };
}
```

(Confirm which Surface Pro generation this is — `lscpu` — older gens may need
`intel-vaapi-driver` (i965) instead of `intel-media-driver`.)

## 2. Media-host power policy (`hosts/Hearth/host.nix` addition)

`common/base.nix` doesn't touch logind, and the slim profile shouldn't either;
set it host-side so a closed lid doesn't kill the server:

```nix
services.logind.settings.Login = {
  HandleLidSwitch = "suspend";              # on battery: still a laptop
  HandleLidSwitchExternalPower = "ignore";  # on AC: stay up, keep serving
  HandlePowerKey = "ignore";
  HandlePowerKeyLongPress = "poweroff";
};
```

Also consider (decide at implementation):
- disable hypridle suspend-on-idle for Hearth (idle lock + DPMS ok; suspend
  would kill playback for clients) — theme/hosts-style host conditional or
  simply omit hypridle's suspend listener in the slim HM
- `networking.networkmanager.wifi.powersave = false` if Wi-Fi latency shows up
  during streaming

## 3. Media storage

The Surface has a single internal disk (`/` ext4). `/srv/media` lives there
initially. If an external USB drive is added later: mount by UUID under
`/srv/media` via a `fileSystems` entry in `host.nix` (`nofail` option so boot
doesn't hang without it).

## Verification

- `http://<hearth-ip>:8096` reachable from another machine on the LAN
- First-run wizard; library at `/srv/media`; `wiz` can copy files in without sudo
- Playback with transcoding: `sudo intel_gpu_top` (package `igt-gpu-tools`)
  shows video engine load when transcoding; jellyfin logs show VAAPI
- Close lid on AC: server keeps responding
