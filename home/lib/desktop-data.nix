# `*.desktop` in appDir → ~/.local/share/applications/ (see desktop/applications README)
{
  lib,
  appDir,
}:
lib.listToAttrs (
  map (n: {
    name = "applications/${n}";
    value = {
      source = appDir + "/${n}";
      force = true;
    };
  })
  (lib.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".desktop" n) (builtins.readDir appDir)))
)
