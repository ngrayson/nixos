{
  lib,
  config,
  pkgs,
  ...
}: let
  photoGimpRelease = pkgs.fetchzip {
    url = "https://github.com/Diolinux/PhotoGIMP/releases/download/3.0/PhotoGIMP-linux.zip";
    sha256 = "0fy3y7pyq65fp1a1f7x55gh7i6vrnrlzdl83ygl5ycfrrm3hq4dw";
    stripRoot = false;
  };
  sourceConfig = "${photoGimpRelease}/PhotoGIMP-linux/.config/GIMP/3.0";
  targetConfig = "${config.home.homeDirectory}/.config/GIMP/3.0";
in {
  home.activation.photoGimpProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    _photogimp_src="${sourceConfig}"
    _photogimp_dst="${targetConfig}"
    _photogimp_marker="$_photogimp_dst/.photogimp-nix-managed"

    mkdir -p "${config.home.homeDirectory}/.config/GIMP"

    # Migrate from old HM symlink layout (caused loops and read-only behavior in GIMP).
    if [ -L "$_photogimp_dst/gimprc" ] || [ -L "$_photogimp_dst/theme.css" ]; then
      if [ -d "$_photogimp_dst" ] && [ ! -L "$_photogimp_dst" ]; then
        $DRY_RUN_CMD mv "$_photogimp_dst" "''${_photogimp_dst}.hm-backup-pre-photogimp-migrate"
      fi
      $DRY_RUN_CMD rm -rf "$_photogimp_dst"
    fi

    # Seed config once; keep files writable so GIMP can persist user changes.
    if [ ! -e "$_photogimp_marker" ]; then
      if [ -d "$_photogimp_dst" ]; then
        # Previous attempts may have left read-only files/dirs copied from the store.
        $DRY_RUN_CMD ${pkgs.findutils}/bin/find "$_photogimp_dst" -type d -exec ${pkgs.coreutils}/bin/chmod u+rwx {} +
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+rwX "$_photogimp_dst"
      fi
      $DRY_RUN_CMD rm -rf "$_photogimp_dst"
      $DRY_RUN_CMD mkdir -p "$_photogimp_dst"
      $DRY_RUN_CMD cp -r --no-preserve=mode,ownership "$_photogimp_src"/. "$_photogimp_dst"/
    fi

    # Files copied from the Nix store can be read-only; ensure GIMP can update them.
    if [ -d "$_photogimp_dst" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+rwX "$_photogimp_dst"
    fi

    # Let GIMP regenerate theme.css from current system theme (Stylix/GTK integration),
    # while preserving PhotoGIMP layout/shortcuts from the rest of the profile.
    if [ -f "$_photogimp_dst/theme.css" ]; then
      $DRY_RUN_CMD rm -f "$_photogimp_dst/theme.css"
    fi

    if [ -d "$_photogimp_dst" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/touch "$_photogimp_marker"
    fi
  '';

  xdg.dataFile."icons/hicolor" = {
    source = "${photoGimpRelease}/PhotoGIMP-linux/.local/share/icons/hicolor";
    force = true;
    recursive = true;
  };
}
