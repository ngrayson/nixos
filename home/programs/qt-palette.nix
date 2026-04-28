# Qt5/Qt6 platform colors via qt5ct + qt6ct (Fusion). Izar-aligned QPalette rows for qt6ct format.
# Chromamancer mapping reference: themes/izar + targets/qt/mapping.jsonc
#
# KDE (Dolphin, Kate, etc.) ignores qt*ct palette files: they use KColorScheme from
# ~/.config/kdeglobals + ~/.local/share/color-schemes/*.colors. Stylix targets.qt is off.
# Kvantum + [KDE] widgetStyle=Kvantum in kdeglobals would override Fusion. This module
# installs Izar.colors and pins ColorScheme via Home Manager activation.
#
# KDE apps: use Breeze + Izar.colors (Dolphin expects Breeze; Fusion + QT_STYLE_OVERRIDE
# looks wrong). Pure Qt apps still get Fusion + Izar via qt5ct/qt6ct (HM qt.style unset).
# Dolphin may keep a stale scheme in dolphinrc until [UiSettings] ColorScheme=* (bug 493384).
{
  config,
  lib,
  pkgs,
  ...
}: let
  h = config.home.homeDirectory;
  kde = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
  kdglobals = "${h}/.config/kdeglobals";
  dolphinrc = "${h}/.config/dolphinrc";

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

  # RGB triples for KDE .colors (same tokens as above)
  voidRgb = "1,2,18";
  depthRgb = "11,10,28";
  purpleRgb = "32,38,97";
  plumRgb = "48,41,71";
  blueRgb = "64,84,149";
  lavenderRgb = "215,202,220";
  mintRgb = "220,245,225";
  mauveRgb = "164,129,204";
  tealRgb = "106,186,181";

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

  # BreezeDark-derived structure; roles mapped to Izar (KDE apps: Dolphin, Kate, …)
  izarKdeColors = ''
    [ColorEffects:Disabled]
    Color=56,56,56
    ColorAmount=0
    ColorEffect=0
    ContrastAmount=0.65
    ContrastEffect=1
    IntensityAmount=0.1
    IntensityEffect=2

    [ColorEffects:Inactive]
    ChangeSelectionColor=true
    Color=112,111,110
    ColorAmount=0.025
    ColorEffect=2
    ContrastAmount=0.1
    ContrastEffect=2
    Enable=false
    IntensityAmount=0
    IntensityEffect=0

    [Colors:Button]
    BackgroundAlternate=${purpleRgb}
    BackgroundNormal=${purpleRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:Complementary]
    BackgroundAlternate=${purpleRgb}
    BackgroundNormal=${depthRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:Header]
    BackgroundAlternate=${depthRgb}
    BackgroundNormal=${purpleRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:Header][Inactive]
    BackgroundAlternate=${purpleRgb}
    BackgroundNormal=${depthRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:Selection]
    BackgroundAlternate=${plumRgb}
    BackgroundNormal=${tealRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${voidRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${mintRgb}
    ForegroundNegative=176,55,69
    ForegroundNeutral=198,92,0
    ForegroundNormal=${voidRgb}
    ForegroundPositive=23,104,57
    ForegroundVisited=${mauveRgb}

    [Colors:Tooltip]
    BackgroundAlternate=${depthRgb}
    BackgroundNormal=${voidRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:View]
    BackgroundAlternate=${depthRgb}
    BackgroundNormal=${depthRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [Colors:Window]
    BackgroundAlternate=${plumRgb}
    BackgroundNormal=${voidRgb}
    DecorationFocus=${tealRgb}
    DecorationHover=${tealRgb}
    ForegroundActive=${tealRgb}
    ForegroundInactive=${blueRgb}
    ForegroundLink=${blueRgb}
    ForegroundNegative=218,68,83
    ForegroundNeutral=246,116,0
    ForegroundNormal=${lavenderRgb}
    ForegroundPositive=39,174,96
    ForegroundVisited=${mauveRgb}

    [General]
    ColorScheme=Izar
    Name=Izar
    shadeSortColumn=true

    [KDE]
    contrast=4

    [WM]
    activeBackground=${purpleRgb}
    activeBlend=${lavenderRgb}
    activeForeground=${lavenderRgb}
    inactiveBackground=${plumRgb}
    inactiveBlend=${blueRgb}
    inactiveForeground=${blueRgb}
  '';
in {
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    # Omit style.name so QT_STYLE_OVERRIDE is unset — KDE reads [KDE] widgetStyle (breeze).
    style.name = null;

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

  xdg.dataFile."color-schemes/Izar.colors".text = izarKdeColors;

  home.activation.kdeIzarPalette = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${kde} --notify --file "${kdglobals}" --group General --key ColorScheme Izar
    $DRY_RUN_CMD ${kde} --notify --file "${kdglobals}" --group KDE --key widgetStyle breeze
    $DRY_RUN_CMD ${kde} --notify --file "${dolphinrc}" --group UiSettings --key ColorScheme '*'
  '';

  home.packages = [pkgs.kdePackages.dolphin];
}
