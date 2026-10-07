# User-writable npm prefix for the Conveyor Personal Compute CLI (@rallycry/conveyor-k3).
# Nix's npm prefix is a read-only store path, so `npm install -g` cannot write there. The CLI
# stays npm-installed rather than Nix-packaged because Conveyor's update timer re-pins it.
# See documentation/conveyor-personal-compute.md.
{config, ...}: {
  home.sessionVariables.NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";
  home.sessionPath = ["${config.home.homeDirectory}/.npm-global/bin"];
}
