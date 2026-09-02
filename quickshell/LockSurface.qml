import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// SDDM-like lock chrome on login-bg.png. Shared by WlSessionLock and the Esc-dismissable preview overlay.
Item {
	id: root

	required property LockContext context
	property bool preview: false
	property bool showUi: true
	// Split out of showUi deliberately. showUi is "draw the chrome", primary is
	// "take the keys". The real lock now draws a prompt on every output, but
	// only one surface may forceActiveFocus() — under ext-session-lock the
	// compositor routes input, and surfaces fighting over focus is the failure
	// mode that split buys us out of. LockContext is shared, so the non-primary
	// prompts still mirror the typed text and the failure shake.
	property bool primary: true

	readonly property color voidColor: Theme.bg
	readonly property color depthColor: Theme.depth
	readonly property color textColor: Theme.text
	readonly property color mutedColor: Theme.muted
	readonly property color accentColor: Theme.accent
	readonly property color errorColor: Theme.error
	readonly property color surfaceSolid: Theme.surface
	readonly property color surfaceColor: Qt.rgba(depthColor.r, depthColor.g, depthColor.b, 0.8)

	readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user"
	readonly property string homeDir: Quickshell.env("HOME") || ""
	readonly property string wallpaperPath: {
		const w = Theme.wallpaper;
		if (w && w.length > 0)
			return w.startsWith("file:") ? w : ("file://" + w);
		return `file://${homeDir}/.config/nixos/login-bg.png`;
	}

	readonly property var battery: UPower.displayDevice
	readonly property bool batteryPresent: battery?.isLaptopBattery ?? false
	readonly property int batteryPercent: Math.round((battery?.percentage ?? 0) * 100)
	readonly property bool batteryCharging: battery?.state === UPowerDeviceState.Charging

	signal dismissRequested()

	property bool uiVisible: true
	property bool capsOn: false
	property int faceTry: 0
	property var now: new Date()

	function pokeUi(): void {
		uiVisible = true;
		if (passwordBox.text.length === 0)
			fadeTimer.restart();
		else
			fadeTimer.stop();
	}

	function handleKey(event: var): void {
		pokeUi();
		if (event.key === Qt.Key_CapsLock)
			capsOn = !capsOn;
		if (root.preview && event.key === Qt.Key_Escape) {
			root.dismissRequested();
			event.accepted = true;
		}
	}

	function requestPower(kind: string): void {
		if (root.preview)
			return;
		if (powerProc.running)
			powerProc.running = false;
		if (kind === "sleep")
			powerProc.command = ["systemctl", "suspend"];
		else if (kind === "reboot")
			powerProc.command = ["systemctl", "reboot"];
		else if (kind === "poweroff")
			powerProc.command = ["systemctl", "poweroff"];
		else
			return;
		powerProc.running = true;
	}

	function batteryGlyph(): string {
		if (batteryCharging)
			return String.fromCodePoint(0xF0084);
		if (batteryPercent >= 95)
			return String.fromCodePoint(0xF0079);
		if (batteryPercent <= 5)
			return String.fromCodePoint(0xF008E);
		return String.fromCodePoint(0xF007A + Math.min(8, Math.floor(batteryPercent / 10) - 1));
	}

	Rectangle {
		anchors.fill: parent
		color: root.voidColor
	}

	Image {
		anchors.fill: parent
		source: root.wallpaperPath
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
		cache: true
		smooth: true
	}

	MouseArea {
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.AllButtons
		onPressed: mouse => {
			root.pokeUi();
			mouse.accepted = false;
		}
		onPositionChanged: root.pokeUi()
		onWheel: root.pokeUi()
	}

	Timer {
		id: clockTimer
		running: true
		repeat: true
		interval: 1000
		onTriggered: root.now = new Date()
	}

	Timer {
		id: fadeTimer
		interval: 60000
		repeat: false
		onTriggered: {
			if (passwordBox.text.length === 0)
				root.uiVisible = false;
		}
	}

	Process {
		id: capsQuery
		command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | head -n1"]
		running: false
		stdout: StdioCollector {
			onStreamFinished: {
				const t = this.text.trim();
				if (t === "1")
					root.capsOn = true;
				else if (t === "0")
					root.capsOn = false;
			}
		}
	}

	Process {
		id: powerProc
		running: false
	}

	// Clock stays visible when chrome fades (Breeze greeter behavior).
	Item {
		id: clockBlock
		visible: root.showUi
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: loginStack.top
		anchors.bottomMargin: 36
		width: clockCol.width
		height: clockCol.height

		Column {
			id: clockCol
			spacing: 4

			Item {
				implicitWidth: clockText.width + 4
				implicitHeight: clockText.height + 4
				anchors.horizontalCenter: parent.horizontalCenter

				Text {
					text: clockText.text
					color: "#B0000000"
					font: clockText.font
					x: 1
					y: 2
				}

				Text {
					id: clockText
					text: Qt.formatDateTime(root.now, "HH:mm")
					color: root.textColor
					font.pixelSize: 72
					font.weight: Font.Light
				}
			}

			Text {
				anchors.horizontalCenter: parent.horizontalCenter
				text: Qt.formatDateTime(root.now, "dddd d MMMM")
				color: root.textColor
				font.pixelSize: 18
				opacity: 0.9
			}
		}
	}

	ColumnLayout {
		id: loginStack
		visible: root.showUi
		opacity: root.uiVisible ? 1 : 0
		spacing: 14
		width: 320
		implicitWidth: 320
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.horizontalCenterOffset: shakeX.x
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: 28

		Behavior on opacity {
			NumberAnimation {
				duration: 400
				easing.type: Easing.InOutQuad
			}
		}

		Item {
			Layout.alignment: Qt.AlignHCenter
			implicitWidth: 88
			implicitHeight: 88

			Rectangle {
				anchors.fill: parent
				radius: width / 2
				color: Qt.rgba(depthColor.r, depthColor.g, depthColor.b, 0.67)
				border.width: 2
				border.color: root.accentColor
			}

			Image {
				id: faceImage
				anchors.fill: parent
				anchors.margins: 4
				source: {
					if (!root.showUi || !root.homeDir)
						return "";
					if (root.faceTry === 0)
						return `file://${root.homeDir}/.face`;
					if (root.faceTry === 1)
						return `file://${root.homeDir}/.face.icon`;
					return "";
				}
				fillMode: Image.PreserveAspectCrop
				asynchronous: true
				visible: status === Image.Ready
				onStatusChanged: {
					if (status === Image.Error && root.faceTry < 2)
						root.faceTry += 1;
				}
			}

			Text {
				anchors.centerIn: parent
				visible: !faceImage.visible
				text: root.userName.charAt(0).toUpperCase()
				color: root.textColor
				font.pixelSize: 36
				font.weight: Font.Medium
			}
		}

		Text {
			Layout.alignment: Qt.AlignHCenter
			text: root.userName
			color: root.textColor
			font.pixelSize: 18
		}

		Text {
			Layout.alignment: Qt.AlignHCenter
			visible: root.capsOn
			text: "Caps Lock is on"
			color: root.errorColor
			font.pixelSize: 13
		}

		Item {
			Layout.alignment: Qt.AlignHCenter
			Layout.preferredWidth: 320
			implicitWidth: 320
			implicitHeight: 42

			Rectangle {
				anchors.fill: parent
				radius: 8
				color: root.surfaceColor
				border.width: 1
				border.color: passwordBox.activeFocus ? root.accentColor : Qt.rgba(surfaceSolid.r, surfaceSolid.g, surfaceSolid.b, 0.5)

				TextInput {
					id: passwordBox
					anchors.fill: parent
					anchors.leftMargin: 12
					anchors.rightMargin: 48
					verticalAlignment: TextInput.AlignVCenter
					echoMode: TextInput.Password
					passwordCharacter: "•"
					color: root.textColor
					selectionColor: root.accentColor
					selectedTextColor: root.voidColor
					font.pixelSize: 15
					enabled: !root.context.unlockInProgress
					inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
					focus: root.primary

					Text {
						anchors.fill: parent
						verticalAlignment: Text.AlignVCenter
						text: "Password"
						color: root.mutedColor
						font.pixelSize: 15
						visible: passwordBox.text.length === 0 && !passwordBox.activeFocus
					}

					onTextChanged: {
						root.context.currentText = text;
						root.pokeUi();
					}
					onAccepted: root.context.tryUnlock()

					Keys.onPressed: event => root.handleKey(event)

					Connections {
						target: root.context
						function onCurrentTextChanged() {
							if (passwordBox.text !== root.context.currentText)
								passwordBox.text = root.context.currentText;
						}
					}
				}

				Rectangle {
					id: submitBtn
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					anchors.rightMargin: 4
					implicitWidth: 34
					implicitHeight: 34
					radius: 6
					color: enabled ? root.accentColor : Qt.rgba(surfaceSolid.r, surfaceSolid.g, surfaceSolid.b, 0.4)
					enabled: !root.context.unlockInProgress && root.context.currentText !== ""
					opacity: enabled ? 1 : 0.45

					Text {
						anchors.centerIn: parent
						text: String.fromCodePoint(0xF0142)
						color: root.voidColor
						font.pixelSize: 20
						font.family: "IosevkaTermSlab NF"
					}

					MouseArea {
						anchors.fill: parent
						enabled: submitBtn.enabled
						cursorShape: Qt.PointingHandCursor
						onClicked: root.context.tryUnlock()
					}
				}
			}
		}

		Text {
			Layout.alignment: Qt.AlignHCenter
			visible: root.context.showFailure
			text: "Unlock failed"
			color: root.errorColor
			font.pixelSize: 13
		}

		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: 18
			spacing: 28
			opacity: root.preview ? 0.4 : 1

			Repeater {
				model: [
					{
						kind: "sleep",
						label: "Sleep",
						glyph: 0xF04B2
					},
					{
						kind: "reboot",
						label: "Restart",
						glyph: 0xF0709
					},
					{
						kind: "poweroff",
						label: "Shut Down",
						glyph: 0xF0425
					}
				]

				delegate: Item {
					required property var modelData
					implicitWidth: Math.max(powerIcon.implicitWidth, powerLabel.implicitWidth) + 16
					implicitHeight: powerIcon.implicitHeight + powerLabel.implicitHeight + 10
					opacity: powerHover.containsMouse && !root.preview ? 1 : 0.85

					Text {
						id: powerIcon
						anchors.top: parent.top
						anchors.horizontalCenter: parent.horizontalCenter
						text: String.fromCodePoint(modelData.glyph)
						color: root.textColor
						font.pixelSize: 22
						font.family: "IosevkaTermSlab NF"
					}

					Text {
						id: powerLabel
						anchors.top: powerIcon.bottom
						anchors.topMargin: 6
						anchors.horizontalCenter: parent.horizontalCenter
						text: modelData.label
						color: root.textColor
						font.pixelSize: 12
					}

					MouseArea {
						id: powerHover
						anchors.fill: parent
						hoverEnabled: true
						enabled: !root.preview
						cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
						onClicked: root.requestPower(modelData.kind)
					}
				}
			}
		}
	}

	Text {
		visible: root.showUi && root.preview
		opacity: root.uiVisible ? 1 : 0
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.top: parent.top
		anchors.topMargin: 24
		text: "PREVIEW — Esc to close"
		color: root.accentColor
		font.pixelSize: 14
		font.weight: Font.Medium

		Behavior on opacity {
			NumberAnimation {
				duration: 400
			}
		}
	}

	Row {
		visible: root.showUi && root.batteryPresent
		opacity: root.uiVisible ? 1 : 0
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: 16
		spacing: 6

		Behavior on opacity {
			NumberAnimation {
				duration: 400
			}
		}

		Text {
			text: root.batteryGlyph()
			color: root.textColor
			font.pixelSize: 16
			font.family: "IosevkaTermSlab NF"
			anchors.verticalCenter: parent.verticalCenter
		}

		Text {
			text: `${root.batteryPercent}%`
			color: root.textColor
			font.pixelSize: 13
			anchors.verticalCenter: parent.verticalCenter
		}
	}

	QtObject {
		id: shakeX
		property real x: 0
	}

	SequentialAnimation {
		id: shakeAnim
		NumberAnimation {
			target: shakeX
			property: "x"
			to: 18
			duration: 40
		}
		NumberAnimation {
			target: shakeX
			property: "x"
			to: -18
			duration: 50
		}
		NumberAnimation {
			target: shakeX
			property: "x"
			to: 12
			duration: 40
		}
		NumberAnimation {
			target: shakeX
			property: "x"
			to: -8
			duration: 40
		}
		NumberAnimation {
			target: shakeX
			property: "x"
			to: 0
			duration: 40
		}
	}

	Shortcut {
		enabled: root.preview && root.showUi
		sequence: "Esc"
		onActivated: root.dismissRequested()
	}

	Connections {
		target: root.context
		function onFailed() {
			shakeAnim.restart();
			root.pokeUi();
		}
	}

	// The chrome work (avatar retry, fade poke, caps query) is per-surface and
	// stays gated on showUi. Only the focus grab is gated on primary.
	onShowUiChanged: {
		if (showUi) {
			root.faceTry = 0;
			root.pokeUi();
			capsQuery.running = false;
			capsQuery.running = true;
			if (root.primary)
				passwordBox.forceActiveFocus();
		}
	}

	Component.onCompleted: {
		if (showUi) {
			root.pokeUi();
			capsQuery.running = true;
			if (root.primary)
				passwordBox.forceActiveFocus();
		}
	}
}
