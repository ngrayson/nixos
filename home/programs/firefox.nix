# Firefox: on Wayland, tab/toolbar chrome often does not follow GTK/Stylix; userChrome
# uses `config.theme` so it matches Hyprland + Kitty. Requires legacy user stylesheets.
#
# `profiles.default` is the HM-managed profile. Activation also copies the same chrome into
# every other relative Path= in profiles.ini (Theseus-era default-release, etc.).
{
  config,
  lib,
  pkgs,
  ...
}: let
  hx = config.theme.hex;
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
  userChromeFile = pkgs.writeText "firefox-userChrome.css" userChrome;
  fanOut = pkgs.writeText "firefox-fanout-userchrome.py" ''
    import os
    import re
    import sys

    profiles_ini, chrome_src, pref_line = sys.argv[1:4]
    root = os.path.dirname(profiles_ini)
    if not os.path.isfile(profiles_ini):
        raise SystemExit(0)

    css = open(chrome_src, encoding="utf-8").read()
    text = open(profiles_ini, encoding="utf-8").read()
    paths = []
    current = {}
    for raw in text.splitlines() + ["[end]"]:
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            if current.get("path") and current.get("relative", "1") != "0":
                paths.append(current["path"])
            current = {}
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().lower()
        if key == "path":
            current["path"] = value.strip()
        elif key == "isrelative":
            current["relative"] = value.strip()

    for rel in paths:
        prof = os.path.join(root, rel)
        chrome_dir = os.path.join(prof, "chrome")
        dest = os.path.join(chrome_dir, "userChrome.css")
        if os.path.islink(dest):
            target = os.path.realpath(dest)
            if target.startswith("/nix/store/"):
                continue
        os.makedirs(chrome_dir, exist_ok=True)
        open(dest, "w", encoding="utf-8").write(css)

        user_js = os.path.join(prof, "user.js")
        if os.path.islink(user_js) and os.path.realpath(user_js).startswith("/nix/store/"):
            continue
        try:
            existing = open(user_js, encoding="utf-8").read()
        except FileNotFoundError:
            existing = ""
        pref_re = re.compile(
            r'^\s*user_pref\(\s*"toolkit\.legacyUserProfileCustomizations\.stylesheets"\s*,.*$',
            re.M,
        )
        if pref_re.search(existing):
            updated = pref_re.sub(pref_line, existing, count=1)
        else:
            updated = existing
            if updated and not updated.endswith("\n"):
                updated += "\n"
            updated += pref_line + "\n"
        if updated != existing:
            open(user_js, "w", encoding="utf-8").write(updated)
  '';
in {
  programs.firefox = {
    enable = true;
    # Preserve the existing profile location while home.stateVersion remains 25.11.
    configPath = ".mozilla/firefox";
    profiles.default = {
      id = 0;
      isDefault = true;
      settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      userChrome = userChrome;
    };
  };

  home.activation.firefoxUserChromeFanout = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${lib.getExe pkgs.python3} ${fanOut} \
      "${config.home.homeDirectory}/.mozilla/firefox/profiles.ini" \
      ${userChromeFile} \
      ${lib.escapeShellArg ''user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);''}
  '';
}
