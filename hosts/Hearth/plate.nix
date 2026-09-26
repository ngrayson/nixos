# Weekly "plate" digest (Conveyor + Notion -> Discord), Saturdays 10:00 Hearth time.
# The package and module live in pkgs/plate; this file only supplies the secret and turns it on.
# secrets/plate.env holds CONVEYOR_API_URL, CONVEYOR_USER_TOKEN, CONVEYOR_PROJECT_ID,
# DISCORD_WEBHOOK_URL, NOTION_TOKEN (`sops secrets/plate.env`). Never print it.
# On demand: `sudo plate-now`.
{config, ...}: {
  imports = [../../pkgs/plate/module.nix];

  # Read by systemd as root before the DynamicUser drop, so root-only is enough.
  sops.secrets.plate-env = {
    sopsFile = ../../secrets/plate.env;
    format = "dotenv";
    mode = "0400";
  };

  services.plate = {
    enable = true;
    environmentFile = config.sops.secrets.plate-env.path;
  };
}
