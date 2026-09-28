# Weekly "scry" digest (Conveyor + Notion -> Discord), Saturdays 10:00 Hearth time.
# The package and module live in pkgs/scry; this file only supplies the secret and turns it on.
# secrets/scry.env holds CONVEYOR_API_URL, CONVEYOR_USER_TOKEN, CONVEYOR_PROJECT_ID,
# DISCORD_WEBHOOK_URL, NOTION_TOKEN (`sops secrets/scry.env`). Never print it.
# On demand: `sudo scry-now`.
{config, ...}: {
  imports = [../../pkgs/scry/module.nix];

  # Read by systemd as root before the DynamicUser drop, so root-only is enough.
  sops.secrets.scry-env = {
    sopsFile = ../../secrets/scry.env;
    format = "dotenv";
    mode = "0400";
  };

  services.scry = {
    enable = true;
    environmentFile = config.sops.secrets.scry-env.path;
  };
}
