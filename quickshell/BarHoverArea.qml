import QtQuick

// Hover/press chrome shared by everything clickable in the bar: a pointing-hand
// cursor, a highlight that deepens from hover to press, and a momentary
// press-squish.
//
// Lifted out of shell.qml's inline `component StatusPill`, which already had all
// three but was hardcoded to a 22x22 icon square and visible from exactly one
// place in one file. Registered in qmldir alongside Theme/PowerMenu/LockSurface
// so any bar widget — and the click-to-open features still to come — can wrap
// itself in it instead of hand-rolling the same three behaviours again.
//
// Owns no click semantics on purpose. Every widget's onClicked differs (toggle
// playback, switch workspace, open a menu, dispatch an exec), so callers keep
// their own handlers.
//
// Put the widget's content INSIDE this item, not beside it: the squish is a
// `scale` on this item, so a sibling would sit still while the highlight shrank
// underneath it.
MouseArea {
	id: root

	// Match whatever is being wrapped: 4 for the small square status icons, 6-8
	// for the wider rounded pills. Not baked in, because forcing one radius on
	// both is what kept this component tied to the status cluster.
	property real radius: 4

	// Optional tooltip hook, inert unless both are set. `tipHost` is a parameter
	// rather than a direct `barWindow` reference because that id only exists
	// inside shell.qml — a top-level component cannot see it.
	property string tipKind: ""
	property var tipHost: null

	hoverEnabled: true
	cursorShape: Qt.PointingHandCursor

	scale: pressed ? 0.94 : 1
	Behavior on scale {
		NumberAnimation {
			duration: 90
			easing.type: Easing.OutCubic
		}
	}

	onEntered: {
		if (root.tipHost && root.tipKind !== "")
			root.tipHost.armTip(root, root.tipKind);
	}
	onExited: {
		if (root.tipHost)
			root.tipHost.disarmTip();
	}

	Rectangle {
		z: -1
		anchors.fill: parent
		radius: root.radius
		color: {
			if (root.pressed)
				return Qt.alpha(Theme.selection, 0.28);
			if (root.containsMouse)
				return Qt.alpha(Theme.selection, 0.16);
			return "transparent";
		}
		Behavior on color {
			ColorAnimation {
				duration: 100
			}
		}
	}
}
