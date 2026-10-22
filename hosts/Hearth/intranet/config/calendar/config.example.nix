# Not read by the build any more. The feed list moved to the sops secret
# secrets/hearth-calendar-feeds.yaml (key `feeds`, a JSON string), because a
# value read here was written into the world-readable Nix store. Edit with
# `sops secrets/hearth-calendar-feeds.yaml`. The entry shape is unchanged.
# Treat each url as a secret: a Google "Secret address in iCal format"
# grants read access to the whole calendar.
#
# calendarIcsUrls entries:
#   name        display label shown on events from this feed (required)
#   url         the ICS/secret-address URL (required)
#   calendarId  optional, e.g. you@gmail.com or
#               abc123@group.calendar.google.com. Only used to build the
#               "Open in Google Calendar" deep link; without it the modal
#               falls back to calendar.google.com.
#
# Google caches these feeds, so edits can take a few hours to appear.
# calendarIcsUrl (single string) still works and is treated as one unnamed feed.
{
  calendarIcsUrl = null;
  calendarIcsUrls = [
    # {
    #   name = "Family";
    #   url = "https://calendar.google.com/calendar/ical/.../basic.ics";
    #   calendarId = "abc123@group.calendar.google.com";
    # }
  ];
}
