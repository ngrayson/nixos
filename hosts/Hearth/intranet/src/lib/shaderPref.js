export const SHADER_KEY = "hearth.shader";
export const SHADER_IDS = ["geometry", "7fyXRh", "ldc3z4", "ltXczj"];

export const SHADER_OPTIONS = [
  { id: "geometry", label: "Geometry" },
  { id: "7fyXRh", label: "Terrain" },
  { id: "ldc3z4", label: "PS2 menu" },
  { id: "ltXczj", label: "Plasma waves" },
];

export function readShaderPref() {
  try {
    const stored = String(localStorage.getItem(SHADER_KEY) || "").trim();
    if (SHADER_IDS.includes(stored)) return stored;
  } catch {
    /* private mode */
  }
  return "geometry";
}

export function writeShaderPref(value) {
  if (!SHADER_IDS.includes(value)) return;
  try {
    localStorage.setItem(SHADER_KEY, value);
  } catch {
    /* private mode */
  }
}
