export const ANIMATION_KEY = "hearth.animateBackground";

// Three background animation modes:
//   always — live render (today's "On")
//   wake   — frozen at rest, but animates for a moment each time the Go3 panel
//            wakes from screen-off, then eases back to frozen
//   off    — frozen shader frame (PR #205)
export const ANIMATION_MODES = ["always", "wake", "off"];

// Default live. Every viewer that is not the kiosk — phones, laptops — keeps
// today's behaviour until someone actively changes it.
const DEFAULT_MODE = "always";

// The value used to be a single "1"/"0" bit. Migrate it so a viewer who set the
// old On/Off pref before the three-way mode existed keeps their choice: true
// (On) → "always", false (Off) → "off". A corrupt or foreign value falls back
// to the default rather than throwing.
function normalizeMode(stored) {
  if (stored === "always" || stored === "wake" || stored === "off") return stored;
  if (stored === "1") return "always";
  if (stored === "0") return "off";
  return null;
}

export function readAnimationMode() {
  try {
    return normalizeMode(localStorage.getItem(ANIMATION_KEY)) ?? DEFAULT_MODE;
  } catch {
    /* private mode */
  }
  return DEFAULT_MODE;
}

export function writeAnimationMode(mode) {
  try {
    localStorage.setItem(ANIMATION_KEY, ANIMATION_MODES.includes(mode) ? mode : DEFAULT_MODE);
  } catch {
    /* private mode */
  }
}

// Whether this browser has ever decided (in either the legacy or the mode
// encoding). Go3's kiosk URL seeds the preference on a first load only, so a
// later Settings change on the panel itself sticks instead of being re-forced
// by the query string on every reload.
export function animationModeIsSet() {
  try {
    return normalizeMode(localStorage.getItem(ANIMATION_KEY)) !== null;
  } catch {
    return false;
  }
}
