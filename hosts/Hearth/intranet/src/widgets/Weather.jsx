import { useEffect, useState } from "react";
import Modal from "../components/Modal.jsx";
import { widget } from "../lib/config.js";
import { Empty, Fact, Heading, ICO, Icon } from "../lib/icons.jsx";

const FORECAST_DAYS = 7;
const STRIP_DAYS = 4;

function tempUnit(weather) {
  const u = String(weather.temperatureUnit || "F").toUpperCase();
  return u === "C" ? "C" : "F";
}

function tempTone(deg, unit) {
  if (deg == null || isNaN(deg)) return "";
  const f = unit === "C" ? Number(deg) * (9 / 5) + 32 : Number(deg);
  if (f <= 32) return "tone-cold";
  if (f <= 50) return "tone-cool";
  if (f <= 75) return "";
  if (f <= 85) return "tone-warm";
  if (f <= 95) return "tone-hot";
  return "tone-extreme";
}

function aqiTone(aqi) {
  if (aqi == null || isNaN(aqi)) return "";
  const n = Number(aqi);
  if (n <= 50) return "tone-aqi-good";
  if (n <= 100) return "tone-aqi-moderate";
  if (n <= 150) return "tone-aqi-usg";
  if (n <= 200) return "tone-aqi-unhealthy";
  if (n <= 300) return "tone-aqi-very";
  return "tone-aqi-hazard";
}

function weatherLabel(code) {
  if (code === 0) return "Clear";
  if (code <= 3) return "Cloudy";
  if (code === 45 || code === 48) return "Fog";
  if (code >= 51 && code <= 67) return "Rain";
  if (code >= 71 && code <= 77) return "Snow";
  if (code >= 80 && code <= 82) return "Showers";
  if (code >= 95) return "Thunder";
  return `Weather ${code}`;
}

function weatherIcon(code) {
  if (code === 0) return ICO.sunny;
  if (code === 1) return ICO.overcast;
  if (code <= 3) return ICO.cloudy;
  if (code === 45 || code === 48) return ICO.fog;
  if (code >= 51 && code <= 55) return ICO.drizzle;
  if (code >= 56 && code <= 67) return ICO.rain;
  if (code >= 71 && code <= 77) return ICO.snow;
  if (code >= 80 && code <= 82) return ICO.showers;
  if (code >= 85 && code <= 86) return ICO.snow;
  if (code >= 95) return ICO.thunder;
  return ICO.cloudy;
}

function moonPhase(frac) {
  const phases = [
    { code: "e38d", label: "New moon" },
    { code: "e390", label: "Waxing crescent" },
    { code: "e394", label: "First quarter" },
    { code: "e397", label: "Waxing gibbous" },
    { code: "e39b", label: "Full moon" },
    { code: "e39e", label: "Waning gibbous" },
    { code: "e3a2", label: "Last quarter" },
    { code: "e3a5", label: "Waning crescent" },
  ];
  if (frac == null || isNaN(frac)) return phases[0];
  const t = ((Number(frac) % 1) + 1) % 1;
  return phases[Math.round(t * 8) % 8];
}

function fmtClock(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
}

function fmtDeg(value) {
  if (value == null || isNaN(value)) return "—";
  return `${Math.round(value)}°`;
}

// daily.time entries are bare YYYY-MM-DD in the location's own timezone. Handing
// those to new Date() reads them as UTC midnight, which renders as the previous
// day at any negative offset, so build and format the date in UTC throughout.
function utcDay(iso) {
  const [y, m, d] = String(iso || "")
    .split("-")
    .map(Number);
  if (!y || !m || !d) return null;
  return new Date(Date.UTC(y, m - 1, d));
}

function fmtDay(iso, opts) {
  const date = utcDay(iso);
  if (!date) return "—";
  return date.toLocaleDateString(undefined, { ...opts, timeZone: "UTC" });
}

function at(list, i) {
  return Array.isArray(list) ? list[i] : undefined;
}

function placeDetail(loc) {
  return String((loc && loc.detail) || "long").toLowerCase() === "short" ? "short" : "long";
}

function fetchJson(url) {
  return fetch(url).then((res) => {
    if (!res.ok) throw new Error(`${url} ${res.status}`);
    return res.json();
  });
}

function loadPlace(loc, unit) {
  const temp = unit === "C" ? "celsius" : "fahrenheit";
  const wind = unit === "C" ? "kmh" : "mph";
  const forecast =
    "https://api.open-meteo.com/v1/forecast?latitude=" +
    encodeURIComponent(loc.latitude) +
    "&longitude=" +
    encodeURIComponent(loc.longitude) +
    "&current=temperature_2m,weather_code,wind_speed_10m" +
    "&daily=sunrise,sunset,moonrise,moonset,moon_phase" +
    ",temperature_2m_max,temperature_2m_min,weather_code" +
    ",precipitation_probability_max,wind_speed_10m_max" +
    "&forecast_days=" +
    FORECAST_DAYS +
    "&temperature_unit=" +
    temp +
    "&wind_speed_unit=" +
    wind +
    "&timezone=auto";
  const air =
    "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" +
    encodeURIComponent(loc.latitude) +
    "&longitude=" +
    encodeURIComponent(loc.longitude) +
    "&current=us_aqi&timezone=auto";
  return Promise.all([fetchJson(forecast), fetchJson(air)]).then(([forecastJson, airJson]) => ({
    loc,
    forecast: forecastJson,
    air: airJson,
  }));
}

function ForecastStrip({ daily, unit }) {
  const times = daily.time || [];
  const count = Math.min(STRIP_DAYS, times.length);
  if (!count) return null;
  const days = [];
  for (let i = 0; i < count; i += 1) {
    const hi = at(daily.temperature_2m_max, i);
    const lo = at(daily.temperature_2m_min, i);
    const code = at(daily.weather_code, i);
    days.push(
      <li key={times[i]}>
        <span className="forecast-day">
          {i === 0 ? "Today" : fmtDay(times[i], { weekday: "short" })}
        </span>
        <Icon code={weatherIcon(code)} />
        <span className="forecast-temps">
          <span className={tempTone(hi, unit) || undefined}>{fmtDeg(hi)}</span>
          <span className="forecast-low">{fmtDeg(lo)}</span>
        </span>
      </li>,
    );
  }
  return (
    <ul className="forecast-strip" aria-label={`${count}-day forecast`}>
      {days}
    </ul>
  );
}

function ForecastModal({ place, unit, aqi, onClose }) {
  const daily = (place.forecast && place.forecast.daily) || {};
  const times = daily.time || [];
  const name = place.loc.name || "Location";
  return (
    <Modal
      icon={ICO.weather}
      title={`${name} · ${FORECAST_DAYS}-day`}
      label={`${name} ${FORECAST_DAYS}-day forecast`}
      onClose={onClose}
    >
      <p className="facts">
        <Fact code={ICO.aci} text={`ACI ${aqi == null ? "—" : aqi}`} tone={aqiTone(aqi)} />
      </p>
      <ul className="forecast-days">
        {times.map((iso, i) => {
          const hi = at(daily.temperature_2m_max, i);
          const lo = at(daily.temperature_2m_min, i);
          const code = at(daily.weather_code, i);
          const precip = at(daily.precipitation_probability_max, i);
          const gust = at(daily.wind_speed_10m_max, i);
          return (
            <li key={iso}>
              <h3>
                {i === 0 ? "Today" : fmtDay(iso, { weekday: "long" })}
                <span className="forecast-date">
                  {fmtDay(iso, { month: "short", day: "numeric" })}
                </span>
              </h3>
              <p className="facts">
                <Fact code={weatherIcon(code)} text={weatherLabel(code)} />
                <Fact
                  code={ICO.thermometer}
                  text={`${fmtDeg(hi)} / ${fmtDeg(lo)}`}
                  tone={tempTone(hi, unit)}
                />
                <Fact code={ICO.rain} text={precip == null ? "—" : `${Math.round(precip)}%`} />
                <Fact code={ICO.wind} text={gust == null ? "—" : String(Math.round(gust))} />
              </p>
              <p className="facts">
                <Fact code={ICO.sunrise} text={fmtClock(at(daily.sunrise, i))} />
                <Fact code={ICO.sunset} text={fmtClock(at(daily.sunset, i))} />
              </p>
            </li>
          );
        })}
      </ul>
    </Modal>
  );
}

function Place({ place, unit, detail, showName }) {
  const cur = (place.forecast && place.forecast.current) || {};
  const daily = (place.forecast && place.forecast.daily) || {};
  const aqi = place.air && place.air.current ? place.air.current.us_aqi : null;
  const phase = moonPhase(daily.moon_phase && daily.moon_phase[0]);
  const [open, setOpen] = useState(false);
  const name = place.loc.name || "Location";
  return (
    <article className={detail === "short" ? "weather-place is-short" : "weather-place"}>
      <h3>
        {showName ? name : null}
        <button
          type="button"
          className="forecast-btn"
          onClick={() => setOpen(true)}
          aria-label={`Open ${FORECAST_DAYS}-day forecast for ${name}`}
        >
          <Icon code={ICO.calendar} />
          {FORECAST_DAYS}-day
        </button>
      </h3>
      <p className="facts">
        <Fact
          code={ICO.thermometer}
          text={`${Math.round(cur.temperature_2m)}°${unit}`}
          tone={tempTone(cur.temperature_2m, unit)}
        />
        <Fact code={weatherIcon(cur.weather_code)} text={weatherLabel(cur.weather_code)} />
        <Fact code={ICO.wind} text={String(Math.round(cur.wind_speed_10m))} />
        <Fact code={ICO.aci} text={`ACI ${aqi == null ? "—" : aqi}`} tone={aqiTone(aqi)} />
      </p>
      {detail === "long" ? (
        <>
          <p className="facts">
            <Fact code={ICO.sunrise} text={fmtClock(daily.sunrise && daily.sunrise[0])} />
            <Fact code={ICO.sunset} text={fmtClock(daily.sunset && daily.sunset[0])} />
          </p>
          <p className="facts">
            <Fact code={phase.code} text={phase.label} />
            <Fact code={ICO.moonrise} text={fmtClock(daily.moonrise && daily.moonrise[0])} />
            <Fact code={ICO.moonset} text={fmtClock(daily.moonset && daily.moonset[0])} />
          </p>
          <ForecastStrip daily={daily} unit={unit} />
        </>
      ) : null}
      {open ? (
        <ForecastModal place={place} unit={unit} aqi={aqi} onClose={() => setOpen(false)} />
      ) : null}
    </article>
  );
}

// variant "focus" is one location rendered in full detail, titled after the
// place. "combo" is every short-detail location, two to a line. Which config
// entry lands in which widget comes from its own detail field.
export default function Weather({ variant = "combo" }) {
  const weather = widget("weather");
  const locations = weather.locations || [];
  const valid = locations.filter((loc) => loc && loc.latitude != null && loc.longitude != null);
  const unit = tempUnit(weather);
  const focus = variant === "focus";
  const picked = focus
    ? valid.filter((loc) => placeDetail(loc) === "long").slice(0, 1)
    : valid.filter((loc) => placeDetail(loc) === "short");
  const title = focus && picked.length ? `${picked[0].name || "Location"} Weather` : "Weather";
  const [places, setPlaces] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!picked.length) return;
    let cancelled = false;
    Promise.all(picked.map((loc) => loadPlace(loc, unit)))
      .then((next) => {
        if (!cancelled) setPlaces(next);
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (!picked.length) {
    const want = focus ? "long" : "short";
    return (
      <Empty
        text={`set a location with detail = "${want}" in intranet/config/weather/config.nix`}
        title={title}
        code={ICO.weather}
      />
    );
  }
  if (failed) {
    return <Empty text="weather unavailable" title={title} code={ICO.weather} />;
  }
  if (!places) return <Heading title={title} code={ICO.weather} />;
  return (
    <>
      <Heading title={title} code={ICO.weather} />
      <div className="weather-places">
        {places.map((place) => (
          <Place
            key={place.loc.name || `${place.loc.latitude},${place.loc.longitude}`}
            place={place}
            unit={unit}
            detail={focus ? "long" : "short"}
            showName={!focus}
          />
        ))}
      </div>
    </>
  );
}
