import { lazy, Suspense, useCallback, useEffect, useRef, useState } from "react";
import Modal from "./components/Modal.jsx";
import WidgetGrid from "./components/WidgetGrid.jsx";
import { Fact, ICO, Icon } from "./lib/icons.jsx";
import { readShaderPref, SHADER_OPTIONS, writeShaderPref } from "./lib/shaderPref.js";
import {
  applyTheme,
  readThemePref,
  themeOptions,
  writeThemePref,
} from "./lib/themePref.js";
import { TimeFormatProvider, useTimeFormat } from "./lib/timeFormat.js";

const Atmosphere = lazy(() => import("./visuals/Atmosphere.jsx"));

// Holding the Home nav item opens this in a new tab. Deliberately unhinted:
// no tooltip, no icon change, no data attribute naming it, no CSS affordance
// — the dashboard has to look untouched to anyone who is not holding the
// button down. Home is `href="/"` and already `aria-current="page"`, so a
// plain click is inert today and the gesture displaces nothing.
const HELD_HOME_URL = "https://technowizard.myles.usbx.me/sonarr2/";
// Long enough that a normal tap never reaches it, short enough that a
// deliberate hold does not feel broken.
const LONG_PRESS_MS = 600;
const MOVE_TOLERANCE_PX = 10;

// The kiosk loads this page once in cage + Chromium and never navigates away,
// so a hearth-deploy that ships new dashboard code never reaches it — the tab
// keeps running the old JS in memory indefinitely. build-id.txt changes only
// when the served content actually changes, so poll it and reload on a
// mismatch. Generic on purpose: any long-lived viewer benefits, and nothing
// here knows Go3 exists.
const BUILD_POLL_MS = 120000;

function useBuildReload() {
  useEffect(() => {
    let cancelled = false;
    // The id captured at load. Held in the effect rather than in state: a
    // change to it must trigger a reload, never a re-render.
    let loaded = null;

    function poll() {
      // no-store so an intermediate cache cannot hide a new build.
      fetch("/build-id.txt", { cache: "no-store" })
        .then((res) => {
          if (!res.ok) throw new Error(`build-id ${res.status}`);
          return res.text();
        })
        .then((text) => {
          const id = text.trim();
          if (cancelled || !id) return;
          if (loaded === null) {
            loaded = id;
            return;
          }
          if (id !== loaded) window.location.reload();
        })
        // Fail quiet. A network hiccup, or Caddy restarting mid-deploy, must
        // never reload the page or surface an error for a background poll —
        // only an actual mismatch reloads.
        .catch(() => {});
    }

    poll();
    const timer = setInterval(poll, BUILD_POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, []);
}

function AtmosphereGate({ shaderId }) {
  const [mount, setMount] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setMount(!mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);
  if (!mount) return null;
  return (
    <Suspense fallback={null}>
      <Atmosphere shaderId={shaderId} />
    </Suspense>
  );
}

function SettingsModal({ shaderId, onShader, themeId, onTheme, onClose }) {
  const { pref, setFormat } = useTimeFormat();
  // Empty under `vite dev`, where /themes.js is not generated — no point
  // showing a picker with nothing in it.
  const themes = themeOptions();
  return (
    <Modal icon={ICO.cog} title="Settings" onClose={onClose}>
      <div className="settings-row">
        <span className="settings-label">Time</span>
        <div className="map-provider" role="radiogroup" aria-label="Time format">
          {[
            ["12h", "12-hour"],
            ["24h", "24-hour"],
          ].map(([id, label]) => (
            <button
              key={id}
              type="button"
              role="radio"
              aria-checked={pref === id}
              className={pref === id ? "map-provider-btn is-active" : "map-provider-btn"}
              onClick={() => setFormat(id)}
            >
              {label}
            </button>
          ))}
        </div>
      </div>
      <div className="settings-row">
        <label className="shader-picker">
          <span className="shader-picker-label">Background</span>
          <select
            value={shaderId}
            onChange={(event) => {
              const next = event.target.value;
              writeShaderPref(next);
              onShader(next);
            }}
          >
            {SHADER_OPTIONS.map((option) => (
              <option key={option.id} value={option.id}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
      </div>
      {themes.length > 0 ? (
        <div className="settings-row">
          <label className="shader-picker">
            <span className="shader-picker-label">Theme</span>
            <select
              value={themeId}
              onChange={(event) => {
                const next = event.target.value;
                writeThemePref(next);
                onTheme(next);
              }}
            >
              {themes.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      ) : null}
    </Modal>
  );
}

// Go3's kiosk URL carries ?hideJellyfin=1 (profiles/kiosk.nix). Read once at
// module scope: the query string cannot change without a reload, so there is
// nothing to re-evaluate and no reason to make it state.
const params =
  typeof window === "undefined" ? null : new URLSearchParams(window.location.search);
const hideJellyfin = params?.get("hideJellyfin") === "1";
// Go3's kiosk URL sets this too. Independent of hideJellyfin: both ride the
// same URL and neither implies the other.
const showSystemStats = params?.get("showSystemStats") === "1";

// Go3 serves its own CPU/RAM/battery/Wi-Fi/temperature on loopback, because a
// web page has no API for OS-level stats and this page comes from Hearth.
// Same machine, different origin -- hence the CSP entry in caddy.nix.
const STATS_URL = "http://127.0.0.1:18090/stats.json";
const STATS_POLL_MS = 5000;

function KioskStats() {
  const [stats, setStats] = useState(null);

  useEffect(() => {
    let cancelled = false;
    function poll() {
      fetch(STATS_URL)
        .then((res) => (res.ok ? res.json() : Promise.reject(new Error("stats"))))
        .then((data) => {
          if (!cancelled) setStats(data);
        })
        // Anything at all -- service down, wrong host, CSP -- hides the row.
        // A Go3-only extra must never be able to break the shared dashboard.
        .catch(() => {
          if (!cancelled) setStats(null);
        });
    }
    poll();
    const id = setInterval(poll, STATS_POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (!stats) return null;

  const charging = stats.battery_status === "Charging";
  return (
    <span className="site-nav-stats">
      {stats.cpu_pct != null ? <Fact code={ICO.cpu} text={`${stats.cpu_pct}%`} /> : null}
      {stats.mem_pct != null ? <Fact code={ICO.memory} text={`${stats.mem_pct}%`} /> : null}
      {stats.battery_pct != null ? (
        <Fact
          code={charging ? ICO.battery : ICO.batteryOff}
          text={`${stats.battery_pct}%`}
        />
      ) : null}
      {stats.wifi_signal != null ? <Fact code={ICO.wifi} text={`${stats.wifi_signal}%`} /> : null}
      {stats.cpu_temp_c != null ? <Fact code={ICO.temp} text={`${stats.cpu_temp_c}°C`} /> : null}
    </span>
  );
}

function Shell() {
  const [shaderId, setShaderId] = useState(readShaderPref);
  const [themeId, setThemeId] = useState(readThemePref);
  const [settingsOpen, setSettingsOpen] = useState(false);
  useBuildReload();
  // Repaints the eight CSS custom properties style.css declares in :root —
  // on mount for the stored preference, and again on every change.
  useEffect(() => {
    applyTheme(themeId);
  }, [themeId]);
  const pressTimer = useRef(null);
  const pressOrigin = useRef(null);
  const longPressFired = useRef(false);

  const cancelPress = useCallback(() => {
    if (pressTimer.current !== null) {
      clearTimeout(pressTimer.current);
      pressTimer.current = null;
    }
    pressOrigin.current = null;
  }, []);

  const startPress = useCallback((event) => {
    // Primary button only; a right-click is not a long press.
    if (event.button !== undefined && event.button !== 0) return;
    longPressFired.current = false;
    pressOrigin.current = { x: event.clientX, y: event.clientY };
    pressTimer.current = setTimeout(() => {
      pressTimer.current = null;
      longPressFired.current = true;
      window.open(HELD_HOME_URL, "_blank", "noopener,noreferrer");
    }, LONG_PRESS_MS);
  }, []);

  const trackPress = useCallback(
    (event) => {
      const origin = pressOrigin.current;
      if (!origin) return;
      // A scroll or drag that happens to start on Home is not a held press.
      if (
        Math.abs(event.clientX - origin.x) > MOVE_TOLERANCE_PX ||
        Math.abs(event.clientY - origin.y) > MOVE_TOLERANCE_PX
      ) {
        cancelPress();
      }
    },
    [cancelPress],
  );

  // A pending timer must not outlive the component.
  useEffect(() => cancelPress, [cancelPress]);

  return (
    <>
      <AtmosphereGate shaderId={shaderId} />
      <main>
        <nav className="site-nav" aria-label="Hearth">
          <a
            href="/"
            className="site-nav-item"
            aria-current="page"
            onPointerDown={startPress}
            onPointerMove={trackPress}
            onPointerUp={cancelPress}
            onPointerLeave={cancelPress}
            onPointerCancel={cancelPress}
            onClick={(event) => {
              // Swallow the click a completed hold leaves behind so the
              // gesture never also navigates.
              if (longPressFired.current) {
                longPressFired.current = false;
                event.preventDefault();
              }
            }}
            onContextMenu={(event) => {
              // On touch, a hold otherwise raises the context menu, which
              // would both interrupt the gesture and hint that it exists.
              event.preventDefault();
            }}
          >
            <Icon code={ICO.home} />
            Home
          </a>
          {showSystemStats ? <KioskStats /> : null}
          <span className="site-nav-ctas">
            <button
              type="button"
              className="site-nav-item site-nav-cta site-nav-settings"
              aria-label="Settings"
              onClick={() => setSettingsOpen(true)}
            >
              <Icon code={ICO.cog} />
            </button>
            {hideJellyfin ? null : (
              <a id="tv-jellyfin" className="site-nav-item site-nav-cta" href="https://tv.wizt.org">
                <Icon code={ICO.tv} />
                TV Jellyfin
              </a>
            )}
          </span>
        </nav>
        <WidgetGrid />
      </main>
      {settingsOpen ? (
        <SettingsModal
          shaderId={shaderId}
          onShader={setShaderId}
          themeId={themeId}
          onTheme={setThemeId}
          onClose={() => setSettingsOpen(false)}
        />
      ) : null}
    </>
  );
}

export default function App() {
  return (
    <TimeFormatProvider>
      <Shell />
    </TimeFormatProvider>
  );
}
