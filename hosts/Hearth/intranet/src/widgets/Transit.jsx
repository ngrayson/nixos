import { useEffect, useRef, useState } from "react";
import Modal from "../components/Modal.jsx";
import { widget } from "../lib/config.js";
import { Heading, ICO } from "../lib/icons.jsx";
import { mapsBrowserKey, readMapProvider, writeMapProvider } from "../lib/mapProvider.js";

function parseLatLng(query) {
  const m = String(query || "").match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (!m) return null;
  return { lat: m[1], lng: m[2] };
}

function wazeSrc(transit) {
  const query = (transit.mapQuery || "").trim();
  const zoom = Number(transit.mapZoom || 10);
  const ll = parseLatLng(query);
  if (ll) {
    // Official iframe params are lat, lon, zoom, pin, desc only. Jam tiles
    // come from Waze livemap georss, which 403s (recaptcha / third-party
    // cookies) as of 2026-08. Leave the embed as an option; Google mode is
    // the traffic layer. Do not put Waze chrome on the Google map.
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

// Under loading=async the maps/api/js response is only a stub that injects
// main.js later, so the script's own load event fires before
// google.maps.importLibrary exists. Wait for the API's callback, not load.
const MAPS_CALLBACK = "hearthGoogleMapsReady";
const MAPS_TIMEOUT_MS = 20000;
let mapsReady = null;

function loadGoogleMaps(key) {
  if (window.google?.maps?.importLibrary) return Promise.resolve();
  if (mapsReady) return mapsReady;
  mapsReady = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    const fail = (message) => {
      script.remove();
      // Let a later mount retry rather than latching the failure forever.
      mapsReady = null;
      reject(new Error(message));
    };
    const timer = setTimeout(() => fail("google maps callback timed out"), MAPS_TIMEOUT_MS);
    window[MAPS_CALLBACK] = () => {
      clearTimeout(timer);
      resolve();
    };
    script.id = "hearth-google-maps";
    script.src =
      "https://maps.googleapis.com/maps/api/js?key=" +
      encodeURIComponent(key) +
      "&v=weekly&loading=async&callback=" +
      MAPS_CALLBACK;
    script.async = true;
    script.addEventListener(
      "error",
      () => {
        clearTimeout(timer);
        fail("google maps script failed to load");
      },
      { once: true },
    );
    document.head.appendChild(script);
  });
  return mapsReady;
}

function GoogleTrafficMap({ lat, lng, zoom, interactive = false }) {
  const ref = useRef(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const el = ref.current;
    const key = mapsBrowserKey();
    if (!el || !key) return undefined;
    let cancelled = false;
    (async () => {
      try {
        await loadGoogleMaps(key);
        if (cancelled || !ref.current) return;
        const { Map } = await window.google.maps.importLibrary("maps");
        if (cancelled || !ref.current) return;
        const map = new Map(ref.current, {
          center: { lat: Number(lat), lng: Number(lng) },
          zoom: Number(zoom) || 10,
          disableDefaultUI: true,
          mapTypeControl: false,
          streetViewControl: false,
          fullscreenControl: false,
          clickableIcons: false,
          gestureHandling: interactive ? "greedy" : "none",
          colorScheme: "DARK",
        });
        const traffic = new window.google.maps.TrafficLayer();
        traffic.setMap(map);
      } catch (err) {
        if (!cancelled) setFailed(true);
        console.error("google map failed", err);
      }
    })();
    return () => {
      cancelled = true;
      if (el) el.replaceChildren();
    };
  }, [lat, lng, zoom, interactive]);

  if (failed) return <p className="empty">Google map failed to load.</p>;
  return <div ref={ref} className="local-map local-map-google" role="img" aria-label="Local traffic map" />;
}

function MapOpenHit({ onOpen }) {
  const origin = useRef(null);
  return (
    <button
      type="button"
      className="map-open"
      aria-label="Open fullscreen map"
      onPointerDown={(event) => {
        origin.current = { x: event.clientX, y: event.clientY };
      }}
      onPointerUp={(event) => {
        const start = origin.current;
        origin.current = null;
        if (!start) return;
        const dx = event.clientX - start.x;
        const dy = event.clientY - start.y;
        if (dx * dx + dy * dy > 100) return;
        onOpen();
      }}
    />
  );
}

function ProviderToggle({ value, onChange }) {
  return (
    <div className="map-provider" role="radiogroup" aria-label="Map provider">
      {[
        ["waze", "Waze"],
        ["google", "Google"],
        ["off", "Off"],
      ].map(([id, label]) => (
        <button
          key={id}
          type="button"
          role="radio"
          aria-checked={value === id}
          className={value === id ? "map-provider-btn is-active" : "map-provider-btn"}
          onClick={() => onChange(id)}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

function WazeFrame({ src, title = "Local traffic map" }) {
  return (
    <iframe
      className="local-map local-map-waze"
      title={title}
      loading="lazy"
      referrerPolicy="no-referrer-when-downgrade"
      src={src}
    />
  );
}

export default function Transit() {
  const transit = widget("transit");
  const [provider, setProvider] = useState(readMapProvider);
  const [open, setOpen] = useState(false);
  const query = (transit.mapQuery || "").trim();
  const ll = parseLatLng(query);
  const zoom = Number(transit.mapZoom || 10);
  const key = mapsBrowserKey();
  const waze = wazeSrc(transit);

  const onProvider = (next) => {
    writeMapProvider(next);
    setProvider(next);
  };

  let preview = null;
  if (provider === "off") {
    preview = <p className="empty">Map hidden. Pick Waze or Google to show it.</p>;
  } else if (provider === "google") {
    if (!ll) preview = <p className="empty">Set mapQuery to lat,lon for Google traffic.</p>;
    else if (!key) preview = <p className="empty">Google Maps key missing.</p>;
    else {
      preview = (
        <div className="map-chrome map-chrome-preview">
          {open ? <div className="local-map" aria-hidden="true" /> : (
            <GoogleTrafficMap lat={ll.lat} lng={ll.lng} zoom={zoom} />
          )}
          <MapOpenHit onOpen={() => setOpen(true)} />
        </div>
      );
    }
  } else {
    if (!waze) return null;
    preview = (
      <div className="map-chrome map-chrome-preview">
        {open ? <div className="local-map" aria-hidden="true" /> : <WazeFrame src={waze} />}
        <MapOpenHit onOpen={() => setOpen(true)} />
      </div>
    );
  }

  if (provider === "waze" && !waze && !query) return null;

  let modalMap = null;
  if (open && provider === "google" && ll && key) {
    modalMap = (
      <div className="map-chrome">
        <GoogleTrafficMap lat={ll.lat} lng={ll.lng} zoom={zoom} interactive />
      </div>
    );
  } else if (open && provider === "waze" && waze) {
    modalMap = (
      <div className="map-chrome">
        <WazeFrame src={waze} title="Fullscreen traffic map" />
      </div>
    );
  }

  return (
    <>
      <div className="map-head">
        <Heading title="Map" code={ICO.map} />
        <ProviderToggle value={provider} onChange={onProvider} />
      </div>
      {preview}
      {modalMap ? (
        <Modal size="wide" icon={ICO.map} title="Map" onClose={() => setOpen(false)}>
          {modalMap}
        </Modal>
      ) : null}
    </>
  );
}
