# Single-app Wayland kiosk profile (Go3). Imports only common/base.nix — not
# workstation.nix or media-desktop.nix — so SDDM, Plasma, Hyprland, Steam,
# VPN and the workstation package pile stay out of this closure.
#
# common/base.nix is four lines (locale, timezone, nix settings): it enables
# neither NetworkManager nor Bluetooth, so both are set explicitly here. Do
# not "fix" that by growing common/base.nix — it stays server-safe for Gcp.
{
  lib,
  pkgs,
  ...
}: let
  # The query flag tells the dashboard it is being viewed on this kiosk, which
  # is the only way the page can know: home.wizt.org is served to phones and
  # laptops too, and nothing else distinguishes the viewer. App.jsx reads it to
  # drop the TV Jellyfin link, which is useless on a wall panel that runs no
  # Jellyfin client. Other viewers load the bare URL and are unaffected.
  kioskUrl = "https://home.wizt.org/?hideJellyfin=1";
  chromiumFlags = [
    "--kiosk"
    "--app=${kioskUrl}"
    "--ozone-platform=wayland"
    # Chromium gates its tap/scroll heuristics on this. Without it the Go 3
    # panel is treated as a hover-capable mouse and taps land wrong.
    "--touch-events=enabled"
    "--noerrdialogs"
    "--disable-infobars"
    "--no-first-run"
    "--disable-session-crashed-bubble"
    "--disable-features=TranslateUI"
  ];
  # wlroots draws a cursor whenever the seat has a pointer capability, and on
  # the Go 3 the ELAN9038 panel and its stylus are the ONLY devices exposing
  # mouseN handlers (verified on the box 2026-09-01) -- so the touchscreen
  # itself is what convinces the seat a mouse exists, and the pointer parks
  # wherever it was last drawn. There is no mouse to unplug.
  #
  # A fully transparent cursor theme is the safe fix: it leaves input
  # classification alone, so touch keeps working. Quirking the panel out of
  # ID_INPUT_MOUSE would risk taking touch with it, which is worse than a
  # visible cursor. `unclutter` is X11 and does nothing here.
  #
  # The theme has to be built: only `hicolor` is installed on the box, so
  # there is no existing transparent theme to point XCURSOR_THEME at.
  transparentCursor =
    pkgs.runCommand "transparent-cursor-theme" {
      nativeBuildInputs = [pkgs.xorg.xcursorgen pkgs.imagemagick];
    } ''
      theme="$out/share/icons/transparent"
      mkdir -p "$theme/cursors"

      cat >"$theme/index.theme" <<EOF
      [Icon Theme]
      Name=transparent
      Comment=Fully transparent cursors for touch-only kiosks
      EOF

      magick -size 24x24 xc:none cursor.png
      # xcursorgen config: <size> <xhot> <yhot> <image>
      echo "24 0 0 cursor.png" >config
      xcursorgen config "$theme/cursors/left_ptr"

      # wlroots asks for a handful of names depending on what is under the
      # pointer; every one of them resolves to the same empty image.
      for name in default pointer text xterm hand1 hand2 grab grabbing \
                  top_left_arrow left_ptr_watch watch progress; do
        ln -s left_ptr "$theme/cursors/$name"
      done
    '';
in {
  imports = [
    ../common/base.nix
    ../common/tailscale.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # No blueman: a cage session has no tray to put it in. Pair over Tailscale
  # SSH with `bluetoothctl`.

  hardware.graphics.enable = true;
  services.libinput.enable = true;

  security.polkit.enable = true;
  security.rtkit.enable = true;

  # tty1 belongs to the kiosk, so nothing else may be started on it.
  #
  # cage-tty1 declares Conflicts=getty@tty1.service, and systemd-getty-generator
  # creates a getty.target want for getty@tty1 at runtime -- which is why
  # /etc/systemd/system/getty.target.wants/ looks empty while `systemctl show
  # getty.target -p Wants` lists it. switch-to-configuration therefore sees a
  # wanted unit that is not running and starts it on every activation, systemd
  # stops cage because the two conflict, and if that lands while cage's
  # ExecStartPre is still running the unit records `Failed with result
  # 'signal'`. Every deploy exited 4 over a kiosk that was actually fine.
  #
  # Masking the unit means the generator's want can never start anything, so
  # the conflict never fires. A recovery console is deliberately preserved:
  # logind still spawns autovt@ttyN on demand, so Ctrl+Alt+F2 through F6 give a
  # login prompt. Only tty1 is off limits, and a getty there was invisible
  # anyway behind cage's output.
  systemd.services."getty@tty1".enable = false;

  # cage runs exactly one Wayland client, fullscreen, on tty1 as `wiz`. That
  # is the entire session: no display manager, no compositor config, no bar,
  # and no way to escape the browser.
  services.cage = {
    enable = true;
    user = "wiz";
    environment = {
      XCURSOR_THEME = "transparent";
      XCURSOR_SIZE = "24";
      # cage inherits no session dirs, so point Xcursor straight at the theme.
      XCURSOR_PATH = "${transparentCursor}/share/icons";
    };
    program = "${lib.getExe pkgs.chromium} ${lib.concatStringsSep " " chromiumFlags}";
  };

  # Upstream's cage module sets restartIfChanged = false, so a switch tore the
  # kiosk down and left it down — the wall screen stayed blank until someone
  # SSHed in. (getty@tty1 takes tty1 the moment cage stops, because cage-tty1
  # Conflicts with it.) Nobody watches an appliance deploy, so a brief flicker
  # on every switch is strictly better than a silent dead screen.
  #
  # chvt 1 is the other half, and the reason a bare `systemctl start
  # cage-tty1` was never enough: logind grants DRM access on /dev/dri/* only
  # to seat0's ActiveSession, so cage exits ~10s after start whenever another
  # VT is active — exactly the state left behind once getty@tty1 has the
  # console. As ExecStartPre it makes every path (boot, deploy restart, manual
  # start) active-VT-correct, which is why no operator needs a separate
  # `sudo chvt 1` any more. Do not drop it: without it the ACL problem comes
  # straight back. The `+` prefix runs it as root — the unit body runs as
  # `wiz`, who cannot switch VTs.
  systemd.services.cage-tty1 = {
    restartIfChanged = lib.mkForce true;
    serviceConfig.ExecStartPre = "+${pkgs.kbd}/bin/chvt 1";
  };

  users.users.wiz = {
    isNormalUser = true;
    description = "Nick G";
    extraGroups = ["networkmanager" "wheel" "video" "input"];
    shell = pkgs.zsh;
  };
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "hm-backup";
    users.wiz.imports = [../home/kiosk.nix];
  };

  environment.shells = [pkgs.zsh];
  environment.systemPackages = with pkgs; [
    chromium
    micro
    git
    btop
    wget
    jq
  ];
}
