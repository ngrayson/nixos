# Weekly "scry" digest (Conveyor + Notion -> Discord), Saturdays 10:00 Hearth time.
# The package and module live in pkgs/scry; this file only supplies the secret and turns it on.
# secrets/scry.env holds CONVEYOR_API_URL, CONVEYOR_USER_TOKEN, CONVEYOR_PROJECT_ID,
# DISCORD_WEBHOOK_URL, NOTION_TOKEN, DISCORD_BOT_TOKEN (`sops secrets/scry.env`). Never print it.
# The Discord bot (scry-bot.service) files tasks from /task or the inbox channel.
# On demand: `sudo scry-now`. File a task in Nick's Tasks: `sudo scry-task <text>` (hearth-tui wraps it).
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
    # Discord ids are not secrets; DISCORD_BOT_TOKEN is in secrets/scry.env.
    bot = {
      enable = true;
      guildId = "598269695300206592";
      ownerId = "153983024411836416";
      inboxChannelId = "1540845613279875183";
    };
  };
}
