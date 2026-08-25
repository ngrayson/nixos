import { widget } from "./config.js";

export const MAP_PROVIDERS = ["waze", "google", "off"];
export const MAP_PROVIDER_KEY = "hearth.mapProvider";

export function mapsBrowserKey() {
  return String(window.hearthMapsKey || "").trim();
}

export function configuredMapProvider() {
  const value = String(widget("transit").mapProvider || "waze").trim().toLowerCase();
  return MAP_PROVIDERS.includes(value) ? value : "waze";
}

export function readMapProvider() {
  try {
    const stored = String(localStorage.getItem(MAP_PROVIDER_KEY) || "").trim().toLowerCase();
    if (MAP_PROVIDERS.includes(stored)) return stored;
  } catch {
    /* private mode */
  }
  return configuredMapProvider();
}

export function writeMapProvider(value) {
  if (!MAP_PROVIDERS.includes(value)) return;
  try {
    localStorage.setItem(MAP_PROVIDER_KEY, value);
  } catch {
    /* private mode */
  }
}
