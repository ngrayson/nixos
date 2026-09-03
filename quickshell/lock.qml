import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The lock screen, as its OWN Quickshell instance. Run it with
// `quickshell -d -n -p ~/.config/nixos/quickshell/lock.qml` (quickshell-lock
// does this); it takes the session lock at startup and exits on unlock.
//
// Separate from the bar on purpose. The lock used to live inside shell.qml,
// so anything that killed the bar killed the lock client -- and
// ext-session-lock-v1 deliberately keeps the session LOCKED when a client
// dies without unlock_and_destroy. On 2026-09-03 a routine `qs-quickshell-reload`
// on a locked Tawa left the machine unenterable that way. A reload of the bar
// must not be able to touch this process, which is also why
// qs-quickshell-reload matches its `-p` value exactly rather than by substring.
//
// Same directory as shell.qml so `qmldir` (Theme, LockContext, LockSurface,
// CenterOutput) and `pam/password.conf` are shared with no duplication --
// PamContext.configDirectory is relative to the config directory.
ShellRoot {
	id: lockRoot

	// Guards the exit path. Quitting while the compositor still holds the lock
	// would orphan it -- exactly the failure this file exists to prevent -- so
	// nothing calls Qt.quit() until the unlock has been handed over and the
	// side monitors are back.
	property bool quitting: false

	LockContext {
		id: lockContext

		onUnlocked: {
			lockContext.currentText = "";
			sessionLock.locked = false;
			lockRoot.quitting = true;
			// Restore every output, not just the ones we blanked. Refusing to
			// blank is harmless; refusing to restore leaves a dark desk.
			restoreSides.running = true;
		}
	}

	WlSessionLock {
		id: sessionLock
		// Unlike the bar's old copy, this starts locked: the instance exists
		// only to lock, and a window where it is up but not locked would be a
		// window where the screen is unguarded.
		locked: true

		WlSessionLockSurface {
			id: lockSurface

			// Chrome on EVERY output, not just the centre. The sides get
			// DPMS-blanked below, so a prompt on the centre alone means any
			// monitor woken by hand shows bare wallpaper with no way to type a
			// password -- observed on Tawa 2026-09-02, recovered only with
			// `hyprctl dispatch dpms on` from another machine.
			//
			// Cheap, because lockContext is one shared object: every surface
			// mirrors the same typed text and the same failure shake. Keyboard
			// focus still lands on exactly one surface, via `primary`.
			readonly property bool isPrimaryOutput: {
				const c = CenterOutput.screen();
				return c && screen && c.name === screen.name;
			}

			color: Theme.bg

			LockSurface {
				anchors.fill: parent
				context: lockContext
				preview: false
				showUi: true
				primary: lockSurface.isPrimaryOutput
			}
		}
	}

	// --- side blanking -------------------------------------------------
	// Deliberately NOT done at Component.onCompleted. Hyprland.focusedMonitor
	// is null for roughly the first 250ms of a new instance, and
	// CenterOutput.screen() does not fail during that window -- it silently
	// returns the GEOMETRIC middle. Measured on Tawa 2026-09-03: centre read
	// HDMI-A-1 at t=0 and DP-1 (the actually focused output) from t=250ms.
	// Blanking on the t=0 answer would darken the monitor the user is sitting
	// at and light one they are not.
	Process {
		id: sideDpmsOff
	}

	Process {
		id: restoreSides
		command: ["hypr-dpms-all-on"]
		// Only now is it safe to go: the lock has been released and the
		// screens are back. Exit code is ignored on purpose -- a failed
		// restore must not strand this process holding nothing.
		onExited: if (lockRoot.quitting) Qt.quit()
	}

	property bool sidesBlanked: false

	function blankSides(): void {
		if (lockRoot.sidesBlanked)
			return;
		lockRoot.sidesBlanked = true;
		sideDpmsOff.command = ["hypr-dpms-side-off", CenterOutput.name()];
		sideDpmsOff.running = true;
	}

	Connections {
		target: CenterOutput
		function onReadyChanged(): void {
			if (CenterOutput.ready)
				lockRoot.blankSides();
		}
	}

	// Bounded fallback: if focus never resolves (single-output machine, or
	// Hyprland not answering) blank anyway rather than leaving the sides lit
	// forever. CenterOutput.name() fails open -- an empty name blanks nothing.
	Timer {
		interval: 1500
		running: true
		repeat: false
		onTriggered: lockRoot.blankSides()
	}

	Component.onCompleted: {
		if (CenterOutput.ready)
			lockRoot.blankSides();
	}
}
