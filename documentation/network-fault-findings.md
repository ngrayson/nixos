# Network fault findings — AncientGlade AP and the Pi Zero W

**Measured 2026-08-30 → 2026-08-31.** An 8-hour instrumented run of the newly
built Pi-hole host found **two independent faults**. Either one alone
disqualifies the current setup from hosting the household's DNS.

Companion to [`router-recommendations.md`](./router-recommendations.md), which
covers the purchase question. This file is the evidence.

## Summary

| # | Fault | Evidence | Status |
|---|---|---|---|
| 1 | **TP-Link AX3000 (AncientGlade) wedges** — LAN/Wi-Fi bridge stops forwarding while WAN stays healthy | Gateway stopped answering ARP; entire `192.168.0.0/24` dark; two independent clients affected; only a power cycle recovered it | Recovered by power cycle. **Recurrence expected — root cause not fixed.** |
| 2 | **Pi Zero W's `wlan0` disappears from the kernel** | Interface vanished from `/proc/net/wireless` at 00:09 and never returned across 473 consecutive samples (~7h54m), while the Pi itself kept running | Mitigation applied (power-save off). **Unverified — awaiting a clean night.** |

## Fault 1 — the AX3000 wedges

Observed 2026-08-31 ~01:00–08:45.

- `192.168.0.1` **did not answer ARP at all** — no entry, so nothing was
  responding at layer 2, let alone routing.
- A full sweep of all 254 addresses on `192.168.0.0/24` returned **nothing**.
- Tawa was *associated* with a valid DHCP lease (`192.168.0.119`, gateway and
  DNS both `192.168.0.1`, NetworkManager reporting `activated`) yet had **100%
  packet loss to the gateway**. A forced down/up reassociation did not help.
- **The radio kept beaconing throughout** — `AncientGlade` and
  `AncientGlade-5G` both visible at normal signal across repeated scans. The AP
  looked alive, which is what makes this failure mode deceptive.
- **The WAN side stayed healthy**: `172.16.141.4` remained ARP-reachable on the
  GiGstreem segment with MAC `40:ed:00:ab:bd:49`, one digit off the LAN
  gateway's `40:ed:00:ab:bd:48` — same device, two interfaces.
- **Two independent clients** were affected simultaneously (Tawa and the Pi),
  ruling out a client-side cause.
- A power cycle restored it immediately: gateway went from 100% loss to 0%.

**Cabling was ruled out.** The topology is GiGstreem → switch → AX3000 **WAN**,
with **nothing in the LAN ports** — all AncientGlade clients are wireless. There
is no second path, so a switching loop is not possible.

**Even after recovery the AP is not healthy.** Four pings to a device in the
same room: min 2.4 ms, max 192 ms, avg 83 ms. A healthy AP is consistently low
single digits.

This is materially stronger evidence than the "clients drop on AncientGlade"
symptom recorded in `router-recommendations.md`. That framing suggested a
tuning problem (band steering, channel choice). This is a **router that stops
forwarding entirely and requires physical intervention** — a hardware/firmware
fault that no amount of Smart Connect or channel configuration will fix.

## Fault 2 — the Pi's Wi-Fi interface vanishes

From `/var/log/pihole-linkmon-night1.log` (60-second samples, 8 hours):

- **478 samples. Gateway reachable in 2. Unreachable in 476.**
- Signal was **−20 dBm** (essentially touching the router) for the 5 samples
  where the interface still reported.
- At **00:09** `wlan0` stopped appearing in `/proc/net/wireless` entirely — not
  a deassociation, the interface was **gone from the kernel** — and never
  returned for the remaining **473 samples**.
- **The Pi itself was fine.** The monitor ran its full 8-hour course and
  finished cleanly at 08:03. It was alive with no network interface, not hung.
- It did **not** recover when the AP came back; it needed a reboot.

**Moving the Pi beside the router did not help.** Signal improved from −59 dBm
to −20 dBm and the interface still died six minutes later. Range and placement
are ruled out.

This is the signature of a `brcmfmac` (Broadcom SDIO) driver/firmware failure,
a known weakness of the Pi Zero W's radio. **Not confirmed from logs** — see
the journald note below.

## Changes applied 2026-08-31

| Change | Where | Why |
|---|---|---|
| Wi-Fi power-save **disabled** | `nmcli … 802-11-wireless.powersave 2` on `netplan-wlan0-AncientGlade`, plus `/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf` so it survives netplan regeneration | Standard mitigation for `brcmfmac` interface dropouts; the leading theory for fault 2 |
| **Persistent journald** | `/etc/systemd/journald.conf.d/99-persistent.conf` (`Storage=persistent`, 200 M cap, 1-month retention) | Raspberry Pi OS ships `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` keeping logs **in RAM** to spare the SD card. Creating `/var/log/journal` is *not* enough — the override must sort later and journald needs `journalctl --flush`. **This is why fault 2 has no driver-level log evidence: the logs died with the reboot.** |
| Monitor moved to `/usr/local/bin/linkmon.sh` | was `/tmp`, cleared on reboot | so it survives restarts |
| `/root/.curlrc` with stall detection | `speed-limit 1000`, `speed-time 30`, retries | the Pi-hole installer's `curl` has no stall timeout and hung indefinitely on this link |

**Tradeoff worth knowing:** persistent journald increases SD-card writes, on a
card that is ~5 years old and already served ~33 M Pi-hole queries. Diagnosis
was judged worth the wear; revert `99-persistent.conf` once the faults are
resolved.

## Equipment on hand

| Device | State | Notes |
|---|---|---|
| **TP-Link AX3000** | Active as `AncientGlade` | WAN `172.16.141.4` → LAN `192.168.0.0/24`. **Faulty — see fault 1.** Wi-Fi 6, Address Reservation, EasyMesh. |
| **GL.iNet GL-SFT1200 "Opal"** | Spare, unplugged | Wi-Fi 5 AC1200, dual-core 1 GHz, 128 MB RAM, 3× gigabit (1 WAN / 2 LAN), USB 2.0. OpenWrt-based. **Untested — see next steps.** |
| **Raspberry Pi Zero W** | Running as `PiHole`, `192.168.0.20` | armv6l, 512 MB, **2.4 GHz only, no ethernet**. Raspbian 13 (trixie), Pi-hole Core v6.4.3 / Web v6.6 / FTL v6.7. |
| **Ethernet switch** | In use | Carries GiGstreem → AX3000 WAN. PoE status unverified. |
| **USB gigabit NIC (ASIX AX88179B)** | Attached to Hearth, **faulty** | Re-enumerates ~every 10–20 s (492 `cdc_ncm` re-registrations in one hour). Binds `cdc_ncm`, not `ax88179_178a`. Separate card; blocked on a powered hub. |
| **GiGstreem gateway** | ISP-provided, `172.16.141.1` | **Cannot be removed.** No DHCP reservations. DNS not under our control — which is why Pi-hole targets AncientGlade. |

## Next steps

1. **Tonight's run tests the power-save fix in isolation.** Monitor restarted
   09:14 with power-save disabled and nothing else changed. Early samples:
   −16 dBm, gateway up, 6.3 ms — against 312 ms in night 1's first sample.
2. **Do not swap the router at the same time.** Power-save was already changed;
   changing the AP too would confound the result. If the Pi survives the night,
   fault 2 is fixed. If it dies again, fault 2 is not power-save.
3. **Then try the Opal** — as a diagnostic it is free and isolates the
   variable. Best run in **AP/bridge mode off the switch with its own SSID**,
   with only the Pi joined: that avoids a third NAT layer and leaves
   `AncientGlade` undisturbed for the household's 2.4 GHz smart-home devices,
   which are provisioned against that SSID.
4. **Neither fault is resolved enough to put household DNS on this pair.** The
   LAN-DNS card should stay gated until the Pi holds a link for a full night
   *and* the AP stops wedging.

## Open questions

- Is fault 1 load-related, thermal, or uptime-related? Unknown — it wedged once
  under observation. Worth noting how long the AP had been up.
- Does the Opal hold a link where the AX3000 does not? Untested.
- Would a Pi Zero **2** W (aarch64, different radio) avoid fault 2 entirely?
  ~$15, and unlike the Zero W it is a platform nixpkgs supports — though the
  standing decision is that this Pi stays out of the flake regardless.
