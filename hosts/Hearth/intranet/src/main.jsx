import { Component, StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App.jsx";
import "react-grid-layout/css/styles.css";
import "./style.css";

// React 18 unmounts the ENTIRE tree when a render or effect throws and nothing
// catches it. On the Go3 wall kiosk that is invisible and permanent: the page
// paints its background colour, every poll stops -- including useBuildReload,
// so a fixed deploy can never reach it -- and it stays that way until someone
// restarts the kiosk by hand. That happened on 2026-09-07 and cost ten hours
// of blank wall.
//
// The reload is what makes this useful on an appliance nobody is sitting at.
// 30s is long enough that a human viewer can read the line, and short enough
// that the wall heals itself before anyone walks past it.
class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { crashed: false };
  }

  static getDerivedStateFromError() {
    return { crashed: true };
  }

  componentDidCatch(error, info) {
    // Chromium is started with --enable-logging=stderr on the kiosk
    // (profiles/kiosk.nix), so this lands in `journalctl -u cage-tty1` as a
    // CONSOLE(...) line. It is the only record of what killed the page.
    console.error("dashboard crashed", error, info);
    this.reloadTimer = setTimeout(() => window.location.reload(), 30000);
  }

  componentWillUnmount() {
    clearTimeout(this.reloadTimer);
  }

  render() {
    if (this.state.crashed) {
      return (
        <div style={{ padding: "2rem", fontSize: "1.25rem", opacity: 0.8 }}>
          Dashboard hit an error, reloading…
        </div>
      );
    }
    return this.props.children;
  }
}

// Report-only, deliberately: these fire for things an ErrorBoundary never sees
// (a rejected fetch in a widget's effect, an async throw), and every widget
// already handles its own fetch failures. Reloading on them would put the wall
// into a reload loop the first time Hearth hiccups. The value is the log line
// that step 2's Chromium flags now capture.
window.addEventListener("error", (event) => {
  console.error("uncaught error", event.error ?? event.message);
});
window.addEventListener("unhandledrejection", (event) => {
  console.error("unhandled rejection", event.reason);
});

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
);
