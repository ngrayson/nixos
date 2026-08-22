# Shared Tailscale mesh VPN (Tawa, Hearth, …). After first enable, join with:
#   sudo tailscale up
{...}: {
  services.tailscale = {
    enable = true;
    # UDP 41641 for direct peer connections through NAT.
    openFirewall = true;
    # Tailscale SSH: identity auth (ngrayson@github), no host authorized_keys.
    # Applied by tailscaled-set.service (`tailscale set --ssh`).
    extraSetFlags = ["--ssh"];
  };

  # Accept inbound tailnet traffic (SSH, Jellyfin, etc.) without per-port holes.
  networking.firewall.trustedInterfaces = ["tailscale0"];
  # rpfilter drops Tailscale return paths when NetworkManager also owns a default route.
  networking.firewall.checkReversePath = "loose";
}
