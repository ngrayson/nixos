import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Wayland

Rectangle {
	id: root
	required property LockContext context

	Loader {
		id: wpal
		asynchronous: false
		active: true
		source: "WallustColors.qml"
	}

	color: wpal.item ? wpal.item.barBg : "#1a1a2e"

	Label {
		id: clock
		property var date: new Date()

		anchors {
			horizontalCenter: parent.horizontalCenter
			top: parent.top
			topMargin: 100
		}

		color: wpal.item ? wpal.item.text : "#cdd6f4"
		renderType: Text.NativeRendering
		font.pointSize: 80

		Timer {
			running: true
			repeat: true
			interval: 1000

			onTriggered: clock.date = new Date();
		}

		text: {
			const hours = this.date.getHours().toString().padStart(2, '0');
			const minutes = this.date.getMinutes().toString().padStart(2, '0');
			return `${hours}:${minutes}`;
		}
	}

	ColumnLayout {
		anchors {
			horizontalCenter: parent.horizontalCenter
			top: parent.verticalCenter
		}

		RowLayout {
			TextField {
				id: passwordBox

				implicitWidth: 400
				padding: 10

				focus: true
				enabled: !root.context.unlockInProgress
				echoMode: TextInput.Password
				inputMethodHints: Qt.ImhSensitiveData
				placeholderText: "Password"
				placeholderTextColor: wpal.item ? wpal.item.muted : "#6c7086"
				color: wpal.item ? wpal.item.text : "#ffffff"

				background: Rectangle {
					implicitWidth: 400
					color: wpal.item ? wpal.item.muted : "#2a2a3a"
					border.width: 1
					border.color: wpal.item ? wpal.item.accent : "#89b4fa"
					radius: 4
				}

				onTextChanged: root.context.currentText = this.text;

				onAccepted: root.context.tryUnlock();

				Connections {
					target: root.context

					function onCurrentTextChanged() {
						passwordBox.text = root.context.currentText;
					}
				}
			}

			Button {
				id: unlockBtn
				text: "Unlock"
				padding: 10

				focusPolicy: Qt.NoFocus

				enabled: !root.context.unlockInProgress && root.context.currentText !== "";
				onClicked: root.context.tryUnlock();

				contentItem: Text {
					text: unlockBtn.text
					font: unlockBtn.font
					opacity: enabled ? 1.0 : 0.3
				color: wpal.item ? (wpal.item.onAccent || "#1e1e2e") : "#1e1e2e"
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					elide: Text.ElideRight
				}

				background: Rectangle {
					implicitWidth: unlockBtn.implicitContentWidth + 20
					implicitHeight: 40
					color: wpal.item ? wpal.item.accent : "#89b4fa"
					radius: 4
				}
			}
		}

		Label {
			visible: root.context.showFailure
			text: "Incorrect password"
			color: wpal.item ? (wpal.item.error || "#f38ba8") : "#f38ba8"
		}
	}
}
