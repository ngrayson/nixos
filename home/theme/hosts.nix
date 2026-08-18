# Per-machine appearance. Edit this file to change wallpaper or color scheme.
#
# `scheme` must be a key in ./schemes/ (izar | lilac-ash).
# `wallpaper` is a repo-relative path from this file.
# `spanMonitors`: Tawa spans one image across heads via rwpspread; other hosts
# use Stylix Hyprpaper with a single wallpaper.
{
  Tawa = {
    scheme = "izar";
    wallpaper = ../../izar-utopia.png;
    wallpaperName = "izar-utopia.png";
    spanMonitors = true;
  };

  Theseus = {
    scheme = "lilac-ash";
    wallpaper = ../../login-bg.png;
    wallpaperName = "login-bg.png";
    spanMonitors = false;
  };
}
