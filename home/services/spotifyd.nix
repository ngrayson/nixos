{nixosConfig ? null, ...}: let
  hostIsTawa = nixosConfig != null && nixosConfig.networking.hostName == "Tawa";
in {
  services.spotifyd = {
    enable = true;
    settings.global = {
      device_name =
        if hostIsTawa
        then "Tawa"
        else "spotifyd";
      device_type = "computer";
      backend = "pulseaudio";
      bitrate = 320;
      use_mpris = true;
      disable_discovery = false;
    };
  };
}
