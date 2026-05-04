# OVPN profiles (declarative source)

Place provider `.ovpn` files for Vortix in this directory.

Home Manager maps this tree to `~/.config/ovpn`.

For stunnel-backed profiles, ensure the profile targets `127.0.0.1 1194` so traffic is tunneled through `services.stunnel.clients.frootvpn`.
