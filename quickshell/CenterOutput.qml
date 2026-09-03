pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// THE definition of which output is "centre". Both the bar (shell.qml) and the
// lock screen (lock.qml) ask here; neither may re-derive it.
//
// Why one definition is a hard rule, not tidiness: `hyprctl monitors -j`
// reports width/height PRE-transform while `Quickshell.screens` reports them
// POST-transform, so a rotated panel is 2560 wide to one API and 1440 to the
// other. Two implementations disagree on exactly the machines that have
// rotated outputs -- Tawa has two -- and the way that failure surfaces is
// blanking the only monitor showing the password prompt. `hypr-dpms-side-off`
// therefore takes the keep-lit name as an argument instead of working it out.
Item {
	id: root
	visible: false
	width: 0
	height: 0

	// False for roughly the first 250ms of a NEW Quickshell instance, while
	// Hyprland.focusedMonitor is still null. During that window screen() does
	// not fail -- it silently returns the GEOMETRIC middle, which on a
	// multi-monitor desk is usually not where the user is. Measured on Tawa
	// 2026-09-03: a fresh instance reported centre=HDMI-A-1 at t=0 and
	// centre=DP-1 (correct, the focused output) from t=250ms onward.
	//
	// That gap did not matter while the only caller was the long-running bar,
	// which has been up for hours by the time anyone locks. It matters now
	// that the lock screen is its own short-lived instance: blanking every
	// other output based on the t=0 answer would darken the monitor the user
	// is actually sitting at and light one they are not. Callers about to act
	// irreversibly on the answer must wait for this.
	readonly property bool ready: Quickshell.screens.length <= 1 || Hyprland.focusedMonitor !== null

	// Prefers the monitor you are actually looking at, and falls back to the
	// geometric middle of the desktop when focus is unknown.
	function screen(): var {
		const screens = Quickshell.screens;
		const n = screens.length;
		if (n === 0)
			return null;
		if (n === 1)
			return screens[0];

		const focusedName = Hyprland.focusedMonitor?.name ?? "";
		if (focusedName) {
			for (let i = 0; i < n; ++i) {
				if (screens[i].name === focusedName)
					return screens[i];
			}
		}

		let minX = screens[0].x;
		let maxX = screens[0].x + screens[0].width;
		for (let i = 1; i < n; ++i) {
			const s = screens[i];
			minX = Math.min(minX, s.x);
			maxX = Math.max(maxX, s.x + s.width);
		}

		const mid = (minX + maxX) / 2;
		let best = screens[0];
		let bestDist = Math.abs(best.x + best.width / 2 - mid);
		for (let i = 1; i < n; ++i) {
			const s = screens[i];
			const d = Math.abs(s.x + s.width / 2 - mid);
			if (d < bestDist) {
				bestDist = d;
				best = s;
			}
		}
		return best;
	}

	// Empty string when unknown. hypr-dpms-side-off fails open on an empty or
	// unrecognised name (blanks nothing), so this is the safe thing to pass.
	function name(): string {
		return root.screen()?.name ?? "";
	}
}
