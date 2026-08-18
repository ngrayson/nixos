# Docker for local Foundation (and similar) compose stacks — Tawa only.
# After switch: re-login (or `newgrp docker`) so `wiz` can talk to the daemon,
# then from the foundation checkout: `docker compose up -d`.
{pkgs, ...}: {
  virtualisation.docker.enable = true;

  users.users.wiz.extraGroups = ["docker"];

  environment.systemPackages = [
    pkgs.docker-compose
  ];
}
