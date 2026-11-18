import QtQuick
import AetherShared

// A divider between two panes: an accent line on hover, drag to resize, double-click to
// equalize its siblings. The drag is measured from where it started (against the tree as it
// was then), so a clamp at the minimum pane size never makes the divider drift.
Item {
    id: handle
    property var shell
    property string key
    readonly property var d: shell.dividerMap[key] || ({ x: 0, y: 0, w: 0, h: 0, dir: "row", extent: 1, path: [], i: 0 })
    readonly property bool horizontal: d.dir === "col"   // a "col" split's divider is a horizontal bar

    // a fat hit area around the visible hairline
    x: d.x - (horizontal ? 0 : 5); y: d.y - (horizontal ? 5 : 0)
    width: d.w + (horizontal ? 0 : 10); height: d.h + (horizontal ? 10 : 0)
    z: 5

    Rectangle {
        anchors.centerIn: parent
        width: handle.horizontal ? parent.width - 12 : (area.containsMouse || area.pressed ? 3 : 2)
        height: handle.horizontal ? (area.containsMouse || area.pressed ? 3 : 2) : parent.height - 12
        radius: 2
        color: Theme.accent
        opacity: area.pressed ? 0.9 : area.containsMouse ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: handle.horizontal ? Qt.SplitVCursor : Qt.SplitHCursor
        property real start: 0
        property var startTree: null
        function axis(m) { const p = mapToItem(handle.shell, m.x, m.y); return handle.horizontal ? p.y : p.x }
        onPressed: (m) => { start = axis(m); startTree = handle.shell.tree; handle.shell.resizing = true }
        onPositionChanged: (m) => {
            if (!pressed) return
            const dd = handle.d
            handle.shell.resizeTo(startTree, dd.path, dd.i, (axis(m) - start) / dd.extent, dd.extent)
        }
        onReleased: { handle.shell.resizing = false; handle.shell.saveLayout() }
        onDoubleClicked: handle.shell.equalizeAt(handle.d.path)
    }
}
