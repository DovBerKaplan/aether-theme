import QtQuick
import AetherShared
import "."

// Content of the large island: header, then rows that only exist when relevant.
//   media (when a player exists) / toggles / sliders / timer (when opened or running)
// Past the controls a notification section fades in; the island's height drives it, so the
// reveal stays continuous mid-drag. The handle reports its pull gesture raw to Island.qml.
Item {
    id: root
    required property var timer
    property date now: new Date()
    property string appName: ""
    // Clip to the island's silhouette: while the glass shrinks, content must never be
    // drawn outside it - rows are revealed by the growing edge on open, swallowed by it
    // on close, at a fading opacity set by Island.qml's height-mapped fades.
    clip: true
    signal closeRequested()
    signal mediaRequested()
    signal panelRequested(string id)
    signal pullStarted()
    signal pullMoved(real dy, real vy)
    signal pullEnded()
    signal holdDetected()

    readonly property int pad: 22
    readonly property real contentHeight: header.height + 14 + column.implicitHeight + 34
    // 61 = divider zone + section header + bottom padding around the handle
    readonly property real notifListHeight: notifStore.list.length === 0 ? 76 : notifStore.list.length * 76 - 8
    readonly property real expandedHeight: contentHeight + 61 + notifListHeight
    readonly property bool notifAtTop: notifList.atTop
    // The section fades across the whole large->expanded segment, so it materialises with
    // the glass's own spring instead of popping in over a narrow pixel band.
    readonly property real notifFade: Math.max(0, Math.min(1,
        (height - contentHeight - 8) / Math.max(1, expandedHeight - contentHeight - 8)))
    property bool timerOpen: false
    property bool holdConsumed: false

    // Called by Island.qml whenever the island drops below the large stop: the next open
    // presents a fresh panel - list back at the top, timer controls folded. Deferred until
    // the closing spring has settled: resetting mid-flight retargets the jelly (the timer
    // row changes the content height) and visibly jumps the list scroll.
    function resetUi() { resetTimer.restart() }
    Timer {
        id: resetTimer
        interval: 450
        onTriggered: {
            notifList.resetScroll()
            timerOpen = false
            holdConsumed = false
        }
    }
    onNotifFadeChanged: if (notifFade > 0.2) resetTimer.stop()   // reopened before it ran

    // The notch "becomes" YouTube Music: the island takes it from here (setMode("media")
    // opens the panel and seats the app window inside it).
    function openMediaSearch() {
        mediaRequested()
    }

    Item {
        id: header
        x: root.pad; y: 0
        width: root.width - 2 * root.pad
        height: 52
        Text {
            id: dateText
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; verticalCenterOffset: 4 }
            TapHandler { onTapped: root.panelRequested("calendar") }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.DemiBold }
            color: Theme.text
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 4 }
            spacing: 12
            // The active app (it used to live in the bar's left corner)
            Text {
                visible: root.appName.length > 0
                text: root.appName
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 150)
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                color: Theme.subtext
            }
            Row {
                visible: system.hasBattery
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                TapHandler { onTapped: root.panelRequested("battery") }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Text {
                    text: system.batteryPercent + "%"
                    anchors.verticalCenter: parent.verticalCenter
                    font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                    color: Theme.subtext
                }
                BatteryGlyph { percent: system.batteryPercent; charging: system.charging; anchors.verticalCenter: parent.verticalCenter }
            }
            Text {
                text: Qt.formatTime(root.now, "H:mm")
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.mono; pixelSize: Tokens.type.title; weight: Font.Medium }
                color: Theme.text
            }
        }
    }

    Column {
        id: column
        x: root.pad; y: header.height + 14
        width: root.width - 2 * root.pad
        spacing: 12

        // The song card is permanent - playing, paused or resting (no player yet);
        // it is also the way into the media view (the app inside the bar).
        MediaCard { width: parent.width; onSearchRequested: root.openMediaSearch() }

        Row {
            width: parent.width
            spacing: 10
            readonly property real w: (width - 3 * spacing) / 4
            ToggleChip {
                width: parent.w
                glyph: system.network === "ethernet" ? "ethernet" : (system.wifiEnabled ? "wifi-3" : "wifi-off")
                label: "Wi‑Fi"
                sublabel: !system.wifiEnabled ? "Off" : (system.wifiName || "Not connected")
                active: system.wifiEnabled
                hasPanel: true
                onTapped: system.toggleWifi()
                onPanelRequested: root.panelRequested("wifi")
            }
            ToggleChip {
                width: parent.w
                glyph: system.bluetoothOn ? "bluetooth" : "bluetooth-off"
                label: "Bluetooth"
                sublabel: !system.bluetoothOn ? "Off" : (system.bluetoothDevices > 0 ? system.bluetoothDevices + " connected" : "On")
                active: system.bluetoothOn
                hasPanel: true
                onTapped: system.toggleBluetooth()
                onPanelRequested: root.panelRequested("bluetooth")
            }
            ToggleChip {
                width: parent.w
                glyph: system.muted ? "volume-muted" : "volume-2"
                label: "Sound"
                sublabel: system.muted ? "Muted" : system.volume + "%"
                active: !system.muted
                hasPanel: true
                onTapped: system.toggleMute()
                onPanelRequested: root.panelRequested("sound")
            }
            ToggleChip {
                width: parent.w
                glyph: "timer"
                label: "Timer"
                sublabel: root.timer.active ? root.timer.text : ""
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
                TapHandler { onTapped: root.panelRequested("sound") }
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
            Glyph {
                name: "sun"; size: 18; anchors.verticalCenter: parent.verticalCenter
                TapHandler { onTapped: root.panelRequested("display") }
            }
            SliderBar {
                width: parent.width - 18 - 12
                anchors.verticalCenter: parent.verticalCenter
                value: Math.max(0, system.brightness) / 100
                onMoved: (v) => system.setBrightness(Math.round(v * 100))
            }
        }
    }

    // ---- notifications (expanded island) ----------------------------------------------
    Rectangle {
        id: divider
        x: root.pad + 16
        width: root.width - 2 * root.pad - 32
        y: column.y + column.implicitHeight + 16
        height: 1
        color: Theme.rim
        opacity: root.notifFade
        visible: opacity > 0
    }
    NotificationList {
        id: notifList
        x: root.pad
        width: root.width - 2 * root.pad
        y: divider.y + 15
        height: Math.max(0, root.height - y - 26)
        now: root.now
        opacity: root.notifFade
        visible: opacity > 0
    }

    // ---- handle: pull to resize, click to close ----------------------------------------
    // The grab zone is much taller than the visible pill so the drag is easy to land.
    Item {
        id: handle
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
        width: 64; height: 20
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        Rectangle {
            anchors.centerIn: parent
            width: 44; height: 5; radius: Tokens.radius.xs
            color: handleTap.pressed || handleDrag.active ? Theme.text : Theme.subtext
            opacity: 0.8
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        }
        // A static click still closes to the bar; a held press (350ms, no movement) expands.
        TapHandler {
            id: handleTap
            onPressedChanged: pressed ? holdTimer.restart() : holdTimer.stop()
            onTapped: {
                if (root.holdConsumed) { root.holdConsumed = false; return }
                root.closeRequested()
            }
        }
        DragHandler {
            id: handleDrag
            target: null
            onActiveChanged: {
                holdTimer.stop()
                if (active) { root.holdConsumed = false; root.pullStarted() }
                else root.pullEnded()
            }
            onTranslationChanged: {
                if (active) root.pullMoved(translation.y, centroid.velocity.y)
                if (Math.abs(translation.y) > 4) holdTimer.stop()
            }
        }
        Timer { id: holdTimer; interval: 350; onTriggered: { root.holdConsumed = true; root.holdDetected() } }
    }
}
