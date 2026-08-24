import { hearthLan } from "./lib/config.js";
import WidgetGrid from "./components/WidgetGrid.jsx";
import Clock from "./widgets/Clock.jsx";

export default function App() {
  const lan = hearthLan();
  const tvHref = lan ? `http://${lan}:8096` : "#";

  return (
    <main>
      <header>
        <h1>Hearth</h1>
        <Clock />
      </header>
      <p>
        <a id="tv-jellyfin" className="cta" href={tvHref}>
          TV Jellyfin
        </a>
      </p>
      <WidgetGrid />
    </main>
  );
}
