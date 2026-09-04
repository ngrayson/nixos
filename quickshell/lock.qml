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
			quitFallback.start();
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
	// Safe to do at startup now that CenterOutput is deterministic geometry:
	// Quickshell.screens is populated before Component.onCompleted, so there
	// is no window where the answer is wrong. This used to be gated on a
	// CenterOutput.ready signal, because the focus-based answer took ~250ms to
	// settle and blanking early would darken the monitor the user was at.
	// Dropping focus-following removed the race along with the guard.
	Process {
		id: sideDpmsOff
	}

	Process {
		id: restoreSides
		// hypr-dpms-side-on, NOT hypr-dpms-all-on. Only the former is in
		// home.packages and therefore on PATH; hypr-dpms-all-on exists solely
		// as a store path behind `lib.getExe` in hypridle/Hearth config, so
		// calling it by name here silently failed and the side monitors never
		// came back after an unlock. Observed on Tawa 2026-09-03.
		//
		// side-on is the right script regardless: it deliberately restores
		// EVERY output rather than mirroring side-off's exclusion, because
		// refusing to blank is harmless while refusing to restore leaves a
		// dark desk.
		//
		// The `||` fallback is not paranoia: if the named script is ever
		// missing again, `hyprctl dispatch dpms on` still lights everything.
		// A dark desk is the worst outcome this file can produce.
		command: ["sh", "-c", "hypr-dpms-side-on || hyprctl dispatch dpms on"]
		onExited: lockRoot.finishQuit()
	}

	// Quitting must not depend on the restore succeeding, or even starting.
	// It failed exactly that way on 2026-09-03: the command named a script
	// that was not on PATH, the Process never spawned, onExited never fired,
	// and the locker stayed resident after unlock. That is worse than the dark
	// monitors it also caused -- `quickshell-lock` passes `-n`, so a resident
	// locker makes the NEXT lock a silent no-op and the machine stops locking.
	Timer {
		id: quitFallback
		interval: 2500
		repeat: false
		onTriggered: lockRoot.finishQuit()
	}

	// Safe to call more than once; whichever path gets here first wins.
	function finishQuit(): void {
		if (!lockRoot.quitting)
			return;
		Qt.quit();
	}

	function blankSides(): void {
		sideDpmsOff.command = ["hypr-dpms-side-off", CenterOutput.name()];
		sideDpmsOff.running = true;
	}

	Component.onCompleted: lockRoot.blankSides()
}
