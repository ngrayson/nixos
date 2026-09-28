# Roblox on Theseus via Sober (VinegarHQ), which ships only as a Flatpak —
# there is no nixpkgs package, so this is the one Flatpak host in the flake.
# nix-flatpak makes the install declarative: flatpak-managed-install.service
# runs at activation and needs network. First Sober launch downloads Roblox.
# Theseus-only on purpose; profiles/workstation.nix is shared with Tawa.
{inputs, ...}: {
  imports = [inputs.nix-flatpak.nixosModules.nix-flatpak];

  services.flatpak = {
    enable = true;
    # nix-flatpak adds flathub by default; stated so the origin is explicit.
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    packages = [
      {
        appId = "org.vinegarhq.Sober";
        origin = "flathub";
      }
    ];
    # Sober updates Roblox itself; keep the Flatpak fresh weekly rather than
    # on every switch (onActivation would make each rebuild hit the network).
    update.onActivation = false;
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # Flatpak apps only see host fonts through /run/current-system/sw/share/X11/fonts.
  fonts.fontDir.enable = true;
}
