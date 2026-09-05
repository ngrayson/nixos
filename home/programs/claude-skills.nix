# ~/.claude/skills for every Claude Code session on this machine, assembled by
# Home Manager so Nick's custom Conveyor skills — and the current upstream
# @rallycry/conveyor-skills — are available in any repo, not just this one.
#
# Two sources merged into one store tree:
#   - upstream skills come from the npm registry tarball via pkgs.fetchzip (this
#     is a Nix flake repo with no package.json / node_modules of its own);
#   - custom WizOs skills are ABSOLUTE symlinks into the live checkout, so
#     editing a SKILL.md is picked up by the next session with no rebuild.
# A custom name overrides an upstream one of the same skill (conveyor-local-loop
# is Nick's fork of upstream's).
#
# Claude Code loads ~/.claude/skills/<name>/SKILL.md for every project and
# personal scope wins a name clash with a project's own .claude/skills.
#
# Bump upstream with `conveyor-skills-update` (scripts/conveyor-skills-update.sh)
# then `os-rebuild switch`. A NEW custom skill must be appended to customSkills
# below to surface outside this repo; inside this repo project scope already
# serves it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Upstream @rallycry/conveyor-skills. These two lines are rewritten in place by
  # scripts/conveyor-skills-update.sh, so keep them in this exact shape.
  version = "1.0.4";
  hash = "sha256-6K/k7k+4EaRUo77/mluen57E1Dkur6qhWCxiNIOtDOg=";
  upstream = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@rallycry/conveyor-skills/-/conveyor-skills-${version}.tgz";
    inherit hash;
  };

  # Custom skills live in the repo checkout and stay the source of truth. Linked
  # in absolutely (not via the store) so edits are live. Theseus shares this
  # checkout path, so the module is correct there too.
  customSkills = [
    "convey-her"
    "conveyor-plan-loop"
    "conveyor-local-loop"
    "conveyor-local-pack"
    "conveyor-local-task"
  ];
  repoSkills = "${config.home.homeDirectory}/.config/nixos/.claude/skills";

  # One tree: every upstream skill symlinked in, then each custom skill linked
  # over the top with `ln -sfn`, so a custom name wins the clash.
  tree = pkgs.runCommand "claude-skills" {} ''
    mkdir -p "$out"
    for dir in ${upstream}/skills/*/; do
      name="$(basename "$dir")"
      ln -s "${upstream}/skills/$name" "$out/$name"
    done
    for name in ${lib.escapeShellArgs customSkills}; do
      ln -sfn "${repoSkills}/$name" "$out/$name"
    done
  '';
in {
  # A single symlink ~/.claude/skills -> the store tree; its entries are the
  # per-skill symlinks above. Nothing else under ~/.claude is managed here
  # (settings.json there is mutable and user-owned).
  home.file.".claude/skills".source = tree;
}
