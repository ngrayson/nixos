# Hex helpers for theme tokens (rrggbb, optional leading #).
{lib}: rec {
  strip = hex: lib.toLower (lib.removePrefix "#" hex);
  withHash = hex: "#" + strip hex;

  hexChars = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
  };

  fromHex = hex:
    lib.foldl (acc: c: acc * 16 + hexChars.${c}) 0 (lib.stringToCharacters (strip hex));

  hexPair = hex: off: fromHex (builtins.substring off 2 (strip hex));

  toRgbCsv = hex: "${toString (hexPair hex 0)},${toString (hexPair hex 2)},${toString (hexPair hex 4)}";

  toRgbaHypr = hex: alpha: "rgba(${strip hex}${alpha})";
}
