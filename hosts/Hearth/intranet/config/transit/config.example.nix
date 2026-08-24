# Flake reads this file. A sibling `config.nix` is ignored (gitignored).
# Buses: no agency JSON is wired (no Bitwarden transit key). Even after
# busStopIds is filled, the widget stays on the empty state until an
# endpoint is chosen in hosts/Hearth/intranet/widgets.js (search BUS_ENDPOINT).
{
  routeFrom = "Hearth";
  routeTo = "Tawa";
  busStopIds = [
    "1_1108" # 3rd Ave & Pike St, Seattle (King County Metro / OneBusAway)
    "1_455" # Westlake Station, Seattle (Link)
    "25027" # Main Street Square NB, Houston METRORail
    "25028" # Main Street Square SB, Houston METRORail
  ];
}
