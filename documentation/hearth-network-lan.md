# Hearth networking — the interim Wi-Fi pin and the wired end state

Detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H1 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H1's status and its rules; this
file keeps the addressing detail and the reasoning.

## Interim (current)

Hearth and the LG TV both sit on GiGstreem Wi-Fi. The ISP gateway has **no
DHCP-reservation UI** (decision 18), so Hearth pins **172.16.141.38/24** on the
existing `GiGstreem` NetworkManager profile, gateway `172.16.141.1`. The PSK
stays on-box, not in the flake.

DNS is **`1.1.1.1,8.8.8.8`** in `common/lan.nix` on purpose: the ISP resolver
`172.16.141.1` combined with MagicDNS / `accept-dns` hung `cache.nixos.org` on
GiGstreem. MAC `c8:34:8e:21:97:1b` is informational only.

Acceptance for the interim state: Hearth holds 172.16.141.38 after a reconnect,
and the TV plays from that IP.

## Final (once a better router lands)

USB-A gigabit ethernet adapter (decision 15) → ethernet switch → TP-Link LAN,
with a static lease and wired preferred over Wi-Fi.

The Pi Zero W runs Pi-hole as LAN DNS (`hearth.home` and friends) when the
wired LAN lands. It is operator-managed and stays out of this flake.

Acceptance for the final state: Jellyfin reachable via the wired IP, and LAN
DNS resolves.

## Why this is deferred rather than blocked on a purchase

The fault behind the deferral was diagnosed on 2026-08-30 and is tracked as
open question 1 in plan.md — `AncientGlade`'s merged SSID with Smart Connect
deauthenticating the TV and phones mid-use. The fix is free (split SSIDs, pin
the TV to 5 GHz, pin the channel, update firmware), so no router purchase is
expected. See [`router-recommendations.md`](./router-recommendations.md).
