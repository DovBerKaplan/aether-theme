import QtQuick
import QtQuick.Shapes

// The selection: four white corner brackets around the chosen area. Drag a corner to resize,
// drag inside to move. `rect` is in the parent's coordinates; `bounds` keeps it on screen.
Item {
    id: root
    property rect rect: Qt.rect(0, 0, 0, 0)
    property size bounds: Qt.size(1920, 1080)
    property bool shown: false
    signal edited(rect r)

    x: rect.x; y: rect.y; width: rect.width; height: rect.height
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 1.06
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.38 } }

    readonly property real arm: Math.min(28, Math.min(width, height) / 2.2)

    component Corner: Shape {
        id: c
        property int sx: 1   // -1 mirrors horizontally
        property int sy: 1
        width: root.arm + 2; height: root.arm + 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "white"; strokeWidth: 4; fillColor: "transparent"
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            startX: c.sx > 0 ? 2 : c.width - 2; startY: c.sy > 0 ? c.height : 0
            PathLine { x: c.sx > 0 ? 2 : c.width - 2; y: c.sy > 0 ? 14 : c.height - 14 }
            PathArc {
                x: c.sx > 0 ? 14 : c.width - 14; y: c.sy > 0 ? 2 : c.height - 2
                radiusX: 12; radiusY: 12
                direction: c.sx * c.sy > 0 ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathLine { x: c.sx > 0 ? c.width : 0; y: c.sy > 0 ? 2 : c.height - 2 }
        }
    }
    Corner { x: -2; y: -2; sx: 1; sy: 1 }
    Corner { x: root.width - width + 2; y: -2; sx: -1; sy: 1 }
    Corner { x: -2; y: root.height - height + 2; sx: 1; sy: -1 }
    Corner { x: root.width - width + 2; y: root.height - height + 2; sx: -1; sy: -1 }

    function clampRect(r) {
        const w = Math.max(48, Math.min(r.width, bounds.width))
        const h = Math.max(48, Math.min(r.height, bounds.height))
        return Qt.rect(Math.max(0, Math.min(r.x, bounds.width - w)), Math.max(0, Math.min(r.y, bounds.height - h)), w, h)
    }

    // move
    MouseArea {
        anchors.fill: parent
        property point last
        cursorShape: Qt.SizeAllCursor
        onPressed: (m) => last = mapToItem(root.parent, m.x, m.y)
        onPositionChanged: (m) => {
            if (!pressed) return
            const p = mapToItem(root.parent, m.x, m.y)
            root.edited(root.clampRect(Qt.rect(root.rect.x + p.x - last.x, root.rect.y + p.y - last.y, root.rect.width, root.rect.height)))
            last = p
        }
    }
    // resize: one handle per corner
    Repeater {
        model: [ { hx: 0, hy: 0 }, { hx: 1, hy: 0 }, { hx: 0, hy: 1 }, { hx: 1, hy: 1 } ]
        MouseArea {
            required property var modelData
            width: 44; height: 44
            x: modelData.hx ? root.width - 30 : -14
            y: modelData.hy ? root.height - 30 : -14
            cursorShape: (modelData.hx === modelData.hy) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            property point last
            onPressed: (m) => last = mapToItem(root.parent, m.x, m.y)
            onPositionChanged: (m) => {
                if (!pressed) return
                const p = mapToItem(root.parent, m.x, m.y)
                const dx = p.x - last.x, dy = p.y - last.y
                const r = root.rect
                const x0 = modelData.hx ? r.x : r.x + dx
                const y0 = modelData.hy ? r.y : r.y + dy
                const x1 = modelData.hx ? r.x + r.width + dx : r.x + r.width
                const y1 = modelData.hy ? r.y + r.height + dy : r.y + r.height
                root.edited(root.clampRect(Qt.rect(Math.min(x0, x1 - 48), Math.min(y0, y1 - 48),
                                                   Math.max(48, x1 - x0), Math.max(48, y1 - y0))))
                last = p
            }
        }
    }
}
