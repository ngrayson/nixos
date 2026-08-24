import { hearthLan } from "./lib/config.js";
import WidgetGrid from "./components/WidgetGrid.jsx";
import { ICO, Icon } from "./lib/icons.jsx";

export default function App() {
  const lan = hearthLan();
  const tvHref = lan ? `http://${lan}:8096` : "#";

  return (
    <main>
      <nav className="site-nav" aria-label="Hearth">
        <a href="/" className="site-nav-item" aria-current="page">
          <Icon code={ICO.home} />
          Home
        </a>
        <a id="tv-jellyfin" className="site-nav-item" href={tvHref}>
          <Icon code={ICO.tv} />
          TV Jellyfin
        </a>
      </nav>
      <WidgetGrid />
    </main>
  );
}
