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
| 2 | **Pi Zero W's `wlan0` disappears from the kernel** | Interface vanished from `/proc/net/wireless` at 00:09 and never returned across 473 consecutive samples (~7h54m), while the Pi itself kept running | **RESOLVED (2026-09-01)** by disabling Wi-Fi power-save. 15h32m continuous uptime spanning the 00:09 failure hour, zero driver errors. See "Run 2" below. |

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

## Run 2 (2026-08-31 → 09-01, power-save disabled) — fault 2 resolved

Restarted 09:14 after disabling Wi-Fi power-save, with the AP freshly power
cycled. Instrumented from **two independent vantage points**, which run 1
lacked — that is what distinguishes an AP-wide failure (both observers lose the
gateway) from a Pi-only one (Pi dark, gateway still fine from Tawa).

**Result: the Pi has held `wlan0` for 15h32m continuously, spanning the 00:09
hour at which run 1 failed.** Verified 2026-09-01 09:32; booted 2026-08-31
17:59:40.

| Metric | Run 1 (night) | Run 2 |
|---|---|---|
| Continuous uptime across 00:09 | interface dead from 00:09 | **15h 32m, unbroken** |
| Gateway unreachable, from the Pi | **476 / 478** | **0** |
| `wlan0` missing from the kernel | 473 samples | **0** |
| `brcmfmac` errors in journal | (logs lost — volatile) | **0** of 74 wifi log lines |
| Signal | −20 dBm then gone | steady −13 to −18 dBm |
| RTT | 312 ms in the first sample | 6–12 ms |

**Tawa's independent observer, 543 samples over 10h (10:25 → 20:25):**

- Gateway reachable in **543 / 543** — **fault 1 did not recur**
- Never roamed off `AncientGlade` (run 1 saw it silently fail over to
  GiGstreem twice, producing false "the Pi is gone" readings)
- Pi unreachable in **5** samples, all **Pi-only with the gateway still up** —
  never an AP-wide outage

Those 5 samples cluster into exactly two groups, 17:01–17:02 and 17:58–18:01,
and the Pi's own boot history shows boots ending at **17:01** and **17:57**.
They were operator reboots (working on the console display), not faults. Each
recovered in 2–3 minutes unattended.

### What is and is not established

**Fault 2 is resolved in practice.** Disabling power-save is the leading
explanation: it was the only change made on the Pi, and the symptom went from
total failure to an unbroken 15-hour run through the exact failure hour.

Two honest caveats remain:

- **The AP power cycle is a confound.** It landed at the same time. A wedged AP
  could plausibly drive a reassociation storm that crashes `brcmfmac`, in which
  case a healthy AP alone was sufficient and power-save was irrelevant. The two
  changes cannot be separated retrospectively.
- **Fault 1 is unproven, not disproven.** The AX3000 wedged exactly **once**
  under observation, so its recurrence interval is unknown. Ten quiet hours
  says little about a fault that might surface weekly. Do not read run 2 as
  evidence the AX3000 is healthy.

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

1. ~~Test the power-save fix in isolation.~~ **Done — fault 2 resolved.** Keep
   `/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf` in place; it is what
   survives netplan regeneration.
2. **Fault 1 is the remaining blocker.** It needs *time*, not a test: the AX3000
   wedged once and its recurrence interval is unknown. Leave both monitors (or
   at least the Tawa-side one) running periodically and note any repeat. A
   second wedge establishes a pattern and settles the replace-or-keep question.
3. **The Opal is no longer needed as a diagnostic** for fault 2, since
   power-save explains it. It stays useful only if fault 1 recurs and you want
   to prove the AX3000 is at fault before spending. If so, run it in **AP/bridge
   mode off the switch with its own SSID**, only the Pi joined — that avoids a
   third NAT layer and leaves `AncientGlade` undisturbed for the household's
   2.4 GHz smart-home devices, which are provisioned against that SSID.
4. **The LAN-DNS card is still gated, but on fault 1 alone now.** The Pi has
   proven it holds a link. Whether the *AP* is dependable enough to carry the
   household's only resolver is the open question. A resolver behind an AP that
   wedges takes all name resolution down with it.
5. **Consider reverting persistent journald** once fault 1 is settled — it
   trades SD-card wear for diagnosability on an already-old card. Keep it while
   fault 1 is still unexplained; that is exactly the evidence it exists to
   capture.

## Open questions

- Is fault 1 load-related, thermal, or uptime-related? Unknown — it wedged once
  under observation. Worth noting how long the AP had been up.
- Does the Opal hold a link where the AX3000 does not? Untested, and only worth
  testing if fault 1 recurs.
- ~~Would a Pi Zero **2** W avoid fault 2 entirely?~~ Moot — fault 2 is fixed on
  the existing hardware. No purchase needed. (The standing decision that this Pi
  stays out of the NixOS flake holds regardless of board.)
- Was power-save genuinely the fix, or was a healthy AP sufficient on its own?
  Unresolvable retrospectively — both changed together. Only matters if fault 1
  recurs *and* the Pi's interface dies with it.
