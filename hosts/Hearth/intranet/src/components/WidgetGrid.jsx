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
  weatherCombo: 6,
  map: 10,
  buses: 14,
  health: 8,
  gallery: 8,
  calendar: 10,
  clock: 2.6,
};

const HUG = new Set(["weather", "weatherCombo", "buses", "health", "calendar"]);

function item(i, x, y, w, h) {
  return { i, x, y, w, h, static: true };
}

// Quarter-row granularity so a card is not padded out to the next whole 48px
// row, while staying coarse enough not to re-fire on sub-pixel noise.
function pxToRows(px) {
  const rows = (px + MARGIN_Y) / (ROW_HEIGHT + MARGIN_Y);
  return Math.max(1, Math.ceil(rows * 4) / 4);
}

// Each widget belongs to a column and stacks under the one above it. Columns
// are independent, so a tall widget never pushes its neighbours down.
function columnIds(showMap, showGallery) {
  const middle = ["calendar", "health"];
  if (showGallery) middle.push("gallery");
  const right = [];
  if (showMap) right.push("map");
  right.push("buses");
  return [["clock", "weather", "weatherCombo"], middle, right];
}

function column(ids, x, w, heights) {
  let y = 0;
  return ids.map((id) => {
    const cell = item(id, x, y, w, heights[id]);
    y += heights[id];
    return cell;
  });
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
  const [left, middle, right] = columnIds(showMap, showGallery);
  const ids = [...left, ...middle, ...right];

  const lg = [
    ...column(left, 0, 4, heights),
    ...column(middle, 4, 4, heights),
    ...column(right, 8, 4, heights),
  ];

  const md = [
    ...column(left, 0, 4, heights),
    ...column(middle, 4, 3, heights),
    ...column(right, 7, 3, heights),
  ];

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
      if (!card) return;
      const style = getComputedStyle(card);
      const border = parseFloat(style.borderTopWidth) + parseFloat(style.borderBottomWidth);
      // The clone must sit under a .widget-card ancestor. Measured loose in the
      // body every card-scoped rule stops applying -- the heading alone falls
      // back to the UA's h2 size and margins -- and the probe reads ~50px tall
      // than the real content. Copying the card's classes and outer width
      // reproduces its padding, so the content box matches too.
      const host = document.createElement("div");
      host.className = card.className;
      host.style.cssText = [
        "position:absolute",
        "left:-99999px",
        "top:0",
        "visibility:hidden",
        "height:auto",
        "overflow:visible",
        `width:${Math.max(0, card.getBoundingClientRect().width)}px`,
        "pointer-events:none",
      ].join(";");
      host.appendChild(inner.cloneNode(true));
      document.body.appendChild(host);
      const px = host.scrollHeight + border;
      document.body.removeChild(host);
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
            <WidgetCard>
              <Clock />
            </WidgetCard>
          </div>
          <div key="weather">
            <HugCard id="weather" onHeight={onHugHeight}>
              <Weather variant="focus" />
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
          <div key="weatherCombo">
            <HugCard id="weatherCombo" onHeight={onHugHeight}>
              <Weather variant="combo" />
            </HugCard>
          </div>
        </ReactGridLayout>
      ) : null}
      {showGallery ? null : <Gallery onPresence={onGalleryPresence} />}
    </div>
  );
}
