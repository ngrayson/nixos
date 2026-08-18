# Firefox: on Wayland, tab/toolbar chrome often does not follow GTK/Stylix; userChrome
# uses `config.theme` so it matches Hyprland + Kitty. Requires legacy user stylesheets.
{config, ...}: let
  hx = config.theme.hex;
in {
  programs.firefox = {
    enable = true;
    # Preserve the existing profile location while home.stateVersion remains 25.11.
    configPath = ".mozilla/firefox";
    profiles.default = {
      id = 0;
      isDefault = true;
      settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      userChrome = ''
        /* ${config.theme.name} — home/theme */
        #navigator-toolbox {
          background-color: ${hx.depth} !important;
        }
        #TabsToolbar,
        #nav-bar,
        #PersonalToolbar,
        .browser-toolbar {
          background-color: ${hx.depth} !important;
          color: ${hx.text} !important;
        }
        .tabbrowser-tab:not([selected]) .tab-background {
          background-color: ${hx.void} !important;
        }
        .tabbrowser-tab[selected] .tab-background {
          background-color: ${hx.surface} !important;
          box-shadow: inset 0 -2px ${hx.accent} !important;
        }
        .tabbrowser-tab,
        .tabbrowser-tab .tab-label,
        .tabbrowser-tab .tab-text,
        .tabbrowser-tab .tab-secondary-label {
          color: ${hx.text} !important;
        }
        .tabbrowser-tab:not([selected]) .tab-label,
        .tabbrowser-tab:not([selected]) .tab-text {
          opacity: 0.92 !important;
        }
        .tabbrowser-tab .tab-close-button {
          color: ${hx.text} !important;
          fill: currentColor !important;
        }
      '';
    };
  };
}
