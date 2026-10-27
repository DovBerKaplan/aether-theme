import QtQuick
import AetherShared

// A thin ring that fills clockwise from the top, with the number inside. Numbers are mono.
// Charging is shown by a tiny bolt, not by colouring the ring (accent stays rare).
Item {
    id: root
    property int percent: -1          // -1 = unknown
    property bool charging: false
    property real ringWidth: 3
    property bool showNumber: true
    implicitWidth: 40
    implicitHeight: 40

    Canvas {
        id: ring
        anchors.fill: parent
        property real p: root.percent < 0 ? 0 : root.percent / 100
        onPChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const r = (Math.min(width, height) - root.ringWidth) / 2, cx = width / 2, cy = height / 2
            ctx.lineWidth = root.ringWidth
            ctx.lineCap = "round"
            ctx.strokeStyle = Qt.rgba(1, 1, 1, Tokens.tint.soft)
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()
            if (p > 0) {
                ctx.strokeStyle = Theme.text
                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.stroke()
            }
        }
        Behavior on p { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.enter } }
    }
    Text {
        visible: root.showNumber
        anchors.centerIn: parent
        text: root.percent < 0 ? "–" : root.percent
        font { family: Theme.mono; pixelSize: root.width >= 52 ? Tokens.type.body : Tokens.type.caption; weight: Font.Medium }
        color: Theme.text
    }
    Glyph {
        visible: root.charging
        size: 11
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -1 }
        name: "bolt"
        color: Theme.text
    }
}
