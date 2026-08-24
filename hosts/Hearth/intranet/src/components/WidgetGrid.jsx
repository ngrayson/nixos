import { useCallback, useMemo, useState } from "react";
import ReactGridLayout, { useContainerWidth, useResponsiveLayout } from "react-grid-layout";
import { widget } from "../lib/config.js";
import Calendar from "../widgets/Calendar.jsx";
import Buses from "../widgets/Buses.jsx";
import Gallery from "../widgets/Gallery.jsx";
import Health from "../widgets/Health.jsx";
import Transit from "../widgets/Transit.jsx";
import Weather from "../widgets/Weather.jsx";
import WidgetCard from "./WidgetCard.jsx";

const BREAKPOINTS = { lg: 1200, md: 996, sm: 768, xs: 480, xxs: 0 };
const COLS = { lg: 12, md: 10, sm: 6, xs: 4, xxs: 2 };

const H = {
  weather: 14,
  map: 10,
  buses: 10,
  health: 10,
  gallery: 10,
  calendar: 10,
};

function item(i, x, y, w, h) {
  return { i, x, y, w, h, static: true };
}

function visibleIds(showMap, showGallery) {
  const ids = ["weather"];
  if (showMap) ids.push("map");
  ids.push("buses", "health");
  if (showGallery) ids.push("gallery");
  ids.push("calendar");
  return ids;
}

function stack(ids, cols) {
  let y = 0;
  return ids.map((id) => {
    const row = item(id, 0, y, cols, H[id]);
    y += H[id];
    return row;
  });
}

function buildLayouts(showMap, showGallery) {
  const ids = visibleIds(showMap, showGallery);

  const lg = [];
  if (showMap) {
    lg.push(item("weather", 0, 0, 6, H.weather), item("map", 6, 0, 6, H.map));
  } else {
    lg.push(item("weather", 0, 0, 12, H.weather));
  }
  const lgY = Math.max(H.weather, showMap ? H.map : 0);
  lg.push(item("buses", 0, lgY, 4, H.buses), item("health", 4, lgY, 4, H.health), item("calendar", 8, lgY, 4, H.calendar));
  if (showGallery) lg.push(item("gallery", 0, lgY + H.buses, 6, H.gallery));

  const md = [];
  if (showMap) {
    md.push(item("weather", 0, 0, 5, H.weather), item("map", 5, 0, 5, H.map));
  } else {
    md.push(item("weather", 0, 0, 10, H.weather));
  }
  const mdY = Math.max(H.weather, showMap ? H.map : 0);
  md.push(item("buses", 0, mdY, 3, H.buses), item("health", 3, mdY, 3, H.health), item("calendar", 6, mdY, 4, H.calendar));
  if (showGallery) md.push(item("gallery", 0, mdY + H.buses, 6, H.gallery));

  return {
    lg,
    md,
    sm: stack(ids, 6),
    xs: stack(ids, 4),
    xxs: stack(ids, 2),
  };
}

export default function WidgetGrid() {
  const showMap = Boolean(String(widget("transit").mapQuery || "").trim());
  const [showGallery, setShowGallery] = useState(false);
  const onGalleryPresence = useCallback((present) => {
    setShowGallery(Boolean(present));
  }, []);

  const layouts = useMemo(() => buildLayouts(showMap, showGallery), [showMap, showGallery]);
  const { width, containerRef, mounted } = useContainerWidth();
  const { layout, cols } = useResponsiveLayout({
    width,
    breakpoints: BREAKPOINTS,
    cols: COLS,
    layouts,
  });

  return (
    <div ref={containerRef} className="widget-grid">
      {mounted ? (
        <ReactGridLayout
          width={width}
          layout={layout}
          gridConfig={{ cols, rowHeight: 36, margin: [12, 12] }}
          dragConfig={{ enabled: false }}
          resizeConfig={{ enabled: false }}
        >
          <div key="weather">
            <WidgetCard>
              <Weather />
            </WidgetCard>
          </div>
          {showMap ? (
            <div key="map">
              <WidgetCard>
                <Transit />
              </WidgetCard>
            </div>
          ) : null}
          <div key="buses">
            <WidgetCard>
              <Buses />
            </WidgetCard>
          </div>
          <div key="health">
            <WidgetCard>
              <Health />
            </WidgetCard>
          </div>
          {showGallery ? (
            <div key="gallery">
              <WidgetCard>
                <Gallery onPresence={onGalleryPresence} />
              </WidgetCard>
            </div>
          ) : null}
          <div key="calendar">
            <WidgetCard>
              <Calendar />
            </WidgetCard>
          </div>
        </ReactGridLayout>
      ) : null}
      {showGallery ? null : <Gallery onPresence={onGalleryPresence} />}
    </div>
  );
}
