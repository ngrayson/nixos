# Qt5/Qt6 platform colors via qt5ct + qt6ct (Fusion style). Izar-aligned QPalette rows for qt6ct color scheme format.
# Chromamancer mapping reference: themes/izar + targets/qt/mapping.jsonc
{
  config,
  lib,
  pkgs,
  ...
}: let
  h = config.home.homeDirectory;

  # Theme tokens: #RRGGBB or #RRGGBBAA -> QColor HexArgb #aarrggbb
  aa = rgb:
    if builtins.stringLength rgb >= 8
    then "#" + lib.toLower (lib.substring 6 2 rgb + lib.substring 0 6 rgb)
    else "#ff" + lib.toLower (lib.substring 0 6 rgb);

  void = aa "010212FF";
  depth = aa "0B0A1CFF";
  purple = aa "202661FF";
  plum = aa "302947FF";
  blue = aa "405495FF";
  lavender = aa "D7CADCFF";
  mint = aa "DCF5E1FF";
  mauve = aa "A481CCFF";
  teal = aa "6ABAB5FF";

  # QPalette::ColorRole order 0..21 (Qt 6.6+ Accent last). See qt6ct paletteeditdialog.cpp labels.
  active = [
    lavender # WindowText
    purple # Button
    depth # Light
    depth # Midlight
    plum # Dark
    purple # Mid
    lavender # Text
    mint # BrightText
    lavender # ButtonText
    depth # Base
    void # Window
    plum # Shadow
    teal # Highlight
    lavender # HighlightedText
    teal # Link
    mauve # LinkVisited
    purple # AlternateBase
    void # NoRole
    depth # ToolTipBase
    lavender # ToolTipText
    plum # PlaceholderText
    teal # Accent
  ];

  inactive = [
    blue # WindowText — inactive_text / muted chrome
    purple
    depth
    depth
    plum
    purple
    lavender
    mint
    lavender
    depth
    void
    plum
    blue # Highlight — chrome_focus_muted
    lavender
    teal
    mauve
    purple
    void
    depth
    lavender
    plum
    teal
  ];

  disabled = [
    plum
    purple
    depth
    depth
    plum
    purple
    plum
    plum
    plum
    depth
    void
    plum
    teal
    plum
    blue
    mauve
    purple
    void
    depth
    plum
    plum
    teal
  ];

  csv = colors: lib.concatStringsSep ", " colors;

  izarColorScheme = ''
    [ColorScheme]
    active_colors=${csv active}
    inactive_colors=${csv inactive}
    disabled_colors=${csv disabled}
  '';
in {
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "Fusion";

    qt6ctSettings.Appearance = {
      style = "Fusion";
      custom_palette = true;
      standard_dialogs = "default";
      color_scheme_path = "${h}/.config/qt6ct/colors/Izar.conf";
    };

    qt5ctSettings.Appearance = {
      style = "Fusion";
      custom_palette = true;
      standard_dialogs = "default";
      color_scheme_path = "${h}/.config/qt5ct/colors/Izar.conf";
    };
  };

  xdg.configFile = {
    "qt6ct/colors/Izar.conf".text = izarColorScheme;
    "qt5ct/colors/Izar.conf".text = izarColorScheme;
  };

  home.packages = [pkgs.kdePackages.dolphin];
}
