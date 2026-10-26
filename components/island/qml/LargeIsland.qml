import QtQuick
import AetherShared

// Content of the large island: header, then rows that only exist when relevant.
//   media (when a player exists) / toggles / sliders / timer (when opened or running)
Item {
    id: root
    required property var timer
    property date now: new Date()
    signal closeRequested()

    readonly property int pad: 22
    readonly property real contentHeight: header.height + 14 + column.implicitHeight + 34
    property bool timerOpen: false

    Item {
        id: header
        x: root.pad; y: 0
        width: root.width - 2 * root.pad
        height: 52
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; verticalCenterOffset: 4 }
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
            color: Theme.text
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 4 }
            spacing: 12
            Row {
                visible: system.hasBattery
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: system.batteryPercent + "%"
                    anchors.verticalCenter: parent.verticalCenter
                    font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                    color: Theme.subtext
                }
                BatteryGlyph { percent: system.batteryPercent; charging: system.charging; anchors.verticalCenter: parent.verticalCenter }
            }
            Text {
                text: Qt.formatTime(root.now, "H:mm")
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.mono; pixelSize: 15; weight: Font.Medium }
                color: Theme.text
            }
        }
    }

    Column {
        id: column
        x: root.pad; y: header.height + 14
        width: root.width - 2 * root.pad
        spacing: 12

        MediaCard { width: parent.width; visible: media.hasPlayer }

        Row {
            width: parent.width
            spacing: 10
            readonly property real w: (width - 3 * spacing) / 4
            ToggleChip {
                width: parent.w
                glyph: system.network === "ethernet" ? "ethernet" : (system.wifiEnabled ? "wifi-3" : "wifi-off")
                label: !system.wifiEnabled ? "Wi-Fi off" : (system.wifiName || "Wi-Fi")
                active: system.wifiEnabled
                onTapped: system.toggleWifi()
            }
            ToggleChip {
                width: parent.w
                glyph: system.bluetoothOn ? "bluetooth" : "bluetooth-off"
                label: !system.bluetoothOn ? "Bluetooth off" : (system.bluetoothDevices > 0 ? system.bluetoothDevices + " connected" : "Bluetooth")
                active: system.bluetoothOn
                onTapped: system.toggleBluetooth()
            }
            ToggleChip {
                width: parent.w
                glyph: system.muted ? "volume-muted" : "volume-2"
                label: system.muted ? "Muted" : "Sound on"
                active: !system.muted
                onTapped: system.toggleMute()
            }
            ToggleChip {
                width: parent.w
                glyph: "timer"
                label: root.timer.active ? root.timer.text : "Timer"
                active: root.timer.active || root.timerOpen
                onTapped: root.timerOpen = !root.timerOpen
            }
        }

        TimerRow { width: parent.width; timer: root.timer; visible: root.timerOpen || root.timer.active }

        Row {
            width: parent.width
            spacing: 12
            Glyph {
                name: system.muted || system.volume === 0 ? "volume-muted" : system.volume < 34 ? "volume-1" : "volume-2"
                size: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            SliderBar {
                width: parent.width - 18 - 12
                anchors.verticalCenter: parent.verticalCenter
                value: system.muted ? 0 : system.volume / 100
                onMoved: (v) => system.setVolume(Math.round(v * 100))
            }
        }
        Row {
            width: parent.width
            visible: system.brightness >= 0
            spacing: 12
            Glyph { name: "sun"; size: 18; anchors.verticalCenter: parent.verticalCenter }
            SliderBar {
                width: parent.width - 18 - 12
                anchors.verticalCenter: parent.verticalCenter
                value: Math.max(0, system.brightness) / 100
                onMoved: (v) => system.setBrightness(Math.round(v * 100))
            }
        }
    }

    Rectangle {                         // handle: click to go back to the bar
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
        width: 44; height: 5; radius: 3
        color: handleTap.pressed ? Theme.text : Theme.subtext
        opacity: 0.8
        Behavior on color { ColorAnimation { duration: 120 } }
        TapHandler { id: handleTap; onTapped: root.closeRequested() }
    }
}
