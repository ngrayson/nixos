# Deprecated re-export. Host entries should import profiles/workstation.nix.
{...}: {
  imports = [../profiles/workstation.nix];
}
