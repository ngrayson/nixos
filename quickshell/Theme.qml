pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Palette from ~/.config/quickshell/theme.json (written by home/theme).
// Defaults match Izar so the bar/lock still render before the first switch.
Item {
	id: root
	visible: false
	width: 0
	height: 0

	readonly property string name: pal.name
	readonly property string bg: pal.bg
	readonly property string depth: pal.depth
	readonly property string chrome: pal.chrome
	readonly property string surface: pal.surface
	readonly property string border: pal.border
	readonly property string muted: pal.muted
	readonly property string text: pal.text
	readonly property string strong: pal.strong
	readonly property string bright: pal.bright
	readonly property string accent: pal.accent
	readonly property string selection: pal.selection
	readonly property string link: pal.link
	readonly property string visited: pal.visited
	readonly property string sage: pal.sage
	readonly property string mauve: pal.mauve
	readonly property string error: pal.err
	readonly property string ink: pal.ink
	readonly property string wallpaper: pal.wallpaper

	FileView {
		path: `${Quickshell.env("HOME")}/.config/quickshell/theme.json`
		watchChanges: true
		onFileChanged: reload()

		JsonAdapter {
			id: pal
			property string name: "Izar"
			property string bg: "#010212"
			property string depth: "#0B0A1C"
			property string chrome: "#202661"
			property string surface: "#302947"
			property string border: "#405495"
			property string muted: "#756B94"
			property string text: "#D7CADC"
			property string strong: "#D7CADC"
			property string bright: "#DCF5E1"
			property string accent: "#6ABAB5"
			property string selection: "#6ABAB5"
			property string link: "#6ABAB5"
			property string visited: "#A481CC"
			property string sage: "#8CCCA4"
			property string mauve: "#A481CC"
			property string err: "#A481CC"
			property string ink: "#010212"
			property string wallpaper: ""
		}
	}
}
