import { lazy, Suspense, useEffect, useState } from "react";
import WidgetGrid from "./components/WidgetGrid.jsx";
import { ICO, Icon } from "./lib/icons.jsx";
import { readShaderPref, SHADER_OPTIONS, writeShaderPref } from "./lib/shaderPref.js";

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

export default function App() {
  const [shaderId, setShaderId] = useState(readShaderPref);
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
            <label className="shader-picker">
              <span className="shader-picker-label">Background</span>
              <select
                value={shaderId}
                onChange={(event) => {
                  const next = event.target.value;
                  writeShaderPref(next);
                  setShaderId(next);
                }}
              >
                {SHADER_OPTIONS.map((option) => (
                  <option key={option.id} value={option.id}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>
            <a id="tv-jellyfin" className="site-nav-item site-nav-cta" href="https://tv.wizt.org">
              <Icon code={ICO.tv} />
              TV Jellyfin
            </a>
          </span>
        </nav>
        <WidgetGrid />
      </main>
    </>
  );
}
