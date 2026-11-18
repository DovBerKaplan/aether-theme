import QtQuick
import QtQuick.Effects
import AetherShared

// The power bar (docs/PANELS-SPEC.md section 9, redesigned): one minimal glass row. Lock and
// sleep act at once; log out, restart and shut down need a deliberate ~1.1 s hold - a ring
// drains around the pebble in the island's danger red, releasing early cancels softly.
// Keyboard: Enter arms (the ring drains in 5 s, the label asks again), Enter again acts.
// No header, no footer - a back chevron, the pebbles, and a firmware whisper.
Item {
    id: root
    property real maxHeight: 10000
    readonly property real contentHeight: Math.min(maxHeight,
        8 + 68 + (session.canFirmware ? 20 : 0) + 10)
    signal closeRequested()

    readonly property color danger: Tokens.role.island.negative

    function g(n) { return Qt.resolvedUrl("assets/glyphs/" + n + ".svg") }

    function fire(act) {
        session[act]()
        root.closeRequested()
    }

    // A gentle escalation across the row; mirrors itself in RTL.
    readonly property var pebbles: {
        const p = []
        if (session.canSleep) p.push({ glyph: "moon", label: I18n.tr("Sleep"), act: "sleep" })
        p.push({ glyph: "lock", label: I18n.tr("Lock"), act: "lock" })
        p.push({ glyph: "logout", label: I18n.tr("Log out"), act: "logout", confirm: true })
        p.push({ glyph: "restart", label: I18n.tr("Restart"), act: "restart", confirm: true })
        p.push({ glyph: "power", label: I18n.tr("Shut down"), act: "shutDown", confirm: true })
        return p
    }

    BackButton {
        id: back
        anchors { left: parent.left; leftMargin: 8; verticalCenter: rowArea.verticalCenter }
        onActivated: root.closeRequested()
    }

    Item {
        id: rowArea
        anchors { top: parent.top; topMargin: 8; left: parent.left; right: parent.right }
        height: 68
        Row {
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: root.pebbles
                Pebble {}
            }
        }
    }

    Text {
        visible: session.canFirmware
        anchors { horizontalCenter: parent.horizontalCenter; top: rowArea.bottom; topMargin: 2 }
        property bool armed: false
        text: armed ? I18n.tr("Tap again to reboot into firmware") : I18n.tr("Firmware setup")
        textFormat: Text.PlainText
        font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
        color: armed ? Tokens.role.island.attention : Theme.subtext
        opacity: armed || fwHover.hovered ? 1 : 0.8
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        HoverHandler { id: fwHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                if (firmware.armed) { firmware.armed = false; root.fire("restartToFirmware") }
                else { firmware.armed = true; fwTimer.restart() }
            }
        }
        Timer { id: fwTimer; interval: 4000; onTriggered: firmware.armed = false }
    }

    component Pebble: Item {
        id: peb
        required property var modelData
        readonly property bool confirm: modelData.confirm === true
        readonly property string confirmText: {
            const a = peb.modelData.act
            return a === "restart" ? I18n.tr("Tap to restart") : a === "shutDown" ? I18n.tr("Tap to shut down") : I18n.tr("Tap to log out")
        }
        property bool holding: false      // pointer hold in progress
        property bool armed: false        // keyboard: first Enter arms, second acts
        property bool fired: false        // this pebble already sent its action
        width: 56; height: 68
        activeFocusOnTab: true

        Keys.onReturnPressed: (event) => {
            if (peb.fired) return
            if (!peb.confirm || (event.modifiers & Qt.ShiftModifier)) peb.go()
            else if (peb.armed) peb.go()
            else { peb.armed = true; peb.holding = false; ring.tone = Theme.accent; armAnim.restart() }
        }

        function go() {
            if (peb.fired) return
            peb.fired = true
            holdAnim.stop(); armAnim.stop()
            peb.holding = false; peb.armed = false
            ring.opacity = 0
            root.fire(peb.modelData.act)
        }
        function cancel() {
            holdAnim.stop(); armAnim.stop()
            peb.holding = false; peb.armed = false
            ring.opacity = 0
        }

        // the pebble itself: quiet glass, ink glyph - nothing at rest, like a toggled-off chip
        Rectangle {
            id: circle
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: 48; height: 48; radius: 24
            color: Theme.veil(peb.holding ? Tokens.tint.strong
                          : peb.armed || hover.hovered || tap.pressed ? Tokens.tint.soft
                          : Tokens.tint.subtle)
            border { width: peb.activeFocus ? 2 : 0; color: Theme.accent }
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
            Item {
                anchors.centerIn: parent
                width: 18; height: 18
                Image { id: g; anchors.fill: parent; source: root.g(peb.modelData.glyph); sourceSize: Qt.size(54, 54); visible: false }
                MultiEffect {
                    anchors.fill: g; source: g; colorization: 1.0
                    colorizationColor: peb.holding ? root.danger : peb.armed ? Theme.accent : Theme.text
                    scale: tap.pressed ? 0.92 : 1
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }
                    Behavior on colorizationColor { ColorAnimation { duration: Tokens.motion.duration.fast } }
                }
            }
        }

        // the draining ring: a hold drains it in the danger red; a keyboard arm drains it in accent
        Canvas {
            id: ring
            anchors.fill: circle
            property real progress: 0
            property color tone: root.danger
            opacity: peb.holding || peb.armed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            onProgressChanged: requestPaint()
            onToneChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (progress <= 0.002) return
                ctx.strokeStyle = Qt.rgba(tone.r, tone.g, tone.b, 0.95)
                ctx.lineWidth = 2; ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, width / 2 - 1.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress)
                ctx.stroke()
            }
            NumberAnimation { id: holdAnim; target: ring; property: "progress"; from: 1; to: 0; duration: 1100
                onFinished: if (peb.holding) { peb.holding = false; pulseAnim.restart() } }
            NumberAnimation { id: armAnim; target: ring; property: "progress"; from: 1; to: 0; duration: 5000
                onFinished: peb.armed = false }
        }

        // the completed hold: the ring blooms once, then the machine obeys
        Rectangle {
            id: pulse
            anchors.fill: circle; radius: width / 2; color: "transparent"
            border { width: 2; color: root.danger }
            opacity: 0
        }
        SequentialAnimation {
            id: pulseAnim
            NumberAnimation { target: pulse; property: "opacity"; to: 1; duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: pulse; property: "scale"; to: 1.25; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: pulse; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InQuad }
            }
            ScriptAction { script: peb.go() }
        }

        Text {
            anchors { top: circle.bottom; topMargin: 3; horizontalCenter: parent.horizontalCenter }
            width: parent.width + 8; horizontalAlignment: Text.AlignHCenter
            text: peb.armed ? peb.confirmText : peb.modelData.label; textFormat: Text.PlainText
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
            color: peb.armed ? Tokens.role.island.attention : peb.holding ? root.danger : Theme.subtext
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: tap
            onPressedChanged: {
                if (peb.fired) return
                if (pressed) {
                    peb.armed = false; armAnim.stop()
                    if (peb.confirm) { peb.holding = true; ring.tone = root.danger; ring.progress = 1; holdAnim.restart() }
                } else {
                    if (peb.holding) peb.cancel()
                    else if (!pulseAnim.running) peb.go()   // lock / sleep: a plain tap acts at once
                }
            }
        }
    }
}
