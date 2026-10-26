import QtQuick
import org.kde.taskmanager as TaskManager
import "."

// Aether Island - replaces the top bar.
//   hidden  nothing visible; an invisible strip along the top edge listens for the pointer
//   bar     the bar appears across the whole width with the notch hanging from its middle:
//           logo + active app on the left, status glyphs + date on the right, clock in the notch
//   large   the notch grows into the full island (the window then covers the screen so a
//           click outside can close it)
// Open:  touch the top edge (bar), then click or scroll down on the notch (large), or Win+N
// Close: click outside, Esc, scroll up, the handle, or leave with the pointer.
Item {
    id: root

    readonly property real shoulder: 10
    readonly property real screenW: island.screenWidth
    readonly property real screenH: island.screenHeight
    readonly property var shapes: ({
        // sw = strip width, sh = strip height, nw = notch width, nb = notch bottom, r = notch corner radius
        "hidden": { sw: 0,       sh: 0,  nw: 120, nb: 2,   r: 1,  win: Qt.size(screenW, 2) },
        "bar":    { sw: screenW, sh: 30, nw: 232, nb: 38,  r: 14, win: Qt.size(screenW, 38) },
        "large":  { sw: 0,       sh: 0,  nw: 480, nb: Math.max(170, largeContent.contentHeight), r: 30, win: Qt.size(screenW, screenH) }
    })

    property string mode: "hidden"
    readonly property var shape: shapes[mode]
    property date now: new Date()

    Binding { target: Theme; property: "bodyAlpha"; value: island.bodyAlpha }
    TimerState { id: timerState }
    Timer { interval: 1000; running: root.mode !== "hidden"; repeat: true; onTriggered: root.now = new Date() }

    // ---- active app name -------------------------------------------------------------
    TaskManager.TasksModel { id: tasks; groupMode: TaskManager.TasksModel.GroupDisabled }
    property string appName: ""
    function refreshApp() {
        const idx = tasks.activeTask
        const n = idx.valid ? tasks.data(idx, TaskManager.AbstractTasksModel.AppName) : ""
        appName = n && n.length ? n : "Desktop"
    }
    Connections {
        target: tasks
        function onActiveTaskChanged() { root.refreshApp() }
        function onDataChanged() { root.refreshApp() }
        function onCountChanged() { root.refreshApp() }
    }
    Component.onCompleted: { refreshApp(); island.setWindowSize(curWin.width, curWin.height) }

    // ---- window sizing: grow before the shape animates, shrink after ----------------
    property size curWin: Qt.size(screenW, 2)
    function applyWindow() {
        const t = shapes[mode].win
        const grows = t.width * t.height > curWin.width * curWin.height
        if (t.width === curWin.width && t.height === curWin.height) return
        if (grows) {
            shrinkTimer.stop()
            curWin = t
            island.setWindowSize(t.width, t.height)
        } else {
            shrinkTimer.restart()
        }
    }
    Timer {
        id: shrinkTimer
        interval: 420
        onTriggered: {
            root.curWin = root.shapes[root.mode].win
            island.setWindowSize(curWin.width, curWin.height)
        }
    }

    // ---- state changes ---------------------------------------------------------------
    function setMode(next) {
        if (next === "toggle") next = mode === "large" ? "bar" : "large"
        if (next === mode) return
        mode = next
        island.setKeyboard(next === "large")
        leaveTimer.stop()
        if (next !== "hidden") now = new Date()
        applyWindow()
    }
    Connections {
        target: island
        function onStateRequested(state) {
            if (state === "small") state = "bar"
            if (state === "bar" && root.mode === "large") return
            root.setMode(state)
        }
    }

    // ---- pointer ----------------------------------------------------------------------
    HoverHandler { id: windowHover }
    readonly property bool pointerIn: mode === "large" ? notchArea.hovered : windowHover.hovered
    onPointerInChanged: {
        if (pointerIn) {
            leaveTimer.stop()
            if (mode === "hidden") peekTimer.restart()
        } else {
            peekTimer.stop()
            if (mode !== "hidden") leaveTimer.restart()
        }
    }
    Timer { id: peekTimer; interval: 120; onTriggered: if (root.pointerIn) root.setMode("bar") }
    Timer {
        id: leaveTimer
        interval: root.mode === "large" ? 2000 : 900
        onTriggered: if (!root.pointerIn) root.setMode(root.mode === "large" ? "bar" : "hidden")
    }

    focus: true
    Keys.onEscapePressed: root.setMode(root.mode === "large" ? "bar" : "hidden")

    // Click outside the island (only reachable while the window covers the screen)
    MouseArea {
        anchors.fill: parent
        enabled: root.mode === "large"
        onClicked: root.setMode("bar")
    }

    // ---- the shape ----------------------------------------------------------------------
    NotchSurface {
        id: surface
        x: 0; y: 0
        winW: root.width
        stripW: root.shape.sw
        stripH: root.shape.sh
        notchW: root.shape.nw
        notchBottom: root.shape.nb
        cornerR: root.shape.r
        shoulder: root.shoulder
        opacity: root.mode === "hidden" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on stripW { SpringAnimation { spring: 3.0; damping: 0.34; epsilon: 0.5 } }
        Behavior on stripH { SpringAnimation { spring: 3.4; damping: 0.30; epsilon: 0.3 } }
        Behavior on notchW { SpringAnimation { spring: 3.4; damping: 0.28; epsilon: 0.3 } }
        Behavior on notchBottom { SpringAnimation { spring: 3.4; damping: 0.28; epsilon: 0.3 } }
        Behavior on cornerR { SpringAnimation { spring: 3.4; damping: 0.28; epsilon: 0.3 } }
    }

    // The notch's own area: hover target in large mode, click/scroll target in bar mode.
    Item {
        id: notchArea
        readonly property alias hovered: notchHover.hovered
        x: (root.width - surface.notchW) / 2
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        HoverHandler { id: notchHover }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: if (root.mode === "bar") root.setMode("large")
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => {
                if (e.angleDelta.y < 0 && root.mode === "bar") root.setMode("large")
                else if (e.angleDelta.y > 0 && root.mode === "large") root.setMode("bar")
            }
        }
    }

    // ---- bar content --------------------------------------------------------------------
    Item {
        id: barContent
        x: 0; y: 0
        width: root.width
        height: surface.stripH
        opacity: root.mode === "bar" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        // Left: logo + active app
        Row {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Glyph { name: "logo"; size: 15; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: root.appName
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.font; pixelSize: 13; weight: Font.Bold }
                color: Theme.text
            }
        }

        // Right: status glyphs + date
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 14
            Glyph {
                visible: system.bluetoothOn
                name: system.bluetoothOn ? "bluetooth" : "bluetooth-off"
                size: 15
                anchors.verticalCenter: parent.verticalCenter
            }
            Glyph {
                name: system.network === "ethernet" ? "ethernet"
                    : system.network === "wifi" ? (system.wifiSignal > 66 ? "wifi-3" : system.wifiSignal > 33 ? "wifi-2" : "wifi-1")
                    : "wifi-off"
                size: 15
                anchors.verticalCenter: parent.verticalCenter
            }
            Glyph {
                name: system.muted || system.volume === 0 ? "volume-muted" : system.volume < 34 ? "volume-1" : "volume-2"
                size: 15
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                visible: system.hasBattery
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: system.batteryPercent + "%"
                    anchors.verticalCenter: parent.verticalCenter
                    font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                    color: Theme.text
                }
                BatteryGlyph {
                    percent: system.batteryPercent
                    charging: system.charging
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: Qt.formatDate(root.now, "ddd d MMM")
                anchors.verticalCenter: parent.verticalCenter
                font { family: Theme.font; pixelSize: 12; weight: Font.Medium }
                color: Theme.subtext
            }
        }
    }

    // Clock in the notch (bar mode); a running timer takes its place and a finished one pulses.
    Text {
        id: notchText
        x: (root.width - width) / 2
        y: (surface.notchBottom - height) / 2 + 1
        text: timerState.done ? "Time's up" : (timerState.active ? timerState.text : Qt.formatTime(root.now, "H:mm"))
        opacity: root.mode === "bar" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        font { family: Theme.mono; pixelSize: 14; weight: Font.Medium }
        color: timerState.done || timerState.active ? Theme.accent : Theme.text
        SequentialAnimation on scale {
            running: timerState.done
            loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 420; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
        }
    }

    // ---- large content ----------------------------------------------------------------
    LargeIsland {
        id: largeContent
        x: (root.width - surface.notchW) / 2
        y: 0
        width: surface.notchW
        height: surface.notchBottom
        timer: timerState
        now: root.now
        opacity: root.mode === "large" && surface.notchBottom > 150 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        onCloseRequested: root.setMode("bar")
    }

    // ---- keep KWin's blur + the input region glued to the animated shape ---------------
    property string lastKey: ""
    function syncLayout() {
        const key = [surface.sw, surface.stripH, surface.notchW, surface.notchBottom, surface.rb, surface.opacity > 0.05, root.mode, root.width]
                    .map(function (v) { return typeof v === "number" ? Math.round(v) : v }).join("|")
        if (key === lastKey) return
        lastKey = key
        const visible = surface.opacity > 0.05
        island.setLayout(visible ? surface.segments : [], root.mode === "large",
                         root.mode === "hidden" ? Qt.rect(0, 0, root.width, 2) : Qt.rect(0, 0, 0, 0))
    }
    Timer { interval: 16; repeat: true; running: true; onTriggered: root.syncLayout() }
}
