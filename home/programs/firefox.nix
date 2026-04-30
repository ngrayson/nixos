# Firefox: on Wayland, tab/toolbar chrome often does not follow GTK/Stylix; userChrome forces Izar
# (void / depth / plum / teal) so it matches Hyprland + Kitty. Requires legacy user stylesheets.
{...}: {
  programs.firefox = {
    enable = true;
    profiles.default = {
      id = 0;
      isDefault = true;
      settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      userChrome = ''
        /* Izar — same tokens as chromamancer themes/izar + nixos/themes/izar-base16.yaml */
        #navigator-toolbox {
          background-color: #0b0a1c !important;
        }
        #TabsToolbar,
        #nav-bar,
        #PersonalToolbar,
        .browser-toolbar {
          background-color: #0b0a1c !important;
          color: #d7cadc !important;
        }
        .tabbrowser-tab:not([selected]) .tab-background {
          background-color: #010212 !important;
        }
        .tabbrowser-tab[selected] .tab-background {
          background-color: #302947 !important;
          box-shadow: inset 0 -2px #6abab5 !important;
        }
      '';
    };
  };
}
