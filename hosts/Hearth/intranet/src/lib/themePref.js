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

// Reading a CSS custom property is the fallback path only. Under `vite dev`
// there is no /themes.js, so themes() is empty and style.css's :root — seeded
// with Ghost — is the only palette that exists.
function cssVar(name, fallback) {
  if (typeof document === "undefined") return fallback;
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

// The three tokens the animated background needs, as `#rrggbb`.
//
// Deliberately sourced from the theme map rather than from the CSS variables
// applyTheme() writes: Atmosphere is a child of the component that calls
// applyTheme, and child effects run before parent effects, so a CSS-var read on
// a theme change would see the OLD palette for one commit. Reading the tokens
// directly has no such ordering hazard.
export function themeVisualColors(id) {
  const tokens = themes()[id]?.tokens;
  const pick = (token, fallback) =>
    tokens && tokens[token] ? `#${tokens[token]}` : cssVar(CSS_VARS[token], fallback);
  return {
    void: pick("void", "#122221"),
    accent: pick("accent", "#2fc7be"),
    strong: pick("strong", "#c5fbfc"),
  };
}

// `#rrggbb` to three sRGB floats in 0..1. Used for shader uniforms, which need
// numbers rather than a CSS string.
export function hexToRgb01(hex) {
  const n = Number.parseInt(String(hex).replace("#", ""), 16);
  if (!Number.isFinite(n)) return [0, 0, 0];
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}
