import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import AetherShared
import "."
import "SplitModel.js" as SM

// Aether Console - the connection shelf, a glass column on the right edge.
//   at rest  only a quiet "ear" at the top-right corner (hover or click opens; Meta+C, D-Bus)
//   open     the shelf slides out with the island's jelly spring; SSH, containers and pods in
//            one list; a tap connects - into tmux on the server, so nothing is ever lost
//   split    tabs live in panes: long-press a tab and drop it on a pane's edge to split, on its
//            middle to move it; dividers resize, the shelf's left edge widens the whole glass
//
// The window is exactly as wide as the glass (the dock's way): the rest of the screen stays
// free. The input mask decides what is really clickable and follows the same path QML draws
// (setLayout); the holes cut for seated terminal windows are part of it.
Workspace {
    id: root

    readonly property int pwList: 400             // the list alone
    readonly property int pwDetail: 640           // one pane with a card, terminal or files
    readonly property int pwSplit: 960            // two or more panes
    readonly property real rad: 26                // every corner - the glass floats, dock-style
    readonly property real edgeGap: 14            // the dock's rest distance from the edges
    readonly property real shelfY: edgeGap
    readonly property real shelfH: height - 2 * edgeGap

    // ---------- the shelf's width ----------
    // list alone: 400. one pane: 640. split: 960. The left edge's handle overrides all of them
    // (saved), except for the bare list, which has nothing to widen for.
    readonly property real availW: ctl.screenWidth - 2 * edgeGap
    property real shelfPref: 0                    // the user's own width (0 = automatic), saved
    property bool widthDrag: false
    function setShelfWidth(w) {
        const floor = Math.max(pwList, SM.minSize(tree, "row", gap) + (groupIds.length > 1 ? 16 : 0))
        shelfPref = Math.round(Math.max(floor, Math.min(availW, w)))
    }
    readonly property bool listOnly: groupIds.length === 1 && focusKind === "home"
    readonly property int pwAuto: groupIds.length > 1 ? Math.min(pwSplit, availW) : (focusKind === "home" ? pwList : pwDetail)
    readonly property int pw: listOnly ? pwList
                                      : Math.round(shelfPref > 0 ? Math.max(pwList, Math.min(availW, shelfPref)) : pwAuto)
    // the window is exactly as wide as its content needs: the rest of the screen stays free
    property real gw: pw                       // sprung glass width
    Behavior on gw { enabled: !root.widthDrag; SpringAnimation { spring: 3.6; damping: 0.22; epsilon: 3 } }
    property real slide: open ? 0 : gw + 24    // 0 = hugging the window's right edge
    Behavior on slide {
        enabled: true
        SpringAnimation { spring: 3.6; damping: root.open ? 0.22 : 0.36; epsilon: 3 }
    }
    readonly property bool panelIn: slide < gw / 2
    // terminals are placed only once the glass has stopped moving (see TermView.place)
    readonly property bool settled: Math.abs(gw - pw) < 1 && Math.abs(root.width - (pw + edgeGap)) < 1 && Math.abs(slide) < 1
    property real closedAt: 0
    onSlideChanged: {
        report()
        // keep the window wide until the glass has fully slid out, then shrink to the ear strip
        if (!open && slide > gw + 20 && root.width > 64) ctl.setWindowSize(64, ctl.screenHeight)
    }
    onGwChanged: report()
    onPwChanged: if (open) ctl.setWindowSize(pw + edgeGap, ctl.screenHeight)
    onOpenChanged: {
        closedAt = open ? 0 : Date.now()
        ctl.setKeyboard(open)
        discovery.setPolling(open)
        if (open) ctl.setWindowSize(pw + edgeGap, ctl.screenHeight)
        else { content.page = "none"; menuGid = ""; cancelDrag() }   // the width shrinks when the slide settles
        report()
    }
    onWidthChanged: report()

    // The island's accent colour and language flow in through the controller's file watch -
    // a colour picked in the bar tints this shelf the same way.
    Binding { target: Theme; property: "accentOverride"; value: ctl.accent }
    Binding { target: Theme; property: "accentTint"; value: 0.07 }
    Binding { target: I18n; property: "lang"; value: ctl.lang }

    Component.onCompleted: {
        ctl.setWindowSize(64, ctl.screenHeight)   // the resting ear strip
        refreshStructure()
        report()
        rebuild()
        shelfPref = Number(ctl.setting("ShelfWidth")) || 0
        if (testDetail.length === 0) restoreLayout()
        if (testDetail.length > 0) {
            root.open = true
        }
    }
    Connections {
        target: ctl
        function onStateRequested(state) {
            if (state === "shown" || (state === "toggle" && !root.open)) root.open = true
            else root.open = false
        }
        // a terminal window got the keyboard (the user clicked into it): its pane is the focused one
        function onSeatFocused(pid) {
            for (const id in root.seats) if (root.seats[id] === pid) { const g = root.groupOf(id); if (g) root.focusGroup = g }
        }
        function onSeatClosed(pid) {
            const d = Object.assign({}, root.downIds)
            for (const id in root.seats) if (root.seats[id] === pid) d[id] = true
            root.downIds = d
        }
    }
    Connections {
        target: store
        function onSessionsChanged() { rebuild() }
    }
    Connections {
        target: discovery
        function onContainersChanged() { rebuild() }
        function onPodsChanged() { rebuild() }
        function onContextsChanged() { rebuild() }
        function onContextChanged() { rebuild() }
    }

    overlayOpen: content.page !== "none"
    areaW: workArea.width
    areaH: workArea.height
    mapToArea: (x, y) => workArea.mapFromItem(root, x, y)
    onReportRequested: report()
    onMenuGidChanged: report()
    onCloseOverlay: content.page = "none"
    readonly property var shelfItem: shelf
    function report() {
        if (panelIn) {
            // the holes are shelf-local; the input mask and blur want window coordinates
            const holeList = []
            for (const id in holes) {
                const h = holes[id]
                holeList.push({ x: h.x + shelf.x, y: h.y + shelf.y, w: h.w, h: h.h })
            }
            ctl.setLayout(panelCmds(root.width - root.edgeGap - root.gw + root.slide,
                                    root.shelfY, root.gw, root.shelfH, root.rad),
                          Qt.rect(0, 0, 0, 0), false, holeList, menuGid !== "")
        } else if (!ctl.earShown) {
            ctl.setLayout([], Qt.rect(0, 0, 0, 0), false)   // the resting tab is switched off: nothing to see or touch
        } else {
            ctl.setLayout(earCmds(), Qt.rect(root.width - 14, ear.y - 10, 16, ear.height + 20), false)
        }
    }
    Connections { target: ctl; function onEarShownChanged() { root.report() } }
    // The floating panel silhouette: rounded at all four corners.
    function panelCmds(x, y, w, h, r) {
        return [
            { t: "M", x: x + r, y: y },
            { t: "L", x: x + w - r, y: y },
            { t: "C", x: x + w, y: y + r, x1: x + w, y1: y, x2: x + w, y2: y + r },
            { t: "L", x: x + w, y: y + h - r },
            { t: "C", x: x + w - r, y: y + h, x1: x + w, y1: y + h, x2: x + w - r, y2: y + h },
            { t: "L", x: x + r, y: y + h },
            { t: "C", x: x, y: y + h - r, x1: x, y1: y + h, x2: x, y2: y + h - r },
            { t: "L", x: x, y: y + r },
            { t: "C", x: x + r, y: y, x1: x, y1: y, x2: x + r, y2: y },
        ]
    }
    function earCmds() {
        const x = root.width - ear.visW
        return [{ t: "M", x: x, y: ear.y }, { t: "L", x: x + ear.visW, y: ear.y },
                { t: "L", x: x + ear.visW, y: ear.y + ear.height }, { t: "L", x: x, y: ear.y + ear.height }]
    }
    function yFromRatio(r) {
        const minY = root.edgeGap, maxY = root.height - 72 - root.edgeGap
        return minY + (maxY - minY) * Math.min(1, Math.max(0, r))
    }
    function ratioFromY(y) {
        const minY = root.edgeGap, maxY = root.height - 72 - root.edgeGap
        return Math.min(1, Math.max(0, (y - minY) / Math.max(1, maxY - minY)))
    }

    function openEditor(s) { editorPage.begin(s); content.page = "editor" }
    function openImport() { importPage.reload(); content.page = "import" }

    // ---------- the resting tab: the phone's Smart-Sidebar handle, in our glass ----------
    // A thin capsule hugging the right edge in the screen's upper quarter (drag it along the
    // edge - the position is saved), pull it inward to open the drawer, or click / hover it.
    Rectangle {
        id: ear
        visible: !root.panelIn && ctl.earShown
        // visW is what shows; the shape runs 6px past the screen edge, so only its inner side is
        // rounded and rimmed - a tab growing out of the edge, not a floating capsule
        readonly property real visW: 8
        x: root.width - visW + pull
        y: root.yFromRatio(ctl.tabRatio)
        width: visW + 6; height: 72; radius: visW / 2
        // the tab lives directly on the desktop, so it is a single translucent shape that reads
        // on either scheme: a pale veil with a pale rim on dark, an ink veil with an ink rim on
        // light. Hover or a drag firms the veil up.
        readonly property bool lit: earHover.hovered || tabDrag.active
        color: ctl.underLight ? Qt.rgba(0.12, 0.14, 0.19, lit ? 0.75 : 0.55)
                              : Qt.rgba(1, 1, 1, lit ? 0.35 : 0.2)
        border {
            width: ctl.underLight ? 1.5 : 2
            color: ctl.underLight ? Qt.rgba(0.12, 0.14, 0.19, 0.75) : Qt.rgba(1, 1, 1, 0.55)
        }
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
        Behavior on border.width { NumberAnimation { duration: Tokens.motion.duration.micro } }
        Behavior on border.color { ColorAnimation { duration: Tokens.motion.duration.base } }
        transform: Scale {
            xScale: 1 + Math.min(0.6, Math.abs(ear.pull) / 50)
            origin.x: ear.visW; origin.y: ear.height / 2   // stretches leftward from the edge
        }
        // look at what is beside the tab and dress to it; only while it rests, a few times a second
        Timer {
            interval: 700; repeat: true; triggeredOnStart: true
            running: ear.visible && !tabDrag.active
            onTriggered: ctl.sampleUnder(ear.y, ear.height)
        }
        // the pull follows the finger 1:1; on release it springs back with the button family
        property real pull: 0
        Behavior on pull {
            enabled: !tabDrag.active
            SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 }
        }
        HoverHandler { id: earHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) peek.restart() }
        onYChanged: if (!root.panelIn) report()   // the input mask rides the tab while it is dragged
        TapHandler { onTapped: root.open = true }
        DragHandler {
            id: tabDrag
            target: null
            property string axis: ""
            property real startY: 0
            onActiveChanged: {
                if (active) {
                    axis = ""
                    startY = ear.y
                } else {
                    if (axis === "y") ctl.setTabRatio(root.ratioFromY(ear.y))
                    ear.pull = 0
                }
            }
            onTranslationChanged: {
                if (axis === "") {
                    if (Math.abs(translation.x) < 6 && Math.abs(translation.y) < 6) return
                    axis = Math.abs(translation.x) >= Math.abs(translation.y) ? "x" : "y"
                }
                if (axis === "x") {
                    ear.pull = Math.max(-44, Math.min(0, translation.x))
                    if (translation.x < -14) {   // the drawer takes over; the spring lands it
                        axis = "done"
                        ear.pull = 0
                        root.open = true
                    }
                } else if (axis === "y") {
                    const maxY = root.height - ear.height - root.edgeGap
                    ear.y = Math.max(root.edgeGap, Math.min(maxY, startY + translation.y))
                }
            }
        }
        // a fast swipe across the edge must not flash the shelf; and right after a deliberate
        // close the pointer is still near - give it 800ms of grace before hover counts again
        Timer { id: peek; interval: 240; onTriggered: if (Date.now() - root.closedAt > 800) root.open = true }
    }

    // ---------- the shelf ----------
    // No click-outside: the window is only as wide as the glass, so clicks to its left belong
    // to the apps living there (that is the point). Close with Esc, Win+C or the list's close
    // button.
    Item {
        id: shelf
        x: root.width - root.edgeGap - root.gw + root.slide
        y: root.shelfY; width: root.gw; height: root.shelfH
        clip: true

        TapHandler { onTapped: (e) => e.accepted = true }   // the glass eats its own clicks

        Shape {
            id: glass
            anchors.fill: parent
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.rim
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: 1
                    GradientStop { position: 0; color: Theme.bodyTop }
                    GradientStop { position: 1; color: Theme.bodyBottom }
                }
                startX: root.rad; startY: 0
                PathLine { x: glass.width - root.rad; y: 0 }
                PathQuad { x: glass.width; y: root.rad; controlX: glass.width; controlY: 0 }
                PathLine { x: glass.width; y: glass.height - root.rad }
                PathQuad { x: glass.width - root.rad; y: glass.height; controlX: glass.width; controlY: glass.height }
                PathLine { x: root.rad; y: glass.height }
                PathQuad { x: 0; y: glass.height - root.rad; controlX: 0; controlY: glass.height }
                PathLine { x: 0; y: root.rad }
                PathQuad { x: root.rad; y: 0; controlX: 0; controlY: 0 }
                // the seated terminals live in windows BELOW this one: cut them out of the painted
                // glass too (not only blur and input), or the gradient veils them
                PathSvg { path: root.holesSvg }
            }
        }
        Shape {
            id: glassMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            ShapePath {
                fillColor: "#fff"
                fillRule: ShapePath.OddEvenFill
                startX: root.rad; startY: 0
                PathLine { x: glassMask.width - root.rad; y: 0 }
                PathQuad { x: glassMask.width; y: root.rad; controlX: glassMask.width; controlY: 0 }
                PathLine { x: glassMask.width; y: glassMask.height - root.rad }
                PathQuad { x: glassMask.width - root.rad; y: glassMask.height; controlX: glassMask.width; controlY: glassMask.height }
                PathLine { x: root.rad; y: glassMask.height }
                PathQuad { x: 0; y: glassMask.height - root.rad; controlX: 0; controlY: glassMask.height }
                PathLine { x: 0; y: root.rad }
                PathQuad { x: root.rad; y: 0; controlX: 0; controlY: 0 }
                PathSvg { path: root.holesSvg }
            }
        }
        Image {
            id: grain
            anchors.fill: parent
            source: Theme.grain
            fillMode: Image.Tile
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: grain
            maskEnabled: true
            maskSource: glassMask
            opacity: Tokens.material.grainOpacity
        }

        Item {
            id: content
            property string page: "none"   // modal overlays only: editor / import
            anchors.fill: parent

            // the panes: one flat list positioned from the split tree, dividers on top
            Item {
                id: workArea
                anchors { fill: parent; margins: root.groupIds.length > 1 ? 8 : 0 }
                Repeater {
                    model: root.groupIds
                    Pane {
                        required property string modelData
                        readonly property var r: root.rects[modelData] || ({ x: 0, y: 0, w: 0, h: 0 })
                        shell: root
                        gid: modelData
                        visible: root.rects[modelData] !== undefined
                        x: r.x; y: r.y; width: r.w; height: r.h
                    }
                }
                Repeater {
                    model: root.dividerKeys
                    SplitHandle { required property string modelData; shell: root; key: modelData }
                }
                // where a dragged tab would land
                Rectangle {
                    id: preview
                    readonly property var r: root.rects[root.dropGid] || ({ x: 0, y: 0, w: 0, h: 0 })
                    visible: root.dragTab !== "" && root.dropGid !== ""
                    z: 50
                    x: r.x + (root.dropZone === "right" ? r.w / 2 : 0)
                    y: r.y + (root.dropZone === "bottom" ? r.h / 2 : 0)
                    width: (root.dropZone === "left" || root.dropZone === "right") ? r.w / 2 : r.w
                    height: (root.dropZone === "top" || root.dropZone === "bottom") ? r.h / 2 : r.h
                    radius: 14
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                    border { width: 2; color: Theme.accent }
                    Behavior on x { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Easing.OutCubic } }
                }
            }

            SessionEditor {
                id: editorPage
                anchors.fill: parent
                maxHeight: root.shelfH
                opacity: content.page === "editor" ? 1 : 0
                enabled: content.page === "editor"
                visible: opacity > 0.01
                onSaved: content.page = "none"
                onBackRequested: content.page = "none"
            }
            ImportPage {
                id: importPage
                anchors.fill: parent
                maxHeight: root.shelfH
                opacity: content.page === "import" ? 1 : 0
                enabled: content.page === "import"
                visible: opacity > 0.01
                onBackRequested: content.page = "none"
            }
        }
    }

    // the glass's left edge: drag to widen or narrow the whole shelf, double-click for automatic
    MouseArea {
        id: widthHandle
        visible: root.panelIn && !root.listOnly
        x: shelf.x; y: shelf.y + root.rad      // the glass touches the window's edge: stay inside it
        width: 8; height: shelf.height - 2 * root.rad
        z: 150
        cursorShape: Qt.SplitHCursor
        preventStealing: true
        property real startX: 0
        property real startW: 0
        // the screen x of the pointer: the window hangs on the right edge and widens as the glass does,
        // so its own x grows with it (mapToGlobal would report window-local numbers on layer-shell)
        function screenX(m) { return ctl.screenWidth - root.width + mapToItem(root, m.x, m.y).x }
        onPressed: (m) => { startX = screenX(m); startW = root.pw; root.widthDrag = true }
        onPositionChanged: (m) => { if (pressed) root.setShelfWidth(startW + startX - screenX(m)) }
        onReleased: { root.widthDrag = false; ctl.setSetting("ShelfWidth", String(root.shelfPref)) }
        onDoubleClicked: { root.shelfPref = 0; ctl.setSetting("ShelfWidth", "0") }
        Rectangle {
            anchors.centerIn: parent
            width: 3; height: 56; radius: 2
            color: Theme.accent
            opacity: widthHandle.pressed ? 0.9 : widthHandle.containsMouse ? 0.6 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        }
        hoverEnabled: true
    }

    PaneMenu { shell: root }
    Fixtures { id: fixtures; shell: root }

    // the picked-up tab follows the pointer
    Rectangle {
        visible: root.dragTab !== ""
        z: 300
        readonly property var t: root.tabById(root.dragTab) || ({ title: "" })
        x: root.dragPos.x - width / 2; y: root.dragPos.y - height - 6
        width: ghostText.width + 28; height: 30; radius: 10
        color: Qt.rgba(Theme.bodyBottom.r, Theme.bodyBottom.g, Theme.bodyBottom.b, 1)
        border { width: 1.5; color: Theme.accent }
        Text {
            id: ghostText
            anchors.centerIn: parent
            width: Math.min(160, implicitWidth)
            elide: Text.ElideRight
            text: parent.t.title
            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
            color: Theme.text
        }
    }
}
