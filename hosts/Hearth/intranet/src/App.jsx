import { lazy, Suspense, useEffect, useState } from "react";
import Modal from "./components/Modal.jsx";
import WidgetGrid from "./components/WidgetGrid.jsx";
import { ICO, Icon } from "./lib/icons.jsx";
import { readShaderPref, SHADER_OPTIONS, writeShaderPref } from "./lib/shaderPref.js";
import { TimeFormatProvider, useTimeFormat } from "./lib/timeFormat.js";

const Atmosphere = lazy(() => import("./visuals/Atmosphere.jsx"));

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

function SettingsModal({ shaderId, onShader, onClose }) {
  const { pref, setFormat } = useTimeFormat();
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
    </Modal>
  );
}

function Shell() {
  const [shaderId, setShaderId] = useState(readShaderPref);
  const [settingsOpen, setSettingsOpen] = useState(false);
  return (
    <>
      <AtmosphereGate shaderId={shaderId} />
      <main>
        <nav className="site-nav" aria-label="Hearth">
          <a href="/" className="site-nav-item" aria-current="page">
            <Icon code={ICO.home} />
            Home
          </a>
          <span className="site-nav-ctas">
            <button
              type="button"
              className="site-nav-item site-nav-cta site-nav-settings"
              aria-label="Settings"
              onClick={() => setSettingsOpen(true)}
            >
              <Icon code={ICO.cog} />
            </button>
            <a id="tv-jellyfin" className="site-nav-item site-nav-cta" href="https://tv.wizt.org">
              <Icon code={ICO.tv} />
              TV Jellyfin
            </a>
          </span>
        </nav>
        <WidgetGrid />
      </main>
      {settingsOpen ? (
        <SettingsModal
          shaderId={shaderId}
          onShader={setShaderId}
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
