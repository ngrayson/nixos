# Router requirements and recommendations for Hearth's LAN (H1)

**Second pass, 2026-08-30.** This replaces the first version of this document,
which recommended a ~$228 purchase. Measurement does not support that
recommendation, and three of the first version's load-bearing assumptions were
wrong. Corrections are recorded in "What changed" below rather than quietly
edited out, because the wrong framing is easy to re-derive from the repo's own
docs.

Relates to open question 1 in [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) §6.

## Verdict

**No router purchase is justified by the current evidence.** The reported
symptoms — a smart TV and phones repeatedly dropping their connections, and
YouTube stuttering — are not caused by inadequate hardware on hand. Every path
that could be measured from inside the flake is healthy, including the TP-Link
that was suspected. The two problems the first version conflated are separate,
and neither is solved by the router it recommended:

- **Clients dropping** is an association problem on the apartment's managed
  Wi-Fi, which no downstream purchase can change.
- **The H1 blocker** is DHCP reservations, and the TP-Link already on the wall
  has an Address Reservation page.

The next step costs nothing: move the affected clients onto the router you
already own.

## What changed from the first version

| First version assumed | Actually |
|---|---|
| A new router replaces the GiGstreem gateway at the WAN edge | The apartment gateway **cannot be removed**. Anything bought sits behind it. Double NAT is a permanent condition, not an open question. |
| A **spare TP-Link router** is on hand to become the downstream NAT box (plan.md decision 2) | The TP-Link AX3000 **is AncientGlade** — active, and the box that was under suspicion. The real spare is a GL.iNet GL-SFT1200 "Opal". |
| The problem is router capability or capacity | Measured: it is not. See below. |

Because the edge position is not available, WAN-edge features — multi-WAN,
2.5 GbE WAN, IPS routing — are money spent on a role that cannot be filled.
That removes most of the first version's rationale for the UniFi Cloud Gateway
Ultra.

## Hardware actually on hand

| Device | State | Relevant capability |
|---|---|---|
| **TP-Link AX3000** (dual-band Wi-Fi 6) | Active. SSID `AncientGlade`, WAN `172.16.141.4` → LAN `192.168.0.0/24` | **Address Reservation** (static DHCP). 2.4 GHz + 5 GHz. EasyMesh-capable. |
| **GL.iNet GL-SFT1200 "Opal"** | Spare, unplugged | Wi-Fi 5 AC1200, dual-core 1 GHz, 128 MB RAM, 3× **gigabit** ports (1 WAN / 2 LAN), USB 2.0. OpenWrt-based, so static leases are standard. |
| Ethernet switch | On hand | Fan-out for the wired segment. PoE status unverified. |
| Raspberry Pi Zero W | On hand, **Pi-hole not yet deployed** | 2.4 GHz only, no ethernet without a USB OTG adapter. |

The Opal is a genuine option for a small dedicated server LAN — gigabit ports
mean Hearth↔switch traffic never touches its modest CPU. Its limits are Wi-Fi 5,
two LAN ports, and that inserting it *behind* AncientGlade would make three
layers of NAT. It is a replacement for AncientGlade's routing role, not an
addition to it.

## Measurements

Taken 2026-08-30 from Tawa, which is dual-homed: wired to GiGstreem
(`172.16.141.23`) and on AncientGlade's Wi-Fi (`192.168.0.119`). 20-40 ICMP
echoes per path. **Zero packet loss on every path tested.**

| Path | Avg | Max | Reading |
|---|---|---|---|
| GiGstreem gateway, wired | **1.2 ms** | 2.9 ms | pristine |
| Internet (`1.1.1.1`) via GiGstreem | **3.1 ms** | 11.4 ms | excellent |
| **Hearth** (GiGstreem Wi-Fi, the media server) | **3.8 ms** | 8.8 ms | healthy |
| AncientGlade router, Wi-Fi from Tawa | 21.0 ms | 104 ms | see caveat |
| AncientGlade, same test, power save off | **5.7 ms** | 20.4 ms | healthy |

**Caveat on the AncientGlade figures.** Tawa is a desktop with an Intel AX201
whose driver defaults to `iwlmvm.power_scheme = 2` (power save on). Disabling
power save for one test moved the same link from 21 ms to 5.7 ms. That is a
property of Tawa's radio, not of the TP-Link — measured here only so it can be
discounted as a confound, and reverted afterwards. AncientGlade's Wi-Fi is
fine.

## What the measurements rule out

- **A congested or oversubscribed uplink.** 3.1 ms to Cloudflare with an 11 ms
  worst case. An earlier theory that the apartment's shared building link was
  saturated is not supported.
- **The TP-Link AX3000 being defective.** Once the measuring client's power
  save was discounted, its link measured 5.7 ms average. Replacing it would
  buy nothing.
- **2.4 GHz channel congestion.** Tested directly rather than assumed:
  AncientGlade was moved from channel 7 (5 MHz from a 25-AP pile on channel 6,
  the worst available setting) to channel 11. Latency did not meaningfully
  change. The move is worth keeping — AncientGlade is now the strongest AP on
  its own channel instead of 12 dB down on an adjacent one — but congestion
  was not the cause.
- **Hearth's own Wi-Fi.** 3.8 ms average, 1.2 ms deviation.
  [`profiles/media-server.nix`](../profiles/media-server.nix) already sets
  `networking.networkmanager.wifi.powersave = false`, and it is working.

## What remains: client steering on the building network

The surviving explanation is the only one consistent with the full symptom set,
including the fact that **Hearth does not drop while the TV and phones do,
on the same SSID**.

GiGstreem is not a single home router. The RF survey shows it broadcasting from
multiple APs (channels 1, 6 ×2, and 11), alongside two other building networks
(`WindsorStaff`, `Tera Guest`) — a managed multi-AP deployment for the
building. Deployments like that commonly run aggressive client steering:
band steering, 802.11k/v/r roaming assistance, and minimum-RSSI thresholds that
deliberately kick clients below a signal floor to force them onto a better AP.

Cheap radios handle that badly. A smart TV and phones get bounced between APs
and bands and drop the connection; Hearth's Intel card negotiates the same
environment without trouble. That asymmetry is the signature.

This is inferred from the topology and the symptom pattern, not confirmed on
the AP itself — the building's equipment is not ours to inspect. It is
falsifiable: if the TV stops dropping once it is on an SSID that does no
steering, the explanation holds.

**None of this is fixable by buying a router**, because the offending AP stays
regardless. It *is* fixable by not using that AP for the affected clients.

## Recommendation

### Step 1 — move the affected clients onto AncientGlade. $0.

Put the TV, the phones, and Hearth on `AncientGlade` instead of `GiGstreem`.
One AP, no steering, no minimum-RSSI kicks, and a DHCP server with an Address
Reservation page.

This solves three things at once:

1. The drops, if the steering explanation is right.
2. The H1 blocker — stable addressing, which is the entire reason a purchase
   was being considered (plan.md decision 18).
3. Jellyfin stays local. **The TV and Hearth must move together**: the TV
   cannot run Tailscale, so it needs Hearth on its own LAN (plan.md §3).

This is the H1-final topology minus the cabling, reachable today with hardware
on the wall.

### Step 2 — verify coverage before spending anything.

The open risk is that AncientGlade's single AP does not cover the apartment as
well as the building's several APs do. That is answerable for free by walking
the space with a phone on the AncientGlade SSID and watching signal and
playback. Prefer its 5 GHz band where reachable: the survey found 45 APs on
2.4 GHz versus 21 on 5 GHz.

### Step 3 — only if coverage is genuinely short, buy an access point.

Not a router. The routing, NAT, and DHCP are already handled by a competent
Wi-Fi 6 box; the only thing potentially missing is radio coverage, and an AP is
the part that supplies it.

| Option | Price | Notes |
|---|---|---|
| **Second TP-Link EasyMesh node** | varies | Simplest path — the AX3000 is EasyMesh-capable, so a matching node extends the existing SSID with no new admin surface. |
| **TP-Link EAP650** | **$129.99** (Newegg, 2026-08-30) | Wi-Fi 6 AX3000 ceiling AP, wired backhaul, far better placement than a router on a desk. Needs PoE — **confirm whether the on-hand switch supplies it, or budget an injector.** |
| **UniFi U7 Lite** | **$99.00** (store.ui.com, 2026-08-30) | Wi-Fi 7 ceiling AP, PoE. Only worth it if the UniFi controller is wanted for its own sake; it needs a controller to manage. |

Prices carried over from the first version's research, gathered the same day
from Newegg and store.ui.com product pages. Amazon prices could not be read
(rendered client-side), so none are quoted — worth a manual check before
ordering.

### What not to buy

The first version's picks — **UniFi Cloud Gateway Ultra + U7 Lite ($228)** and
**TP-Link Archer BE550 ($199.99)**. The UCG-Ultra is a WAN-edge gateway with no
edge to sit at. The BE550 replaces a router that measured healthy, to fix a
problem located on someone else's AP.

## RF environment, for reference

Scan from Tawa, 2026-08-30. 45 APs visible on 2.4 GHz, 21 on 5 GHz.

```
ch 1    15-18 APs   strongest 89
ch 6    24-25 APs   strongest 82-84
ch 11    5-13 APs   strongest 69   <- AncientGlade now here, and loudest on it
```

5 GHz is materially less contended and is where the TV and phones should be
whenever signal allows.

## Open questions

1. **Does moving the TV and phones to AncientGlade stop the drops?** This is
   the test that confirms or kills the steering explanation, and it gates
   every remaining decision here. Free.
2. **Does AncientGlade cover the apartment?** The one input that decides
   whether any hardware is bought at all.
3. **Is `172.16.141.0/24` a building-wide shared segment?** Three tenant-facing
   SSIDs are visible, and an unidentified `172.16.141.36` appeared in Tawa's
   ARP table alongside Tawa's `.23` and Hearth's `.38`. If neighbours share
   that L2, Jellyfin is reachable by the building — Hearth's sshd is key-only
   and fine, but Jellyfin is not authenticated at the network layer. This is a
   security argument for the H1 topology that the first version never raised.
   Not verified: scanning the subnet means scanning neighbours.
4. **Is the on-hand switch PoE?** Decides whether Step 3 needs an injector.
5. **Does the Opal replace AncientGlade, or stay in the box?** Only relevant if
   AncientGlade is ever retired; adding it behind AncientGlade would mean
   triple NAT.
6. **Wiring the TV.** Still the highest-value physical change available: it
   removes the heaviest client from the air entirely and gives Jellyfin a clean
   path, for the price of a cable.

## Sources

- [Opal (GL-SFT1200) specifications — GL.iNet](https://www.gl-inet.com/en-us/products/gl-sft1200)
- [How to use Pi-Hole DNS Server on TP-Link routers](https://www.tp-link.com/us/support/faq/3230/)
- [TP-Link EAP650 — Newegg](https://www.newegg.com/tp-link-eap650/p/N82E16833704652)
- [Access Point U7 Lite — Ubiquiti Store](https://store.ui.com/us/en/products/u7-lite)
- Measurements above: `ping`, `nmcli device wifi list` from Tawa, 2026-08-30.
