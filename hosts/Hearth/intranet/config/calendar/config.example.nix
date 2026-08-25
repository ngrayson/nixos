# Template only. Copy to config.nix (gitignored) for the Hearth build.
# The ICS URLs stay server-side: hearth-intranet-calendar fetches them every
# 15 min and merges them into /run/hearth-intranet/calendar.ics, which is the
# only thing the browser reads. Treat each url as a secret — a Google "Secret
# address in iCal format" grants read access to the whole calendar.
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
