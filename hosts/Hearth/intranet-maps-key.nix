# Write /run/hearth-intranet/maps-key.js from the sops Maps browser key.
# The HUD loads that file as 'self'. Fail closed: empty string if the secret
# is missing. Never print the key.
{
  config,
  lib,
  pkgs,
  ...
}: let
  mapsKeyFile = ../../secrets/hearth-google-maps-browser-key.yaml;
  haveKey = builtins.pathExists mapsKeyFile;
  writer = pkgs.writeShellApplication {
    name = "hearth-intranet-maps-key";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      set -euo pipefail
      mkdir -p /run/hearth-intranet
      python3 - <<'PY'
      import json, os, pathlib
      dest = pathlib.Path("/run/hearth-intranet/maps-key.js")
      src = os.environ.get("HEARTH_MAPS_KEY_FILE", "")
      key = ""
      if src:
          try:
              key = pathlib.Path(src).read_text(encoding="utf-8").strip()
          except OSError:
              key = ""
      dest.write_text("window.hearthMapsKey = " + json.dumps(key) + ";\n", encoding="utf-8")
      dest.chmod(0o644)
      PY
    '';
  };
in {
  sops.secrets.hearth-google-maps-browser-key = lib.mkIf haveKey {
    sopsFile = mapsKeyFile;
    key = "apiKey";
    owner = "hearth-intranet";
    group = "hearth-intranet";
    mode = "0400";
  };

  systemd.services.hearth-intranet-maps-key = {
    description = "Write HUD Google Maps browser key JS";
    wantedBy = ["multi-user.target"];
    after = ["sops-install-secrets.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "hearth-intranet";
      Group = "hearth-intranet";
      ExecStart = "${writer}/bin/hearth-intranet-maps-key";
      Environment = lib.optionals haveKey [
        "HEARTH_MAPS_KEY_FILE=${config.sops.secrets.hearth-google-maps-browser-key.path}"
      ];
      ReadWritePaths = ["/run/hearth-intranet"];
    };
  };
}
