# H6 remote surface — DNS, ACME and the HSTS constraint

Detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md) H6 on
2026-09-01, when that file was restructured into an index so it would stop
outgrowing Conveyor's 32,000-character overview cap for the `hearth` tag.
**Nothing here is superseded.** plan.md keeps H6's status and its rules — never
WAN-forward, no `tls internal` on a `wizt.org` name; this file keeps the
certificate and DNS reasoning.

## Operator DNS

An A record points `tv.wizt.org` at `100.84.222.78`, Hearth's tailnet IPv4.
Tailnet split DNS forwards `wizt.org` to Cloudflare. The name may therefore
resolve off-tailnet, but TCP and TLS only work for tailnet members — resolution
is not access.

Host the `wizt.org` zone on Cloudflare; no GCP. Apex A records may still point
at Rebrandly until the public site has a new home.

## Why Let's Encrypt DNS-01 rather than `tls internal`

TLS is Let's Encrypt via DNS-01 (`security.acme` with lego's `cloudflare`
provider) because **the public apex sends `HSTS includeSubDomains`**. Under
that header Firefox will not let a user accept an exception for a self-signed
certificate, so Caddy's `tls internal` cannot work on any `wizt.org` name.

The secret is `secrets/acme-cloudflare.env`, holding
`CLOUDFLARE_DNS_API_TOKEN`.

## What is bound where

Caddy on Hearth (`hosts/Hearth/caddy.nix`) reverse-proxies Jellyfin at
`https://tv.wizt.org`, bound to tailnet IPv4 `100.84.222.78:443` only.
Tailscale Funnel stays a future card — this is tailnet-only, not Funnel.

The public site itself (decision 16) is a serverless webapp at `wiztow.org`,
living outside this flake. Hearth is not a public web server.

## The TV's path

The LG TV still reaches Jellyfin at `http://172.16.141.38:8096` on GiGstreem,
with Jellyfin's `openFirewall` unchanged. Putting that LAN IP on the intranet
page later would save local users from needing DHCP reservations.

## Acceptance

`https://tv.wizt.org` serves Jellyfin for tailnet devices, and nothing on
Hearth listens on WAN for this vhost.
