import QtQuick

QtObject {
	readonly property color barBg: "#{{background | strip}}"
	readonly property color accent: "#{{color4 | strip}}"
	readonly property color muted: "#{{color8 | strip}}"
	readonly property color text: "#{{foreground | strip}}"
	readonly property color onAccent: "#{{background | strip}}"
	readonly property color error: "#{{color5 | strip}}"
}
