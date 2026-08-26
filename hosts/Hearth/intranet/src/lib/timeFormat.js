import { createContext, createElement, useCallback, useContext, useMemo, useState } from "react";

export const TIME_FORMATS = ["12h", "24h"];
export const TIME_FORMAT_KEY = "hearth.timeFormat";

const TimeFormatContext = createContext(null);

export function readTimeFormat() {
  try {
    const stored = String(localStorage.getItem(TIME_FORMAT_KEY) || "").trim().toLowerCase();
    if (TIME_FORMATS.includes(stored)) return stored;
  } catch {
    /* private mode */
  }
  return "12h";
}

export function writeTimeFormat(value) {
  if (!TIME_FORMATS.includes(value)) return;
  try {
    localStorage.setItem(TIME_FORMAT_KEY, value);
  } catch {
    /* private mode */
  }
}

export function formatTime(date, { hour12, seconds } = {}) {
  return date.toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
    ...(seconds ? { second: "2-digit" } : {}),
    hour12,
  });
}

export function TimeFormatProvider({ children }) {
  const [pref, setPref] = useState(readTimeFormat);
  const hour12 = pref !== "24h";
  const setFormat = useCallback((next) => {
    writeTimeFormat(next);
    setPref(next);
  }, []);
  const value = useMemo(() => ({ pref, hour12, setFormat }), [pref, hour12, setFormat]);
  return createElement(TimeFormatContext.Provider, { value }, children);
}

export function useTimeFormat() {
  const ctx = useContext(TimeFormatContext);
  if (!ctx) throw new Error("useTimeFormat requires TimeFormatProvider");
  return ctx;
}
