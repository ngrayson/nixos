# Router recommendations for Hearth's wired LAN (H1)

Resolves open question 1 in [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) §6
("**Better router:** which model / when — gates the final H1 wired topology").

The ISP-provided GiGstreem gateway **has no DHCP-reservation UI** (plan.md
decision 18). That is the concrete blocker: Hearth's address is currently pinned
by hand at `172.16.141.38/24` on its own NetworkManager profile, and the ISP
pool can reissue `.38` if Hearth is offline. Replacing the edge router is what
unblocks the final H1 topology.

**Researched 2026-08-30. Prices move constantly — re-check before buying.**

## Requirements

From plan.md §3 (target architecture), §4 (H1), decisions 13/15/18, and the
Conveyor cards "Wire Hearth to the dedicated LAN (H1-final)" and "Run Pi-hole on
the Raspberry Pi Zero W".

- **Static DHCP reservations are mandatory.** This is the whole reason for the
  purchase (decision 18). Anything that cannot pin a MAC to an address is
  disqualified.
- **Already on hand — do not re-buy:** a spare TP-Link router (becomes the
  downstream NAT box for the dedicated server LAN), an ethernet switch, a
  Raspberry Pi Zero W (LAN DNS via Pi-hole, its own card), and a USB-A gigabit
  adapter for Hearth (separate purchase, not a router).
- **Position in the topology:** the new router sits at the WAN edge. Per
  plan.md §3 the final chain is
  `Internet → new router → TP-Link (NAT, server LAN) → switch → Hearth + Pi Zero W`.
  It does **not** need to serve the dedicated server LAN itself — the on-hand
  TP-Link does that — but it must serve the rest of the household.
- **Wi-Fi coverage** at least matching the current ISP gateway, since the LG TV,
  phones, workstations, and the future Go2 kiosk are on it today.
- **At least one wired hand-off** toward the TP-Link/switch/Hearth chain, on top
  of household duty. The on-hand switch can fan out from a single port.
- **No budget was ever stated.** Options below span roughly $100–$320. Setting a
  ceiling is left as an open question rather than guessed at.

## How these prices were gathered

| Source | Method | Reliable? |
|---|---|---|
| Newegg | product pages read directly | yes, exact figures below |
| store.ui.com | product pages read directly | yes, exact figures below |
| Amazon | **could not be read** — prices are rendered client-side in JavaScript, so the page HTML carries no figure | no Amazon prices are quoted here |

Amazon commonly differs from Newegg on this hardware, so it is worth a manual
price check there before ordering. No Amazon number is stated in this doc
because none could be verified, and inventing one would be worse than omitting
it.

Static-DHCP support below is from vendor documentation and platform behavior,
not hands-on testing on each unit. All four platforms (UniFi, Omada, TP-Link
consumer, ASUS) expose per-client address reservation; verify in the admin UI on
arrival if it is critical.

## Track A: separate router + Wi-Fi access point(s)

Modular: the routing box and the radios are replaced or upgraded independently.
Neither of these gateways has a Wi-Fi radio, so an AP is **required**, not
optional — budget for both lines.

| Component | Price | Ports | Static DHCP | Notes |
|---|---|---|---|---|
| **UniFi Cloud Gateway Ultra** (UCG-Ultra) | **$129.00** (store.ui.com) | 1× 2.5 GbE WAN, 4× 1 GbE LAN | Yes | Runs the UniFi Network controller **onboard** — no separate Cloud Key needed. No Wi-Fi. 1 Gbps IPS routing, multi-WAN. |
| + **UniFi U7 Lite** AP | **$99.00** (store.ui.com) | PoE | — | Wi-Fi 7, ceiling mount. Cheapest current-gen UniFi AP. |
| + **UniFi U7 Pro** AP | **$189.00** (store.ui.com) | PoE | — | Wi-Fi 7, 6 GHz, 6 spatial streams. Step up in coverage and capacity. |
| **TP-Link Omada ER605 v2** | ~$50–88 street; **out of stock at Newegg** as of 2026-08-30 | 1× WAN + up to 3 configurable WAN/LAN gigabit | Yes | Cheapest credible Track A router. Gigabit only — no 2.5 GbE. Omada controller is separate (software, or hardware controller). |
| + **TP-Link EAP650** AP | **$129.99** (Newegg, third-party seller *NothingButSavings*; other sellers $132–136) | PoE+ | — | Wi-Fi 6 AX3000 ceiling mount. |

**Track A totals:** UniFi $228 (Ultra + U7 Lite) to $318 (Ultra + U7 Pro).
Omada roughly $180–220 depending on ER605 availability.

**Pros:** radios and routing upgrade independently; PoE ceiling APs cover a
house far better than a router's built-in antennas sitting on a desk; UniFi's
controller gives real per-client visibility and painless fixed-IP assignment,
which is exactly the pain point being solved; adding a second AP later is
additive rather than a replacement.

**Cons:** two devices and two power draws; APs generally want PoE (the on-hand
switch may not be PoE — check, or budget a PoE injector); more upfront cost;
more concepts to learn. The ER605's gigabit-only WAN caps the connection if
GiGstreem service exceeds 1 Gbps.

## Track B: all-in-one router + Wi-Fi

| Model | Price | Ports | Static DHCP | Notes |
|---|---|---|---|---|
| **TP-Link Archer BE230** | **~$99** (Newegg) | 2× 2.5 G + 3× 1 G, USB 3.0 | Yes | Dual-band Wi-Fi 7 (BE3600), no 6 GHz. Cheapest sensible Wi-Fi 7. |
| **TP-Link Archer BE550** | **$199.99** (Newegg, marked down from $249.99) | full 2.5 G ports | Yes | Tri-band Wi-Fi 7 BE9300, ~2,000 sq ft, EasyMesh. Widely recommended as the best mainstream pick. |
| **ASUS RT-BE92U** | **$199.99–$219.99** (Newegg, varies by listing; refurb **$159**) | 1× 10 GbE WAN/LAN, 4× 2.5 GbE LAN | Yes | Tri-band Wi-Fi 7 BE9700, AiMesh. Best port loadout at this price. |

**Pros:** one box, one power brick, one admin UI; materially cheaper at the
budget end; consumer firmware is familiar and DHCP reservation is a couple of
clicks; ASUS/TP-Link mesh (AiMesh/EasyMesh) lets a second unit be added later if
coverage falls short.

**Cons:** radios and routing are welded together — a Wi-Fi generation bump means
replacing the whole router, including the parts that were fine; router-position
compromises Wi-Fi placement, since the box must sit where the WAN drop is; less
per-client network visibility.

## Recommendation

**Track A pick: UniFi Cloud Gateway Ultra ($129) + U7 Lite ($99) — $228.**
The Ultra running the controller onboard removes the usual UniFi objection (a
separate Cloud Key), and its fixed-IP-per-client UI is a direct answer to the
DHCP-reservation problem that motivated this whole purchase. Start with the
U7 Lite; the U7 Pro at $189 is the upgrade if one AP does not cover the house,
and under Track A that upgrade does not touch the router.

**Track B pick: TP-Link Archer BE550 at $199.99.** Tri-band with full 2.5 G
ports, currently $50 off, and the most consistently recommended mainstream
Wi-Fi 7 router in 2026 coverage. If the budget is tight, the **Archer BE230 at
~$99** does everything H1 actually requires — the reservation UI, 2.5 G ports,
and a wired hand-off — and only gives up 6 GHz and some range. If port count
matters more than brand familiarity, the **ASUS RT-BE92U** at roughly the same
price adds a 10 GbE port and four 2.5 GbE LAN ports.

**Verdict on the tradeoff Nick raised.** The modular track is the better fit
here, but the deciding factor is coverage, not ideology. This household already
runs a deliberately layered network (edge router, downstream NAT box, dedicated
server LAN, Pi-hole DNS, Tailscale mesh) and clearly intends to keep growing it —
that is the environment where a controller with real per-client visibility earns
its price, and where "replace the AP without touching the router" pays off over a
few years. At $228 versus $199.99 the modular option is also essentially price
neutral against the mid-range all-in-one.

The honest counter-argument: if one router placed at the WAN drop already covers
the house acceptably today, Track B is less hardware, less to learn, and the
Archer BE230 at ~$99 solves the actual blocker for half the money. **If the ISP
gateway's current Wi-Fi coverage is adequate from where it sits, buy the BE230
and move on** — H1 is blocked on DHCP reservations, not on Wi-Fi quality.

Either way this is Nick's call; nothing here should be bought without setting a
budget first.

## Open questions

1. **Budget ceiling** — never stated. The spread above is $99 to $318.
2. **Wi-Fi coverage today** — is the ISP gateway's coverage actually adequate
   from its current position? This is the single input that decides Track A vs
   Track B, and it is answerable for free by walking the house with a phone.
3. **Is the on-hand switch PoE?** Track A's APs need PoE or an injector; an
   unbudgeted injector narrows the price gap.
4. **Double NAT.** The planned chain puts the on-hand TP-Link behind the new
   router doing its own NAT. Both UniFi and Omada could serve the server LAN as
   a VLAN off the edge router instead, retiring the TP-Link and flattening the
   topology. Not a recommendation — plan.md §3 deliberately specifies the
   layered design — but worth deciding before buying, since it changes whether
   the TP-Link stays in the picture.
5. **AncientGlade's fate** — the current downstream Wi-Fi router at
   `192.168.0.0/24` (see the comment in [`common/lan.nix`](../common/lan.nix)).
   Retired, or kept as a secondary AP?
6. **LG TV and Go2 kiosk** — do they stay on Wi-Fi, or eventually get wired?
   Wiring the TV would reduce the Wi-Fi coverage requirement considerably.

## Sources

- [Cloud Gateway Ultra — Ubiquiti Store](https://store.ui.com/us/en/products/ucg-ultra)
- [Access Point U7 Pro — Ubiquiti Store](https://store.ui.com/us/en/products/u7-pro)
- [Access Point U7 Lite — Ubiquiti Store](https://store.ui.com/us/en/products/u7-lite)
- [UniFi Cloud Gateway Ultra review — iFeeltech](https://ifeeltech.com/blog/unifi-cloud-gateway-ultra-review)
- [TP-Link Archer BE550 — Newegg](https://www.newegg.com/tp-link-archer-be550-6-ghz-5760-mbps-5-ghz-2880-mbps-2-4-ghz-574-mbps/p/N82E16833704711)
- [TP-Link Archer BE230 — Newegg](https://www.newegg.com/tp-link-archer-be230-ieee-802-11be-ax-ac-n-a-5-ghz-ieee-802-11be-ax-n-g-b-2-4-ghz/p/N82E16833704758)
- [TP-Link EAP650 — Newegg](https://www.newegg.com/tp-link-eap650/p/N82E16833704652)
- [TP-Link ER605 V2 — Newegg](https://www.newegg.com/tp-link-er605-v2-10-100-1000mbps/p/N82E16833704600)
- [ASUS RT-BE92U — Newegg](https://www.newegg.com/asus-rt-be92u-ieee-802-11a-ieee-802-11b-ieee-802-11g-wifi-4-wifi-5-wifi-6-wifi-6e-wifi-7-ipv4-ipv6/p/N82E16833320608)
- [Best Wi-Fi 7 routers 2026 — Tom's Hardware](https://www.tomshardware.com/networking/routers/best-wi-fi-router-deals)
