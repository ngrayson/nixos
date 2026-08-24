import { useEffect, useState } from "react";
import { widget } from "../lib/config.js";
import { Empty, Fact, Heading, ICO } from "../lib/icons.jsx";

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

function Place({ place, unit }) {
  const cur = (place.forecast && place.forecast.current) || {};
  const daily = (place.forecast && place.forecast.daily) || {};
  const aqi = place.air && place.air.current ? place.air.current.us_aqi : null;
  const phase = moonPhase(daily.moon_phase && daily.moon_phase[0]);
  return (
    <article className="weather-place">
      <h3>{place.loc.name || "Location"}</h3>
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
      {placeDetail(place.loc) === "long" ? (
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
        </>
      ) : null}
    </article>
  );
}

export default function Weather() {
  const weather = widget("weather");
  const locations = weather.locations || [];
  const valid = locations.filter((loc) => loc && loc.latitude != null && loc.longitude != null);
  const unit = tempUnit(weather);
  const [places, setPlaces] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!valid.length) return;
    let cancelled = false;
    Promise.all(valid.map((loc) => loadPlace(loc, unit)))
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

  if (!valid.length) {
    return (
      <Empty
        text="set locations in intranet/config/weather/config.nix"
        title="Weather"
        code={ICO.weather}
      />
    );
  }
  if (failed) {
    return <Empty text="weather unavailable" title="Weather" code={ICO.weather} />;
  }
  if (!places) return <Heading title="Weather" code={ICO.weather} />;
  return (
    <>
      <Heading title="Weather" code={ICO.weather} />
      {places.map((place) => (
        <Place key={place.loc.name || `${place.loc.latitude},${place.loc.longitude}`} place={place} unit={unit} />
      ))}
    </>
  );
}
