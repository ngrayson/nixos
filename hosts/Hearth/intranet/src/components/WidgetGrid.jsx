import { useCallback, useLayoutEffect, useMemo, useRef, useState } from "react";
import ReactGridLayout, { useContainerWidth, useResponsiveLayout } from "react-grid-layout";
import { widget } from "../lib/config.js";
import Calendar from "../widgets/Calendar.jsx";
import Buses from "../widgets/Buses.jsx";
import Gallery from "../widgets/Gallery.jsx";
import Health from "../widgets/Health.jsx";
import Clock from "../widgets/Clock.jsx";
import Transit from "../widgets/Transit.jsx";
import Weather from "../widgets/Weather.jsx";
import WidgetCard from "./WidgetCard.jsx";

const BREAKPOINTS = { lg: 1200, md: 996, sm: 768, xs: 480, xxs: 0 };
const COLS = { lg: 12, md: 10, sm: 6, xs: 4, xxs: 2 };
const ROW_HEIGHT = 36;
const MARGIN_Y = 12;

const H = {
  weather: 12,
  map: 14,
  buses: 14,
  health: 8,
  gallery: 8,
  calendar: 10,
};

const HUG = new Set(["clock", "weather", "buses", "health", "calendar"]);

function item(i, x, y, w, h) {
  return { i, x, y, w, h, static: true };
}

function pxToRows(px) {
  return Math.max(1, Math.ceil((px + MARGIN_Y) / (ROW_HEIGHT + MARGIN_Y)));
}

function visibleIds(showMap, showGallery) {
  const ids = ["clock", "weather"];
  if (showMap) ids.push("map");
  ids.push("buses", "health");
  if (showGallery) ids.push("gallery");
  ids.push("calendar");
  return ids;
}

function stack(ids, cols, heights) {
  let y = 0;
  return ids.map((id) => {
    const h = heights[id];
    const row = item(id, 0, y, cols, h);
    y += h;
    return row;
  });
}

function buildLayouts(showMap, showGallery, heights) {
  const ids = visibleIds(showMap, showGallery);
  const leftH = heights.clock + heights.weather;

  const lg = [];
  if (showMap) {
    lg.push(
      item("clock", 0, 0, 6, heights.clock),
      item("weather", 0, heights.clock, 6, heights.weather),
      item("map", 6, 0, 6, leftH),
    );
  } else {
    lg.push(item("clock", 0, 0, 12, heights.clock), item("weather", 0, heights.clock, 12, heights.weather));
  }
  const lgY = leftH;
  lg.push(
    item("buses", 0, lgY, 4, heights.buses),
    item("health", 4, lgY, 4, heights.health),
    item("calendar", 8, lgY, 4, heights.calendar),
  );
  if (showGallery) lg.push(item("gallery", 0, lgY + heights.buses, 6, heights.gallery));

  const md = [];
  if (showMap) {
    md.push(
      item("clock", 0, 0, 5, heights.clock),
      item("weather", 0, heights.clock, 5, heights.weather),
      item("map", 5, 0, 5, leftH),
    );
  } else {
    md.push(item("clock", 0, 0, 10, heights.clock), item("weather", 0, heights.clock, 10, heights.weather));
  }
  const mdY = leftH;
  md.push(
    item("buses", 0, mdY, 3, heights.buses),
    item("health", 3, mdY, 3, heights.health),
    item("calendar", 6, mdY, 4, heights.calendar),
  );
  if (showGallery) md.push(item("gallery", 0, mdY + heights.buses, 6, heights.gallery));

  return {
    lg,
    md,
    sm: stack(ids, 6, heights),
    xs: stack(ids, 4, heights),
    xxs: stack(ids, 2, heights),
  };
}

function HugCard({ id, onHeight, children }) {
  const cardRef = useRef(null);
  const measureRef = useRef(null);
  useLayoutEffect(() => {
    const inner = measureRef.current;
    const card = cardRef.current;
    if (!inner) return undefined;
    const report = () => {
      const style = card ? getComputedStyle(card) : null;
      const chrome = style
        ? parseFloat(style.paddingTop) +
          parseFloat(style.paddingBottom) +
          parseFloat(style.borderTopWidth) +
          parseFloat(style.borderBottomWidth)
        : 0;
      const width = (card || inner).getBoundingClientRect().width;
      const probe = inner.cloneNode(true);
      probe.style.cssText = [
        "position:absolute",
        "left:-99999px",
        "top:0",
        "visibility:hidden",
        "height:auto",
        "overflow:visible",
        `width:${Math.max(0, width)}px`,
        "pointer-events:none",
      ].join(";");
      document.body.appendChild(probe);
      const px = probe.scrollHeight + chrome;
      document.body.removeChild(probe);
      if (px < 16) return;
      onHeight(id, pxToRows(px));
    };
    const ro = new ResizeObserver(report);
    ro.observe(inner);
    report();
    return () => ro.disconnect();
  }, [id, onHeight]);
  return (
    <div className="widget-hug">
      <WidgetCard hug cardRef={cardRef}>
        <div ref={measureRef} className="widget-hug-measure">
          {children}
        </div>
      </WidgetCard>
    </div>
  );
}

export default function WidgetGrid() {
  const showMap = Boolean(String(widget("transit").mapQuery || "").trim());
  const [showGallery, setShowGallery] = useState(false);
  const [hugH, setHugH] = useState(() => {
    const next = {};
    for (const id of HUG) next[id] = 2;
    return next;
  });
  const onGalleryPresence = useCallback((present) => {
    setShowGallery(Boolean(present));
  }, []);
  const onHugHeight = useCallback((id, h) => {
    setHugH((prev) => (prev[id] === h ? prev : { ...prev, [id]: h }));
  }, []);

  const heights = useMemo(() => ({ ...H, ...hugH }), [hugH]);
  const layouts = useMemo(() => buildLayouts(showMap, showGallery, heights), [showMap, showGallery, heights]);
  const { width, containerRef, mounted } = useContainerWidth();
  const { layout, cols, setLayouts } = useResponsiveLayout({
    width,
    breakpoints: BREAKPOINTS,
    cols: COLS,
    layouts,
  });
  useLayoutEffect(() => {
    setLayouts(layouts);
  }, [layouts, setLayouts]);

  return (
    <div ref={containerRef} className="widget-grid">
      {mounted ? (
        <ReactGridLayout
          width={width}
          layout={layout}
          gridConfig={{ cols, rowHeight: ROW_HEIGHT, margin: [12, MARGIN_Y] }}
          dragConfig={{ enabled: false }}
          resizeConfig={{ enabled: false }}
        >
          <div key="clock">
            <HugCard id="clock" onHeight={onHugHeight}>
              <Clock />
            </HugCard>
          </div>
          <div key="weather">
            <HugCard id="weather" onHeight={onHugHeight}>
              <Weather />
            </HugCard>
          </div>
          {showMap ? (
            <div key="map">
              <WidgetCard fill>
                <Transit />
              </WidgetCard>
            </div>
          ) : null}
          <div key="buses">
            <HugCard id="buses" onHeight={onHugHeight}>
              <Buses />
            </HugCard>
          </div>
          <div key="health">
            <HugCard id="health" onHeight={onHugHeight}>
              <Health />
            </HugCard>
          </div>
          {showGallery ? (
            <div key="gallery">
              <WidgetCard>
                <Gallery onPresence={onGalleryPresence} />
              </WidgetCard>
            </div>
          ) : null}
          <div key="calendar">
            <HugCard id="calendar" onHeight={onHugHeight}>
              <Calendar />
            </HugCard>
          </div>
        </ReactGridLayout>
      ) : null}
      {showGallery ? null : <Gallery onPresence={onGalleryPresence} />}
    </div>
  );
}
