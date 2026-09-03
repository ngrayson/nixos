export const ANIMATION_KEY = "hearth.animateBackground";

// Default on. Every viewer that is not the kiosk — phones, laptops — keeps
// today's behaviour until someone actively turns it off.
const DEFAULT_ANIMATE = true;

// Stored as "1"/"0" rather than JSON: the value is a single bit and this keeps
// a corrupt or foreign value falling back to the default instead of throwing.
export function readAnimationPref() {
  try {
    const stored = localStorage.getItem(ANIMATION_KEY);
    if (stored === "0") return false;
    if (stored === "1") return true;
  } catch {
    /* private mode */
  }
  return DEFAULT_ANIMATE;
}

export function writeAnimationPref(value) {
  try {
    localStorage.setItem(ANIMATION_KEY, value ? "1" : "0");
  } catch {
    /* private mode */
  }
}

// Whether this browser has ever decided. Go3's kiosk URL seeds the preference
// off on a first load only, so a later Settings change on the panel itself
// sticks instead of being re-forced by the query string on every reload.
export function animationPrefIsSet() {
  try {
    const stored = localStorage.getItem(ANIMATION_KEY);
    return stored === "0" || stored === "1";
  } catch {
    return false;
  }
}
