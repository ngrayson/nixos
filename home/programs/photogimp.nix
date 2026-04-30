{pkgs, ...}: let
  photoGimpRelease = pkgs.fetchzip {
    url = "https://github.com/Diolinux/PhotoGIMP/releases/download/3.0/PhotoGIMP-linux.zip";
    sha256 = "0fy3y7pyq65fp1a1f7x55gh7i6vrnrlzdl83ygl5ycfrrm3hq4dw";
    stripRoot = false;
  };
in {
  xdg.configFile."GIMP/3.0" = {
    source = "${photoGimpRelease}/PhotoGIMP-linux/.config/GIMP/3.0";
    force = true;
    recursive = true;
  };

  xdg.dataFile."applications/org.gimp.GIMP.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=PhotoGIMP
      GenericName=Image Editor
      Comment=Edit images and photos with the PhotoGIMP layout
      TryExec=/run/current-system/sw/bin/gimp
      Exec=/run/current-system/sw/bin/gimp %U
      Icon=photogimp
      Terminal=false
      Categories=Graphics;2DGraphics;RasterGraphics;
      MimeType=image/bmp;image/g3fax;image/gif;image/jpeg;image/png;image/tiff;image/x-bmp;image/x-fits;image/x-fli;image/x-icns;image/x-icon;image/x-pcx;image/x-png;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-psd;image/x-sgi;image/x-tga;image/x-xbitmap;image/x-xpixmap;image/x-xwindowdump;
      StartupNotify=true
    '';
  };

  xdg.dataFile."icons/hicolor" = {
    source = "${photoGimpRelease}/PhotoGIMP-linux/.local/share/icons/hicolor";
    force = true;
    recursive = true;
  };
}
