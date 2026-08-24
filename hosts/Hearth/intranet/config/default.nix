# Prefer gitignored config.nix (real locations). Example files are templates.
# Flake copies omit ignored files, so this reads the checkout by absolute path.
# hearth-deploy and `os-rebuild --host Hearth` pass --impure and NIXOS_DIR.
let
  widgetNames = ["clock" "weather" "transit" "health" "gallery" "calendar"];

  checkout = let
    env = builtins.getEnv "NIXOS_DIR";
    home = builtins.getEnv "HOME";
  in
    if env != ""
    then env
    else if home != ""
    then "${home}/.config/nixos"
    else "";

  loadWidget = name: let
    local = "${checkout}/hosts/Hearth/intranet/config/${name}/config.nix";
    example = ./. + "/${name}/config.example.nix";
  in
    if checkout != "" && builtins.pathExists local
    then import (/. + local)
    else import example;
in
  builtins.listToAttrs (map (name: {
      inherit name;
      value = loadWidget name;
    })
    widgetNames)
