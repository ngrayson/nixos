# Firefox: on Wayland, tab/toolbar chrome often does not follow GTK/Stylix; userChrome forces Izar
# (void / depth / plum / teal) so it matches Hyprland + Kitty. Requires legacy user stylesheets.
{...}: {
  programs.firefox = {
    enable = true;
    # Preserve the existing profile location while home.stateVersion remains 25.11.
    configPath = ".mozilla/firefox";
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
        /* Tab labels (Proton inherits a dark text color onto plum — force Izar lavender) */
        .tabbrowser-tab,
        .tabbrowser-tab .tab-label,
        .tabbrowser-tab .tab-text,
        .tabbrowser-tab .tab-secondary-label {
          color: #d7cadc !important;
        }
        .tabbrowser-tab:not([selected]) .tab-label,
        .tabbrowser-tab:not([selected]) .tab-text {
          opacity: 0.92 !important;
        }
        .tabbrowser-tab .tab-close-button {
          color: #d7cadc !important;
          fill: currentColor !important;
        }
      '';
    };
  };
}
