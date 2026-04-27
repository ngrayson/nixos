{
  config,
  lib,
  pkgs,
  ...
}: {
  home.activation.plasmaMultiMonitor = lib.hm.dag.entryAfter ["writeBoundary"] ''
    kwrite="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"
    kwinrc="${config.home.homeDirectory}/.config/kwinrc"
    if [ -f "$kwinrc" ]; then
      $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group Windows --key SeparateScreenFocus --type bool true
      $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group TabBox --key MultiScreenMode --type int 2
      if $DRY_RUN_CMD grep -q '^\[Script-krohnkite\]' "$kwinrc"; then
        $DRY_RUN_CMD "$kwrite" --file "$kwinrc" --group Script-krohnkite --key layoutPerDesktop --type bool true
      fi
    fi
  '';
}
