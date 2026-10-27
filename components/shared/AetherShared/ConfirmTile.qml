import QtQuick
import QtQuick.Effects
import AetherShared

// Destructive-action tile: the first tap arms it (a ring drains over timeoutMs), the second
// tap acts; letting the ring run out cancels. Shift+click acts at once.
Item {
    id: root
    property string label
    property string confirmLabel
    property url glyphSource
    property bool needsConfirm: true
    property int timeoutMs: 5000
    property bool armed: false
    signal activated()

    implicitWidth: 96
    implicitHeight: 88
    activeFocusOnTab: true
    function disarm() { armed = false; drain.stop(); ring.progress = 0 }
    function press(immediate) {
        if (!needsConfirm || immediate || armed) { disarm(); activated() }
        else { armed = true; ring.progress = 1; drain.restart() }
    }
    Keys.onReturnPressed: press(false)
    Keys.onSpacePressed: press(false)

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.lg
        color: Theme.chip
        border { width: root.activeFocus ? 2 : 0; color: Theme.accent }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.material.tintAttention : hover.hovered ? Tokens.material.tintHover : 0)
        }
    }
    Canvas {
        id: ring
        property real progress: 0
        anchors.fill: parent
        visible: root.armed
        onProgressChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const r = Tokens.radius.lg, x0 = 1, y0 = 1, w = width - 2, h = height - 2
            const total = 2 * (w - 2 * r) + 2 * (h - 2 * r) + 2 * Math.PI * r
            ctx.strokeStyle = Theme.accent
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.setLineDash([total * progress, total])
            ctx.beginPath()
            ctx.moveTo(x0 + w / 2, y0)
            ctx.arcTo(x0 + w, y0, x0 + w, y0 + h, r)
            ctx.arcTo(x0 + w, y0 + h, x0, y0 + h, r)
            ctx.arcTo(x0, y0 + h, x0, y0, r)
            ctx.arcTo(x0, y0, x0 + w, y0, r)
            ctx.closePath()
            ctx.stroke()
        }
    }
    NumberAnimation { id: drain; target: ring; property: "progress"; from: 1; to: 0; duration: root.timeoutMs; onFinished: root.armed = false }

    Column {
        anchors.centerIn: parent
        spacing: Tokens.space.sm
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24; height: 24
            Image { id: g; anchors.fill: parent; source: root.glyphSource; sourceSize: Qt.size(72, 72); visible: false }
            MultiEffect { anchors.fill: g; source: g; colorization: 1.0; colorizationColor: root.armed ? Theme.accent : Theme.text }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.armed ? root.confirmLabel : root.label; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
            color: root.armed ? Theme.accent : Theme.text
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: (p, b) => root.press(false) }
    TapHandler { acceptedModifiers: Qt.ShiftModifier; onTapped: root.press(true) }
}
