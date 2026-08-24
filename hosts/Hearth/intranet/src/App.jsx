import { hearthLan } from "./lib/config.js";
import Clock from "./widgets/Clock.jsx";
import Weather from "./widgets/Weather.jsx";
import Transit from "./widgets/Transit.jsx";
import Buses from "./widgets/Buses.jsx";
import Health from "./widgets/Health.jsx";
import Gallery from "./widgets/Gallery.jsx";
import Calendar from "./widgets/Calendar.jsx";

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
      <section id="weather">
        <Weather />
      </section>
      <section id="transit">
        <Transit />
        <Buses />
      </section>
      <section id="health">
        <Health />
      </section>
      <section id="gallery">
        <Gallery />
      </section>
      <section id="calendar">
        <Calendar />
      </section>
    </main>
  );
}
