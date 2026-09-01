# Every named color scheme, as pure data — no module arguments, so anything
# that needs the palettes can `import ./schemes` directly. home/theme's
# home-manager module resolves one per host from here; Hearth's dashboard
# codegen (hosts/Hearth/caddy.nix) ships all of them to the browser as
# themes.js. Add a scheme here once and it appears in both.
{
  izar = import ./izar.nix;
  lilac-ash = import ./lilac-ash.nix;
  ghost = import ./ghost.nix;
}
