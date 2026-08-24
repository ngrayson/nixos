# Household-dashboard knobs for home.wizt.org.
# Leave lat/lon and routes null/empty until Nick fills them in; the page
# renders configure-me states instead of crashing.
#
# Buses: no agency JSON is wired (no Bitwarden transit key). Even after
# busStopIds is filled, the widget stays on the empty state until an
# endpoint is chosen in hosts/Hearth/intranet/widgets.js (search BUS_ENDPOINT).
{
  latitude = null;
  longitude = null;
  routeFrom = "";
  routeTo = "";
  busStopIds = [];
  galleryDir = "/mnt/cold/share/gallery";
  calendarIcsUrl = null;
}
