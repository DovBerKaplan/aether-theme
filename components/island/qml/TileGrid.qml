import QtQuick
import AetherShared
import "."

// The tile set. A tile is a rounded square of 1, 2 or 3 cells wide on a grid of 6 square cells, so every
// edge in every row falls on the same lines. Tiles take the first free spot, two rows make a page, and
// how many buttons fit follows their sizes. Normal: pages with dots when there is more than one.
// Editing: every tile is shown at once; drag one onto another to reorder, minus removes it, the corner
// badge changes its width, tap one under "Available" to add it. Every change is saved at once.
Item {
    id: root
    property bool editing: false
    signal panelRequested(string id)
    signal closeRequested()
    signal doneRequested()

    readonly property int cols: 6          // cells: a tile is 1, 2 or 3 cells wide and always one cell high, so a cell is a square
    readonly property int gap: 6
    readonly property int rowsPerPage: 2
    readonly property real unitW: (width - (cols - 1) * gap) / cols
    readonly property real cellH: unitW
    function spanW(span) { return span * unitW + (span - 1) * gap }
    function colX(c, span) { const x = c * (unitW + gap); return I18n.rtl ? width - spanW(span) - x : x }
    readonly property int count: work.count
    readonly property var available: {
        const used = {}
        for (let i = 0; i < work.count; ++i) used[work.get(i).tid] = true
        return tiles.catalog.filter(c => !used[c.id])
    }

    // Where every tile goes: [{ i, page, row, col, span }]. Each tile takes the first free spot (rows of `cols`
    // cells, `perPage` rows per page), so a hole left by a wide tile is filled by a later small one and two wide
    // tiles share a row when they can. Infinity rows = one long grid (editing).
    function place(perPage) {
        const out = []
        const used = {}                      // "page,row,col" -> true
        const free = (pg, r, c, span) => { for (let k = 0; k < span; ++k) if (used[pg + "," + r + "," + (c + k)]) return false; return true }
        for (let i = 0; i < work.count; ++i) {
            const span = work.get(i).size
            let done = false
            for (let pg = 0; !done; ++pg) {
                for (let r = 0; r < perPage && !done; ++r) {
                    for (let c = 0; c + span <= cols && !done; ++c) {
                        if (!free(pg, r, c, span)) continue
                        for (let k = 0; k < span; ++k) used[pg + "," + r + "," + (c + k)] = true
                        out.push({ i: i, page: pg, row: r, col: c, span: span })
                        done = true
                    }
                }
            }
        }
        return out
    }
    property var layout: []          // paged, for normal mode
    property var flat: []            // one grid, for editing
    function relayout() { layout = place(rowsPerPage); flat = place(1e9) }
    readonly property int pages: layout.reduce((m, t) => Math.max(m, t.page + 1), 1)
    readonly property int pageRows: {
        let m = 1
        for (const t of layout) m = Math.max(m, t.row + 1)
        return m
    }
    readonly property real pagerH: pageRows * cellH + (pageRows - 1) * gap
    readonly property int editRows: flat.reduce((m, t) => Math.max(m, t.row + 1), 1)
    readonly property real gridH: editRows * cellH + (editRows - 1) * gap

    implicitHeight: editing ? editCol.implicitHeight : pagerH + (pages > 1 ? 24 : 0)
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

    // The working copy of the order and sizes; the store is the saved one.
    ListModel { id: work }
    function load() {
        work.clear()
        const sizeOf = {}
        for (const e of tiles.sizes) sizeOf[e.split(":")[0]] = parseInt(e.split(":")[1])
        for (const id of tiles.order) work.append({ tid: id, size: sizeOf[id] || 1 })
        relayout()
    }
    function save() {
        const ids = [], sizes = []
        for (let i = 0; i < work.count; ++i) { ids.push(work.get(i).tid); if (work.get(i).size > 1) sizes.push(work.get(i).tid + ":" + work.get(i).size) }
        relayout()
        tiles.setLayout(ids, sizes)
    }
    function removeAt(i) { work.remove(i); save() }
    function addId(id) { work.append({ tid: id, size: 1 }); save() }   // see WidgetStack: the delegate dies with its row
    function cycleSize(i) { work.setProperty(i, "size", work.get(i).size % 3 + 1); save() }
    Component.onCompleted: load()
    Connections { target: tiles; function onOrderChanged() { if (!root.editing) root.load() } }
    onEditingChanged: if (!editing) load()

    // ---- normal mode: pages ------------------------------------------------------------
    ListView {
        id: pager
        visible: !root.editing
        width: parent.width; height: root.pagerH
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 240
        flickDeceleration: 6000
        boundsBehavior: Flickable.StopAtBounds
        interactive: false          // pages turn on our own, lower threshold (see the DragHandler below), not at half a page
        clip: true
        model: root.pages
        property real dragX: 0
        transform: Translate { x: pager.dragX; Behavior on x { enabled: !pageDrag.active; NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } } }
        delegate: Item {
            id: pageItem
            required property int index
            width: pager.width; height: pager.height
            Repeater {
                model: root.layout.filter(t => t.page === pageItem.index)
                delegate: Tile {
                    required property var modelData
                    tileId: work.get(modelData.i).tid
                    size: modelData.span
                    host: root
                    x: root.colX(modelData.col, modelData.span)
                    y: modelData.row * (root.cellH + root.gap)
                    width: root.spanW(modelData.span); height: root.cellH
                }
            }
        }
    }
    // Turning the page by hand: a short, slow drag is enough (28 px, or a flick), not half a page. The page
    // follows the finger a little, then the list moves on (or settles back) with its own animation.
    DragHandler {
        id: pageDrag
        enabled: !root.editing && root.pages > 1
        target: null
        xAxis.enabled: true; yAxis.enabled: false
        property real lastTx: 0
        onTranslationChanged: if (active) { lastTx = translation.x; pager.dragX = translation.x * 0.35 }
        onActiveChanged: {
            if (active) return
            const tx = lastTx, v = centroid.velocity.x       // the translation is already back at 0 once the drag is over
            lastTx = 0
            pager.dragX = 0
            if (Math.abs(tx) > 28 || Math.abs(v) > 220) {
                const dir = ((tx < 0 || (Math.abs(tx) <= 28 && v < 0)) !== I18n.rtl) ? 1 : -1
                pager.currentIndex = Math.max(0, Math.min(root.pages - 1, pager.currentIndex + dir))
            }
        }
    }
    Row {      // page dots: tap one to go to that page
        visible: !root.editing && root.pages > 1
        anchors { horizontalCenter: parent.horizontalCenter; top: pager.bottom; topMargin: 2 }
        Repeater {
            model: root.pages
            Item {
                required property int index
                width: (index === pager.currentIndex ? 16 : 7) + 14; height: 22
                Behavior on width { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 14; height: 6; radius: 3
                    color: index === pager.currentIndex ? Theme.text : Theme.subtext
                    opacity: index === pager.currentIndex ? 0.9 : 0.5
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pager.currentIndex = index }
            }
        }
    }

    // Two-finger swipe on the touchpad (or a sideways wheel): one step per gesture, not per event.
    WheelHandler {
        id: swipe
        orientation: Qt.Horizontal
        target: pager; enabled: root.pages > 1 && !root.editing
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        property bool cooling: false
        onWheel: (e) => {
            const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : 0
            if (d === 0) return
            if (cooling) { cool.restart(); return }
            acc += d
            if (Math.abs(acc) < 40) return
            const dir = (acc < 0) !== I18n.rtl ? 1 : -1
            pager.currentIndex = Math.max(0, Math.min(root.pages - 1, pager.currentIndex + dir))
            acc = 0; cooling = true; cool.restart()
        }
    }
    Timer { id: cool; interval: 280; onTriggered: { swipe.cooling = false; swipe.acc = 0 } }

    // ---- edit mode ----------------------------------------------------------------------
    // Nothing in edit mode may fall through to the island's click-outside-to-close area: a drag
    // released on a tile, or a tap on dead space, would fold the island mid-edit.
    MouseArea { visible: root.editing; anchors.fill: parent }
    Column {
        id: editCol
        visible: root.editing
        width: parent.width
        spacing: Tokens.space.md

        Item {
            id: gridArea
            width: parent.width; height: root.gridH
            property int target: -1            // index the dragged tile would take, -1 when none
            function rectOf(t) { return { x: root.colX(t.col, t.span), y: t.row * (root.cellH + root.gap), w: root.spanW(t.span), h: root.cellH } }
            function slotAt(px, py) {          // the tile under the pointer, else the nearest one
                let best = -1, bd = 1e12
                for (const t of root.flat) {
                    const r = rectOf(t)
                    const dx = Math.max(r.x - px, 0, px - (r.x + r.w)), dy = Math.max(r.y - py, 0, py - (r.y + r.h))
                    const d = dx * dx + dy * dy
                    if (d < bd) { bd = d; best = t.i }
                }
                return best
            }
            Rectangle {      // where the dragged tile will land
                visible: gridArea.target >= 0 && gridArea.target < root.flat.length
                readonly property var r: visible ? gridArea.rectOf(root.flat[gridArea.target]) : ({ x: 0, y: 0, w: 0, h: 0 })
                x: r.x; y: r.y; width: r.w; height: r.h; radius: Tokens.radius.xl
                color: "transparent"
                border { width: 2; color: Theme.accent }
                Behavior on x { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
                Behavior on y { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
            }
            Repeater {
                model: work
                delegate: Item {
                    id: slotItem
                    required property int index
                    required property string tid
                    required property int size
                    readonly property var cell: root.flat[index] || ({ row: 0, col: 0, span: 1 })
                    x: root.colX(cell.col, cell.span)
                    y: cell.row * (root.cellH + root.gap)
                    width: root.spanW(cell.span); height: root.cellH
                    z: held.dragging ? 10 : 0
                    Behavior on x { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                    Behavior on y { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                    Behavior on width { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

                    Item {
                        id: held
                        property bool dragging: drag.active
                        width: parent.width; height: parent.height
                        scale: dragging ? 1.06 : 1
                        opacity: dragging ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                        Behavior on x { enabled: !held.dragging; NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                        Behavior on y { enabled: !held.dragging; NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                        Tile { anchors.fill: parent; tileId: slotItem.tid; size: slotItem.size; host: root; editing: true }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton }
                        DragHandler {
                            id: drag
                            target: held
                            onActiveChanged: {
                                if (active) return
                                const to = gridArea.target
                                gridArea.target = -1
                                held.x = 0; held.y = 0
                                if (to >= 0 && to !== slotItem.index) { work.move(slotItem.index, to, 1); root.save() }
                            }
                            onTranslationChanged: if (active)
                                gridArea.target = gridArea.slotAt(slotItem.x + held.x + held.width / 2, slotItem.y + held.y + held.height / 2)
                        }
                        HoverHandler { cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                    }
                    Rectangle {      // remove badge
                        visible: root.count > 1 && !held.dragging
                        x: I18n.rtl ? -4 : parent.width - width + 4; y: -4
                        width: 20; height: 20; radius: 10
                        color: Theme.chip
                        border { width: 1; color: Theme.rim }
                        Glyph { anchors.centerIn: parent; name: "minus"; size: 12 }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.removeAt(slotItem.index) }
                    }
                    Rectangle {      // size badge: tap to go 1 -> 2 -> 3 cells wide and back; the shape inside shows the width
                        visible: !held.dragging
                        x: I18n.rtl ? parent.width - width + 4 : -4; y: -4
                        width: 20; height: 20; radius: 10
                        color: Theme.chip
                        border { width: 1; color: Theme.rim }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 4 + slotItem.size * 4; height: 7; radius: 2
                            color: "transparent"
                            border { width: 1.5; color: Theme.text }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.cycleSize(slotItem.index) }
                    }
                }
            }
        }

        SectionLabel { visible: root.available.length > 0; width: parent.width; text: I18n.tr("Available") }
        Flow {
            visible: root.available.length > 0
            width: parent.width
            spacing: Tokens.space.sm
            Repeater {
                model: root.available
                delegate: Rectangle {
                    required property var modelData
                    height: 34; width: chipRow.width + 2 * Tokens.space.md; radius: height / 2
                    color: Qt.rgba(1, 1, 1, addTap.pressed ? Tokens.tint.strong : addHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Glyph { name: "plus"; size: 12; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: modelData.label; textFormat: Text.PlainText
                            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                            color: Theme.text; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: addTap; onTapped: root.addId(modelData.id) }
                }
            }
        }
        Row {
            spacing: Tokens.space.sm
            Button { kind: "filled"; text: I18n.tr("Done"); onClicked: root.doneRequested() }
            Button { kind: "text"; text: I18n.tr("Reset"); onClicked: { tiles.reset(); root.load() } }
        }
    }
}
