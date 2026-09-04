pragma Singleton
import QtQuick
import Quickshell

// THE definition of which output is "main". Both the bar (shell.qml) and the
// lock screen (lock.qml) ask here; neither may re-derive it.
//
// Deliberately DETERMINISTIC: always the geometric middle of the desktop,
// never whichever output happens to have focus. Nick asked for this on
// 2026-09-03, reversing the focus preference PR #182 added: he wants to know
// without looking where the password box will be. On Tawa the answer is
// HDMI-A-1 -- the unrotated landscape panel at the exact midpoint, and the one
// his own hypr/monitors.conf calls "center (HDMI)" and gives workspace 1.
//
// Do not "restore" focus-following here. #182's rationale still reads as an
// argument for it, and that argument was considered and rejected: the power
// menu and sunset modal follow this too, by his choice.
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

	// Geometric middle of the desktop. Available immediately at startup --
	// Quickshell.screens is populated before Component.onCompleted, which is
	// why dropping the focus preference also removed a 250ms race the lock
	// screen previously had to guard against.
	function screen(): var {
		const screens = Quickshell.screens;
		const n = screens.length;
		if (n === 0)
			return null;
		if (n === 1)
			return screens[0];

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
