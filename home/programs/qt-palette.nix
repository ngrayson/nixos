# Izar palette for Qt/KDE: Home Manager `qt` uses KDE platform theme + Breeze so Dolphin, Kate,
# and other KF6 apps use KColorScheme (~/.local/share/color-schemes/Izar.colors + kdeglobals).
# Stylix targets.qt is off.
#
# Do not use QT_QPA_PLATFORMTHEME=qt5ct with Dolphin — it clashes with KDE’s integration and
# looks “unthemed”. Generic Qt apps follow the same kdeglobals ColorScheme via plasma-integration.
# Chromamancer reference: themes/izar + targets/qt/mapping.jsonc
{
  config,
  lib,
  pkgs,
  ...
}: let
  h = config.home.homeDirectory;
  kwrite = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";
  kdglobals = "${h}/.config/kdeglobals";
  dolphinrc = "${h}/.config/dolphinrc";

  voidRgb = "1,2,18";
  depthRgb = "11,10,28";
  purpleRgb = "32,38,97";
  plumRgb = "48,41,71";
  blueRgb = "64,84,149";
  lavenderRgb = "215,202,220";
  mintRgb = "220,245,225";
  mauveRgb = "164,129,204";
  tealRgb = "106,186,181";

  # BreezeDark-shaped scheme; roles mapped to Izar tokens
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
    platformTheme.name = lib.mkForce "kde";
    style.name = "breeze";
  };

  xdg.dataFile."color-schemes/Izar.colors".text = izarKdeColors;

  home.activation.kdeIzarPalette = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${kwrite} --notify --file "${kdglobals}" --group General --key ColorScheme Izar
    $DRY_RUN_CMD ${kwrite} --notify --file "${kdglobals}" --group KDE --key widgetStyle breeze
    $DRY_RUN_CMD ${kwrite} --notify --file "${dolphinrc}" --group UiSettings --key ColorScheme '*'
  '';

  home.packages = [pkgs.kdePackages.dolphin];
}
