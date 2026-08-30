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

## Diagnosis: Smart Connect band steering

**Confirmed inputs (2026-08-30):** the TV and phones drop **mid-use**, not after
idling, and `AncientGlade` runs a **merged SSID with Smart Connect enabled**.

That combination is a well-known failure mode. Smart Connect moves a client
between the 2.4 GHz and 5 GHz radios by **deauthenticating it** to force
re-association on the other band. Well-behaved clients re-associate in
milliseconds. Cheap TV and phone radios frequently do not — they take the
deauth as a disconnect and drop the session.

This explains every observation on record, including the one that defeated the
three earlier hypotheses:

| Observation | Explained by steering? |
|---|---|
| TV and phones drop **mid-use** | Yes — steering decisions fire on load and signal changes at any time, including mid-session |
| **Tawa never drops** on the same AP | Yes — a stationary desktop with a strong, stable signal never triggers a steering decision, so it is never deauthed |
| Latency measured **fine** (5.7 ms) | Yes — the link is healthy *while associated*; steering breaks association, not throughput |
| Moving 2.4 GHz ch7 → ch11 **changed nothing** | Yes — this was never RF congestion |
| GiGstreem holds the same clients fine | Yes — the building's managed APs use standards-based roaming (802.11k/v/r) rather than deauth-based steering |

**Ruled out:** DFS radar events, another common cause of mid-use drops. The
5 GHz radio was observed on channels 149 and 153, both UNII-3 and non-DFS, so
no radar-triggered channel change is possible there.

**Also already eliminated (2026-08-30):** **TWT** (Target Wake Time) and
**OFDMA** are both already disabled on the AX3000. Those are the other two
Wi-Fi 6 features that commonly cause client compatibility failures, so they are
off the table — which leaves Smart Connect as the one known drop-causing
feature still enabled.

**Not ruled out:** auto channel selection. The 5 GHz radio was seen to move
from ch149 to ch153 during the investigation. That was most likely a
reconfiguration side effect, but a router periodically re-selecting its channel
on "auto" also drops clients mid-use, and pinning the channel costs nothing.

### The fix, in order, all free

1. **Disable Smart Connect.** Split into two separately named SSIDs — e.g.
   `AncientGlade` (5 GHz) and `AncientGlade-2G` (2.4 GHz). This is the primary
   fix and directly targets the diagnosis.
2. **Pin the TV to the 5 GHz SSID.** With bands split, the TV can no longer be
   steered at all. 5 GHz is also the less contended band here (21 APs versus
   45).
3. **Pin the 5 GHz channel** manually instead of leaving it on auto, to remove
   re-selection as a second source of mid-use drops.
4. **Update firmware** while in the admin UI.

If the drops stop, no purchase is needed and the plan below unblocks. If they
persist after all four, the AX3000's radio is genuinely unfit and Goal C
applies.

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

### Goal B — the TV. Fix the steering first; everything else follows.

**Clarified requirement (2026-08-30):** the TV does **not** need
`home.wizt.org`. Jellyfin alone is enough. What it needs is an address that
**never changes**, because re-entering one with a TV remote's on-screen
keyboard is the actual pain being solved.

That reduces the whole problem to *stable addressing for Hearth on whatever
network the TV is on* — which is exactly the H1 blocker, and it converges with
the steering fix:

**B1 — fix Smart Connect** (above). Free, and the linchpin: until the TV can
stay associated to AncientGlade, it cannot move there, and GiGstreem is the
only network it can use.

**B2 — then move the TV and Hearth to AncientGlade together.** This is what
delivers the fixed address. On GiGstreem, Hearth's `172.16.141.38` is a
*hand-pinned* static address on a DHCP pool nobody controls — decision 18
records the accepted risk that the pool reissues `.38` while Hearth is offline,
which is precisely the event that forces a retype on the TV remote. On
AncientGlade the address is a **real DHCP reservation**, and the collision risk
goes away. Pi-hole for the TV comes along for free, since AncientGlade's DHCP
can hand out the DNS server.

**B3 — enter the address once in the TV's Jellyfin app**, which stores it.
No hostname, no DNS, no Caddy changes required.

Note what is *not* needed: binding Caddy to the LAN, resolving `home.wizt.org`
locally, or exposing the intranet beyond the tailnet. Those stay tailnet-only
as designed (decision 7).

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

1. **Does disabling Smart Connect stop the drops?** The one test that matters.
   Free, reversible, and it gates every other decision in this document. If it
   works, nothing is bought and Goal B proceeds.
2. **Is `172.16.141.0/24` a building-wide shared segment?** Three tenant-facing
   SSIDs are visible, and an unidentified `172.16.141.36` appeared in Tawa's
   ARP table alongside Tawa's `.23` and Hearth's `.38`. If neighbours share
   that L2, Jellyfin at `172.16.141.38:8096` is already reachable by the
   building — Hearth's sshd is key-only and fine, but Jellyfin is not
   authenticated at the network layer. Moving Hearth and the TV to
   AncientGlade (Goal B2) resolves this as a side effect. Not verified:
   scanning the subnet means scanning neighbours.
3. **Does AncientGlade cover the TV's location on 5 GHz?** Goal B pins the TV
   to the 5 GHz band, which has shorter range than 2.4 GHz. If the TV sits far
   from the router this is the thing that fails, and it is the only remaining
   scenario in which an access point gets bought.
4. **Where should Pi-hole run?** plan.md schedules it on the Pi Zero W behind
   the wired LAN, but that Pi is 2.4 GHz-only with no ethernet. If the TV moves
   to AncientGlade (Goal B2), AncientGlade's DHCP can hand out whatever
   resolver address is chosen, and DNS on Hearth would serve the TV directly
   and the phones over the tailnet. Worth deciding before the wired LAN is
   built around the Pi.
5. **Is the on-hand switch PoE?** Only matters if Goal C is ever reached.
6. **Should Hearth actually be wired?** It is on Wi-Fi today and performing
   well (3.8 ms). plan.md decision 15 assumes a USB-A NIC that is not
   installed. Worthwhile for a media server, but not blocking anything.
7. **Does the Opal have a role?** Only if AncientGlade is retired; adding it
   behind AncientGlade would mean triple NAT.

## Sources

- [Opal (GL-SFT1200) specifications — GL.iNet](https://www.gl-inet.com/en-us/products/gl-sft1200)
- [How to use Pi-Hole DNS Server on TP-Link routers](https://www.tp-link.com/us/support/faq/3230/)
- [TP-Link EAP650 — Newegg](https://www.newegg.com/tp-link-eap650/p/N82E16833704652)
- [Access Point U7 Lite — Ubiquiti Store](https://store.ui.com/us/en/products/u7-lite)
- Measurements above: `ping`, `nmcli device wifi list` from Tawa, 2026-08-30.
