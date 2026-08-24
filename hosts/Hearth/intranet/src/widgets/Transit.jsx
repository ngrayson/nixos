import { widget } from "../lib/config.js";
import { Heading, ICO } from "../lib/icons.jsx";

function parseLatLng(query) {
  const m = String(query || "").match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (!m) return null;
  return { lat: m[1], lng: m[2] };
}

function mapSrc(transit) {
  const query = (transit.mapQuery || "").trim();
  const zoom = Number(transit.mapZoom || 10);
  const ll = parseLatLng(query);
  if (ll) {
    return (
      "https://embed.waze.com/iframe?zoom=" +
      encodeURIComponent(String(zoom)) +
      "&lat=" +
      encodeURIComponent(ll.lat) +
      "&lon=" +
      encodeURIComponent(ll.lng)
    );
  }
  if (!query) return "";
  return (
    "https://maps.google.com/maps?q=" +
    encodeURIComponent(query) +
    "&z=" +
    encodeURIComponent(String(zoom)) +
    "&output=embed"
  );
}

export default function Transit() {
  const src = mapSrc(widget("transit"));
  if (!src) return null;
  return (
    <>
      <Heading title="Map" code={ICO.map} />
      <iframe
        className="local-map"
        title="Local traffic map"
        loading="lazy"
        referrerPolicy="no-referrer-when-downgrade"
        src={src}
      />
    </>
  );
}
