import { lazy, Suspense, useEffect, useState } from "react";
import { hearthLan } from "./lib/config.js";
import WidgetGrid from "./components/WidgetGrid.jsx";
import { ICO, Icon } from "./lib/icons.jsx";

const Atmosphere = lazy(() => import("./visuals/Atmosphere.jsx"));

function AtmosphereGate() {
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
      <Atmosphere />
    </Suspense>
  );
}

export default function App() {
  const lan = hearthLan();
  const tvHref = lan ? `http://${lan}:8096` : "#";

  return (
    <>
      <AtmosphereGate />
      <main>
        <nav className="site-nav" aria-label="Hearth">
          <a href="/" className="site-nav-item" aria-current="page">
            <Icon code={ICO.home} />
            Home
          </a>
          <span className="site-nav-ctas">
            <a id="tv-jellyfin" className="site-nav-item site-nav-cta" href="https://tv.wizt.org">
              <Icon code={ICO.tv} />
              TV Jellyfin
            </a>
            {lan ? (
              <a className="site-nav-item site-nav-cta" href={tvHref}>
                <Icon code={ICO.tv} />
                TV (LAN)
              </a>
            ) : null}
          </span>
        </nav>
        <WidgetGrid />
      </main>
    </>
  );
}
