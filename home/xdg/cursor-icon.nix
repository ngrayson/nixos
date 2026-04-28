# AppImage ships Icon=co.anysphere.cursor but only cursor.png inside the mount; menus resolve
# icons from ~/.local/share/icons (hicolor). Install the expected name so launchers show artwork.
{...}: let
  icon = ../../desktop/icons/co.anysphere.cursor.png;
in {
  xdg.dataFile = {
    "icons/hicolor/48x48/apps/co.anysphere.cursor.png" = {source = icon;};
    "icons/hicolor/64x64/apps/co.anysphere.cursor.png" = {source = icon;};
    "icons/hicolor/128x128/apps/co.anysphere.cursor.png" = {source = icon;};
    "icons/hicolor/256x256/apps/co.anysphere.cursor.png" = {source = icon;};
    "icons/hicolor/512x512/apps/co.anysphere.cursor.png" = {source = icon;};
  };
}
