# Router requirements and recommendations for Hearth's LAN (H1)

**Second pass, 2026-08-30.** This replaces the first version of this document,
which recommended a ~$228 purchase. Measurement does not support that
recommendation, and three of the first version's load-bearing assumptions were
wrong. Corrections are recorded in "What changed" below rather than quietly
edited out, because the wrong framing is easy to re-derive from the repo's own
docs.

Relates to open question 1 in [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) §6.

## Verdict

**A purchase may well be justified, but the fault is not yet diagnosed, so
nothing should be bought yet.**

The symptom, stated correctly: **the TV and phones drop on `AncientGlade`**
(the on-hand TP-Link AX3000). They were moved to `GiGstreem`, where they hold a
good connection — but GiGstreem is the building's network, so they sit outside
the intranet and get neither Pi-hole DNS nor `home.wizt.org`.

So the trade is reliability against reachability, and today reliability wins by
default. The goal is to get the TV and phones onto the intranet *without*
losing the stability they currently have.

What is established by measurement is narrower than the first two versions of
this document claimed:

- The **uplink and the building network are healthy** (1.2 ms wired, 3.1 ms to
  the internet). Nothing upstream is at fault.
- **Hearth is healthy** on GiGstreem Wi-Fi (3.8 ms, 1.2 ms deviation).
- **AncientGlade's latency is fine** for an associated, always-awake client
  (5.7 ms). Latency was never the problem — *association drops* are, and that
  is a different failure mode that these measurements do not capture.

**The cause of the drops is still unknown.** Candidate checks are listed below.
Until one of them is confirmed or exhausted, "buy a better AP" and "fix the AP
you have" cannot be told apart.

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
- **Latency or throughput as the cause.** Once the measuring client's power
  save was discounted, AncientGlade measured 5.7 ms average with zero loss.
  Note carefully what this does **not** rule out: the reported fault is clients
  *dropping their association*, which a latency test on a client that never
  drops cannot detect. The TP-Link is not slow. Whether it is reliable is
  untested.
- **2.4 GHz channel congestion.** Tested directly rather than assumed:
  AncientGlade was moved from channel 7 (5 MHz from a 25-AP pile on channel 6,
  the worst available setting) to channel 11. Latency did not meaningfully
  change. The move is worth keeping — AncientGlade is now the strongest AP on
  its own channel instead of 12 dB down on an adjacent one — but congestion
  was not the cause.
- **Hearth's own Wi-Fi.** 3.8 ms average, 1.2 ms deviation.
  [`profiles/media-server.nix`](../profiles/media-server.nix) already sets
  `networking.networkmanager.wifi.powersave = false`, and it is working.

## The open question: why does AncientGlade drop sleeping clients?

The asymmetry to explain: **Tawa stays associated to AncientGlade; the TV and
phones do not.** The clearest difference between those clients is that Tawa is
a desktop that never sleeps, while a TV and phones sleep constantly and rely on
the AP buffering frames for them and on renewing DHCP leases after waking.

That points at AP-side handling of power-saving clients rather than at RF
quality — consistent with the latency measurements, which found nothing wrong
with the link itself. **This is a hypothesis, not a finding.** Three earlier
hypotheses in this document's history were tested and killed (a saturated
building uplink, 2.4 GHz channel congestion, and steering on the building's
APs); this one has not been tested at all.

Checks worth running on AncientGlade before any purchase, cheapest first:

1. **DHCP lease time and pool size.** Short leases plus a sleeping client is a
   classic drop-off pattern. Longer leases, and a pool large enough for every
   device, cost nothing.
2. **Merged vs split SSID.** If Smart Connect / band steering is on, splitting
   2.4 GHz and 5 GHz into separately named SSIDs and pinning the TV to one
   stops band-flap re-association failures.
3. **Firmware version.** Some Archer AX-series firmware had known 2.4 GHz
   stability regressions.
4. **Any "eco", "green", or airtime-fairness feature**, which can be
   aggressive with idle clients.
5. **DTIM interval**, which governs how the AP buffers for sleeping clients.

If those are exhausted and the drops persist, the AX3000 is genuinely unfit for
the role and replacing the radio — an **access point**, not a router — becomes
the justified purchase.

## Constraint discovered 2026-08-30: the intranet is tailnet-only

[`hosts/Hearth/caddy.nix`](../hosts/Hearth/caddy.nix) sets
`listenAddresses = [tailnetIPv4]` on both the `tv.wizt.org` and
`home.wizt.org` vhosts. They are reachable over Tailscale and nowhere else.

This materially changes the problem, because it means **moving the TV onto
`AncientGlade` would never have given it `home.wizt.org`**. The TV cannot run
Tailscale (plan.md §3), so no choice of Wi-Fi network reaches a tailnet-only
listener. The two affected client classes therefore need different solutions:

- **Phones can run Tailscale.** They already reach `home.wizt.org` from any
  network, GiGstreem included, and Tailscale can push a tailnet-wide DNS
  server, which is a route to Pi-hole that does not depend on Wi-Fi at all.
  Phones may need no network change whatsoever.
- **The TV cannot.** It needs LAN-local reachability, which today does not
  exist on any LAN. Options are to bind Caddy additionally to Hearth's LAN
  address and resolve `home.wizt.org` locally, or to accept Jellyfin-by-IP
  (`172.16.141.38:8096`, which works from GiGstreem today) and drop the
  hostname requirement for the TV.

If Caddy is bound to a LAN address, note open question 3 below: if
`172.16.141.0/24` is a shared building segment, that listener is exposed to
neighbours and needs a firewall rule scoped to known hosts.

## Also discovered 2026-08-30: Hearth is not wired

plan.md decision 15 and §3 assume Hearth reaches the LAN through a USB-A
gigabit adapter into the on-hand switch. It does not. Hearth is on **Wi-Fi**
(`wlp0s20f3`, `172.16.141.38`, GiGstreem) with no ethernet interface up. It is
performing well there (3.8 ms), so this is not urgent — but the wired topology
in §3 is aspirational, not current, and any plan that assumes Hearth is already
on the switch is wrong.

## Recommendation

There are two independent goals here, and conflating them is what produced the
first two versions' wrong answers. Treat them separately.

### Goal A — get the phones onto the intranet. Likely $0, no Wi-Fi change.

Phones can run Tailscale. On the tailnet they already reach `home.wizt.org`
and Hearth from any network, GiGstreem included, and Tailscale's DNS settings
can push a tailnet-wide resolver, which is a path to Pi-hole that does not
depend on which Wi-Fi they are on.

**Do this first.** It removes the phones from the problem entirely and leaves
them on the connection that currently works, which means the remaining question
is only about one device.

### Goal B — get the TV onto the intranet. Diagnose before buying.

The TV cannot run Tailscale, so it needs LAN-local access, and it currently
drops on the only LAN that could offer it. Two sub-problems:

**B1 — make `AncientGlade` hold the TV.** Work the checklist in "The open
question" above (lease time, split SSID, firmware, eco features, DTIM). All
free. Until this is attempted, there is no evidence that a *new* AP would
behave any differently, because the fault mode has never been characterised.

**B2 — make the intranet reachable from the LAN at all.** Even a perfectly
stable AncientGlade does not deliver `home.wizt.org` to the TV, because Caddy
listens on the tailnet address only. Either bind Caddy to Hearth's LAN address
as well (with a firewall rule — see open question 3) and resolve the name
locally, or accept Jellyfin-by-IP for the TV and drop the hostname
requirement. **This is a config decision, not a purchase**, and it is
independent of which router the TV sits behind.

Note that B2 has a bearing on B1's urgency: if the TV only ever needed Jellyfin
by IP, it can have that on GiGstreem today at `172.16.141.38:8096`, and the
whole router question reduces to whether Pi-hole DNS is worth moving it.

### Goal C — only if B1's checklist is exhausted, buy an access point.

Not a router. If AncientGlade proves genuinely unable to hold sleeping clients
after the free checks, the part that has failed is the radio, and an AP is the
part that replaces it. Routing, NAT, and DHCP reservations are not what broke.

| Option | Price | Notes |
|---|---|---|
| **TP-Link EAP650** | **$129.99** (Newegg, 2026-08-30) | Wi-Fi 6 AX3000 ceiling AP, wired backhaul, far better placement than a router on a desk. Needs PoE — **confirm whether the on-hand switch supplies it, or budget an injector.** |
| **UniFi U7 Lite** | **$99.00** (store.ui.com, 2026-08-30) | Wi-Fi 7 ceiling AP, PoE. Needs a controller to manage; only worth it if UniFi is wanted for its own sake. |
| **Second TP-Link EasyMesh node** | varies | Cheapest to adopt, but it is the same vendor and firmware family as the unit that is currently dropping clients — a poor bet if the fault turns out to be firmware. |

Prices carried over from the first version's research, gathered the same day
from Newegg and store.ui.com product pages. Amazon prices could not be read
(rendered client-side), so none are quoted — worth a manual check before
ordering.

### What not to buy

**UniFi Cloud Gateway Ultra + U7 Lite ($228)** and **TP-Link Archer BE550
($199.99)**, the first version's picks. The UCG-Ultra is a WAN-edge gateway and
there is no edge position available behind the apartment gateway. The BE550 is
a whole router bought to replace a radio, when routing, NAT, and DHCP
reservation all work fine on the box already installed.

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

1. **What is the drop pattern on AncientGlade?** Do the TV and phones drop
   after idling, or during active use? Which band were they on — 2.4 GHz,
   5 GHz, or a merged Smart Connect SSID? This is the single most useful
   unknown: it separates a sleeping-client bug from an RF or firmware fault,
   and it decides whether the free checklist is even pointed the right way.
2. **Does the free checklist fix it?** Lease time, split SSID, firmware, eco
   features, DTIM. Until this is run, no purchase can be justified, because
   the fault has never been characterised.
3. **Is `172.16.141.0/24` a building-wide shared segment?** Three tenant-facing
   SSIDs are visible, and an unidentified `172.16.141.36` appeared in Tawa's
   ARP table alongside Tawa's `.23` and Hearth's `.38`. If neighbours share
   that L2, Jellyfin at `172.16.141.38:8096` is already reachable by the
   building — Hearth's sshd is key-only and fine, but Jellyfin is not
   authenticated at the network layer. This becomes urgent if Caddy is bound to
   the LAN address per B2. Not verified: scanning the subnet means scanning
   neighbours.
4. **Does the TV actually need `home.wizt.org`, or is Jellyfin-by-IP enough?**
   If by-IP suffices, the TV can stay on GiGstreem indefinitely and the only
   remaining reason to move it is Pi-hole. This question can collapse most of
   this document.
5. **Where should Pi-hole run?** plan.md schedules it on the Pi Zero W behind
   the wired LAN. But the Pi Zero W is 2.4 GHz-only with no ethernet, and the
   devices that need it are on GiGstreem. DNS on Hearth — already stable on
   GiGstreem at `172.16.141.38` — would serve the TV directly and the phones
   over the tailnet, without anything moving. Worth deciding before the wired
   LAN is built around the Pi.
6. **Is the on-hand switch PoE?** Decides whether Goal C needs an injector.
7. **Should Hearth actually be wired?** It is on Wi-Fi today and performing
   well. plan.md decision 15 assumes a USB-A NIC that is not installed. Wiring
   it is still worthwhile for a media server, but it is not currently blocking
   anything.
8. **Does the Opal have a role?** Only if AncientGlade is retired; adding it
   behind AncientGlade would mean triple NAT.

## Sources

- [Opal (GL-SFT1200) specifications — GL.iNet](https://www.gl-inet.com/en-us/products/gl-sft1200)
- [How to use Pi-Hole DNS Server on TP-Link routers](https://www.tp-link.com/us/support/faq/3230/)
- [TP-Link EAP650 — Newegg](https://www.newegg.com/tp-link-eap650/p/N82E16833704652)
- [Access Point U7 Lite — Ubiquiti Store](https://store.ui.com/us/en/products/u7-lite)
- Measurements above: `ping`, `nmcli device wifi list` from Tawa, 2026-08-30.
