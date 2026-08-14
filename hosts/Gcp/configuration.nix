# Google Compute Engine image and runtime configuration.
{modulesPath, ...}: {
  imports = [
    ../../profiles/server.nix
    (modulesPath + "/virtualisation/google-compute-image.nix")
    ./host.nix
  ];
}
