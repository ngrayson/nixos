# Shared Breeze SDDM theme with the repo-root login background.
# Used by profiles/workstation.nix and profiles/media-desktop.nix.
{pkgs}: let
  sddmLoginBg = builtins.path {
    path = ../login-bg.png;
    name = "login-bg.png";
  };
in
  pkgs.runCommand "sddm-theme-breeze-login" {} ''
    mkdir -p $out/share/sddm/themes
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze $out/share/sddm/themes/breeze-login
    chmod -R u+w $out/share/sddm/themes/breeze-login
    sed -i "s|^background=.*|background=${sddmLoginBg}|" $out/share/sddm/themes/breeze-login/theme.conf
  ''
