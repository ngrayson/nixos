import { useEffect, useState } from "react";
import ICAL from "ical.js";
import Modal from "../components/Modal.jsx";
import { Heading, ICO, Icon } from "../lib/icons.jsx";
import { formatTime, useTimeFormat } from "../lib/timeFormat.js";

const GRID_WEEKS = 3;
const BIG_DAYS = 3;
// A malformed or unbounded RRULE must not spin forever; the window is 3 weeks
// so this is far more room than any real feed needs.
const MAX_OCCURRENCES = 400;
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function startOfDay(date) {
  const out = new Date(date);
  out.setHours(0, 0, 0, 0);
  return out;
}

function addDays(date, count) {
  const out = new Date(date);
  out.setDate(out.getDate() + count);
  return out;
}

function dayKey(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function text(comp, name) {
  const value = comp.getFirstPropertyValue(name);
  return value == null ? "" : String(value);
}

function fields(comp) {
  return {
    uid: text(comp, "uid"),
    summary: text(comp, "summary") || "(untitled)",
    location: text(comp, "location"),
    description: text(comp, "description"),
    calendar: text(comp, "x-hearth-calendar"),
    calendarId: text(comp, "x-hearth-calendar-id"),
  };
}

function occurrence(comp, startTime, endTime) {
  const start = startTime.toJSDate();
  const end = endTime ? endTime.toJSDate() : start;
  return { ...fields(comp), allDay: Boolean(startTime.isDate), start, end };
}

function registerZones(root) {
  for (const zone of root.getAllSubcomponents("vtimezone")) {
    const id = zone.getFirstPropertyValue("tzid");
    if (id && !ICAL.TimezoneService.has(id)) ICAL.TimezoneService.register(zone);
  }
}

function expand(event, from, to) {
  const out = [];
  const iterator = event.iterator();
  let next;
  let guard = 0;
  while ((next = iterator.next())) {
    guard += 1;
    if (guard > MAX_OCCURRENCES) break;
    if (next.toJSDate() >= to) break;
    const detail = event.getOccurrenceDetails(next);
    if (detail.endDate.toJSDate() <= from) continue;
    out.push(occurrence(detail.item.component, detail.startDate, detail.endDate));
  }
  return out;
}

function parseEvents(ics, from, to) {
  const root = new ICAL.Component(ICAL.parse(ics));
  registerZones(root);

  const masters = [];
  const overrides = [];
  for (const comp of root.getAllSubcomponents("vevent")) {
    if (comp.hasProperty("recurrence-id")) overrides.push(comp);
    else masters.push(comp);
  }

  const events = new Map();
  for (const comp of masters) {
    const event = new ICAL.Event(comp);
    events.set(event.uid, event);
  }

  const orphans = [];
  for (const comp of overrides) {
    const parent = events.get(text(comp, "uid"));
    if (parent) parent.relateException(comp);
    // An override whose master is outside the feed still deserves to show up.
    else orphans.push(comp);
  }

  const out = [];
  for (const event of events.values()) {
    if (event.isRecurring()) {
      out.push(...expand(event, from, to));
      continue;
    }
    const end = event.endDate || event.startDate;
    if (end.toJSDate() <= from || event.startDate.toJSDate() >= to) continue;
    out.push(occurrence(event.component, event.startDate, end));
  }
  for (const comp of orphans) {
    const event = new ICAL.Event(comp, { strictExceptions: false });
    const end = event.endDate || event.startDate;
    if (end.toJSDate() <= from || event.startDate.toJSDate() >= to) continue;
    out.push(occurrence(comp, event.startDate, end));
  }

  out.sort((a, b) => a.start - b.start || a.summary.localeCompare(b.summary));
  return out;
}

// An all-day VEVENT ends on an exclusive DTEND, so a single day runs
// 25th->26th. Step back off that boundary before listing covered days.
function coveredDays(event) {
  const days = [];
  const last = event.allDay ? new Date(event.end.getTime() - 1) : event.end;
  let cursor = startOfDay(event.start);
  const stop = startOfDay(last < event.start ? event.start : last);
  let guard = 0;
  while (cursor <= stop && guard < 60) {
    days.push(dayKey(cursor));
    cursor = addDays(cursor, 1);
    guard += 1;
  }
  return days;
}

function fmtTime(date, hour12) {
  return formatTime(date, { hour12 });
}

function fmtWhen(event, hour12) {
  if (event.allDay) return "All day";
  const start = fmtTime(event.start, hour12);
  if (!event.end || event.end <= event.start) return start;
  return `${start} – ${fmtTime(event.end, hour12)}`;
}

function fmtDayLabel(date, today) {
  const diff = Math.round((startOfDay(date) - startOfDay(today)) / 86400000);
  if (diff === 0) return "Today";
  if (diff === 1) return "Tomorrow";
  return date.toLocaleDateString(undefined, { weekday: "long" });
}

// Google's event links are base64url("<eventId> <calendarId>"). The ICS UID is
// "<eventId>@google.com"; without a configured calendarId there is nothing to
// pair it with, so fall back to the plain calendar.
function googleEventUrl(event) {
  const id = String(event.uid || "").replace(/@google\.com$/i, "");
  if (!event.calendarId || !id || !/^[A-Za-z0-9_-]+$/.test(id)) {
    return "https://calendar.google.com";
  }
  try {
    return (
      "https://calendar.google.com/calendar/event?eid=" +
      btoa(`${id} ${event.calendarId}`).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
    );
  } catch {
    return "https://calendar.google.com";
  }
}

function EventModal({ event, hour12, onClose }) {
  const url = googleEventUrl(event);
  return (
    <Modal icon={ICO.calendar} title={event.summary} onClose={onClose}>
      <p className="facts">
        <span className="fact">
          <Icon code={ICO.clock} />
          {event.start.toLocaleDateString(undefined, {
            weekday: "long",
            month: "short",
            day: "numeric",
          })}
          {" · "}
          {fmtWhen(event, hour12)}
        </span>
        {event.calendar ? (
          <span className="fact">
            <Icon code={ICO.calendar} />
            {event.calendar}
          </span>
        ) : null}
      </p>
      {event.location ? <p className="cal-detail">{event.location}</p> : null}
      {event.description ? <p className="cal-detail">{event.description}</p> : null}
      <p className="cal-actions">
        <a className="cal-open" href={url} target="_blank" rel="noreferrer noopener">
          Open in Google Calendar
        </a>
      </p>
    </Modal>
  );
}

function Upcoming({ days, hour12, onOpen }) {
  if (!days.length) return null;
  return (
    <div className="cal-upcoming">
      {days.map((day) => (
        <section key={day.key}>
          <h3>
            {day.label}
            <span className="cal-upcoming-date">
              {day.date.toLocaleDateString(undefined, { month: "short", day: "numeric" })}
            </span>
          </h3>
          <ul>
            {day.events.map((event, i) => (
              <li key={`${event.uid}-${i}`}>
                <button type="button" onClick={() => onOpen(event)}>
                  <span className="cal-when">{fmtWhen(event, hour12)}</span>
                  <span className="cal-summary">{event.summary}</span>
                  {event.calendar ? <span className="cal-src">{event.calendar}</span> : null}
                </button>
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

function Grid({ weeks, byDay, todayKey, month, hour12, onOpen }) {
  return (
    <table className="cal cal-weeks">
      <thead>
        <tr>
          {WEEKDAYS.map((d) => (
            <th key={d}>{d}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {weeks.map((week, wi) => (
          <tr key={wi}>
            {week.map((date) => {
              const key = dayKey(date);
              const events = byDay.get(key) || [];
              const classes = [
                key === todayKey ? "today" : "",
                date.getMonth() === month ? "" : "cal-other-month",
              ]
                .filter(Boolean)
                .join(" ");
              return (
                <td key={key} className={classes || undefined}>
                  <span className="cal-daynum">{date.getDate()}</span>
                  {events.slice(0, 3).map((event, i) => (
                    <button
                      type="button"
                      className="cal-chip"
                      key={`${event.uid}-${i}`}
                      onClick={() => onOpen(event)}
                      title={`${fmtWhen(event, hour12)} ${event.summary}`}
                    >
                      {event.summary}
                    </button>
                  ))}
                  {events.length > 3 ? (
                    <span className="cal-more">+{events.length - 3}</span>
                  ) : null}
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function Calendar() {
  const { hour12 } = useTimeFormat();
  const [events, setEvents] = useState([]);
  const [open, setOpen] = useState(null);

  const today = startOfDay(new Date());
  const gridStart = addDays(today, -today.getDay());
  const gridEnd = addDays(gridStart, GRID_WEEKS * 7);

  useEffect(() => {
    let cancelled = false;
    fetch("/calendar.ics")
      .then((res) => {
        if (!res.ok) throw new Error("ics " + res.status);
        return res.text();
      })
      .then((ics) => {
        if (cancelled) return;
        setEvents(parseEvents(ics, gridStart, gridEnd));
      })
      .catch(() => {
        if (!cancelled) setEvents([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const byDay = new Map();
  for (const event of events) {
    for (const key of coveredDays(event)) {
      if (!byDay.has(key)) byDay.set(key, []);
      byDay.get(key).push(event);
    }
  }

  const upcoming = [];
  for (let i = 0; i < BIG_DAYS; i += 1) {
    const date = addDays(today, i);
    const dayEvents = byDay.get(dayKey(date)) || [];
    if (dayEvents.length) {
      upcoming.push({
        key: dayKey(date),
        date,
        label: fmtDayLabel(date, today),
        events: dayEvents,
      });
    }
  }

  const weeks = [];
  for (let w = 0; w < GRID_WEEKS; w += 1) {
    const week = [];
    for (let d = 0; d < 7; d += 1) week.push(addDays(gridStart, w * 7 + d));
    weeks.push(week);
  }

  return (
    <>
      <Heading title="Calendar" code={ICO.calendar} />
      <p className="cal-caption">
        {today.toLocaleString(undefined, { month: "long", year: "numeric" })}
      </p>
      <Upcoming days={upcoming} hour12={hour12} onOpen={setOpen} />
      <Grid
        weeks={weeks}
        byDay={byDay}
        todayKey={dayKey(today)}
        month={today.getMonth()}
        hour12={hour12}
        onOpen={setOpen}
      />
      {open ? <EventModal event={open} hour12={hour12} onClose={() => setOpen(null)} /> : null}
    </>
  );
}
