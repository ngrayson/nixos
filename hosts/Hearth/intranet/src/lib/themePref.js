export const THEME_KEY = "hearth.theme";
// Ghost is what style.css's :root already paints, so defaulting to it means
// nobody's view changes until they actively pick something.
export const DEFAULT_THEME = "ghost";

// Generated from home/theme/schemes/*.nix by caddy.nix's intranetRoot
// derivation and served as /themes.js, so the palettes are never hand-copied
// into this app. It does not exist under `vite dev` (nothing generates it
// there) — every reader below tolerates an empty map, which leaves style.css's
// hardcoded fallback in place rather than blanking the page.
function themes() {
  if (typeof window === "undefined") return {};
  return window.hearthThemes || {};
}

function known(id) {
  return Object.prototype.hasOwnProperty.call(themes(), id);
}

// [{ id, label }] in the order Nix emitted, so a scheme added to
// home/theme/schemes/default.nix appears here with no change to this file.
export function themeOptions() {
  return Object.entries(themes()).map(([id, theme]) => ({
    id,
    label: theme.name || id,
  }));
}

export function readThemePref() {
  try {
    const stored = String(localStorage.getItem(THEME_KEY) || "").trim();
    if (known(stored)) return stored;
  } catch {
    /* private mode */
  }
  return DEFAULT_THEME;
}

export function writeThemePref(value) {
  if (!known(value)) return;
  try {
    localStorage.setItem(THEME_KEY, value);
  } catch {
    /* private mode */
  }
}

// The eight tokens style.css's :root declares; the rest of the stylesheet
// derives every other color from them via color-mix(), so overriding these
// recolors the whole page. Not a mechanical transform of the token names —
// onAccent is --on-accent — so the mapping is spelled out.
const CSS_VARS = {
  void: "--void",
  depth: "--depth",
  chrome: "--chrome",
  text: "--text",
  strong: "--strong",
  accent: "--accent",
  onAccent: "--on-accent",
  link: "--link",
};

// Scheme tokens are bare rrggbb (that is how the Nix modules consume them);
// CSS needs the leading #.
export function applyTheme(id) {
  const theme = themes()[id];
  if (!theme || !theme.tokens) return;
  const root = document.documentElement.style;
  for (const [token, cssVar] of Object.entries(CSS_VARS)) {
    const value = theme.tokens[token];
    if (value) root.setProperty(cssVar, `#${value}`);
  }
}
