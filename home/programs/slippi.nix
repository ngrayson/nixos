# Slippi Launcher options (module from slippi-nix is imported in `common/system.nix`).
{lib, ...}: {
  slippi-launcher = {
    enable = true;
    # Set your NTSC Melee ISO path here, or via the launcher UI (merged on next activation).
    isoPath = lib.mkDefault "";
  };
  # gcc.oc-kmod.enable = true;
}
