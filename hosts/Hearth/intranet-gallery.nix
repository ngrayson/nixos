# Oneshot + timer: list gallery images into /run/hearth-intranet/gallery.json.
# Missing dir → empty hrefs. Do not fail caddy.
{pkgs, ...}: let
  galleryDir = (import ./intranet/config).gallery.galleryDir or "";
  extraRo =
    if galleryDir != ""
    then [galleryDir]
    else [];
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-gallery";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      python3 - ${pkgs.writeText "hearth-gallery-dir.txt" galleryDir} <<'PY'
      import json, os, sys, time

      root = open(sys.argv[1], encoding="utf-8").read().strip()
      out = "/run/hearth-intranet/gallery.json"
      exts = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"}
      hrefs = []
      if root and os.path.isdir(root):
          for name in sorted(os.listdir(root)):
              ext = os.path.splitext(name)[1].lower()
              if ext in exts:
                  hrefs.append("/gallery/" + name)
      payload = {"hrefs": hrefs, "generatedAt": int(time.time())}
      tmp = out + ".tmp"
      with open(tmp, "w", encoding="utf-8") as fh:
          json.dump(payload, fh)
          fh.write("\n")
      os.chmod(tmp, 0o644)
      os.replace(tmp, out)
      PY
    '';
  };
in {
  systemd.services.hearth-intranet-gallery = {
    description = "Write Hearth intranet gallery.json";
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-gallery";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/run/hearth-intranet"];
      ReadOnlyPaths = extraRo;
      RestrictAddressFamilies = ["AF_UNIX"];
    };
  };

  systemd.timers.hearth-intranet-gallery = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "5min";
      AccuracySec = "15s";
      Unit = "hearth-intranet-gallery.service";
    };
  };
}
