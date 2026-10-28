import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import AetherShared

// The dock: one glass pill per screen edge ("bottom" or "left", set by the host). Hidden at rest:
// the window is then a 2px invisible strip that only listens for the pointer. Touching it
// springs the pill out of the edge in the island's material; leaving retracts it.
Item {
    id: root
    // Icon order is fixed (pinned first, left to right / top to bottom) whatever the UI locale.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property bool horiz: dock.edge === "bottom"
    readonly property int iconSize: Tokens.dock.icon
    readonly property int cell: iconSize + 2 * Tokens.dock.cellInset
    readonly property int gap: Tokens.dock.gap
    readonly property int pad: Tokens.dock.pad        // glass inset around the icons
    readonly property int margin: 10     // clear space between pill and screen edge
    readonly property int sepExtra: Tokens.dock.sepExtra   // extra air around the pinned | running separator
    readonly property real thickness: cell + 2 * pad
    readonly property real along: grid.implicitLength + allCell.reserve + 2 * pad   // pill length along the edge
    readonly property real radius: Tokens.dock.radius

    // Material: the island's glass (gradient body, hairline rim, grain), tuned per scheme - a touch
    // denser and rougher in dark mode, lighter, smoother and clearer in light mode.
    readonly property bool dark: dock.dark
    readonly property color ink: dark ? Theme.text : Tokens.palette.graphite950
    // Light mode is a white veil over the blur, nothing darker: clear, frosted, with a light rim.
    readonly property color bodyTop: dark ? Qt.alpha(Tokens.palette.ink750, Tokens.material.dockAlphaDark)
                                          : Qt.rgba(0.95, 0.96, 0.99, Tokens.material.dockAlphaLight)
    readonly property color bodyBottom: dark ? Qt.alpha(Tokens.palette.ink850, Tokens.material.dockAlphaDark)
                                             : Qt.rgba(0.90, 0.92, 0.97, Tokens.material.dockAlphaLight * 0.8)
    readonly property color rim: dark ? Theme.rim : Qt.rgba(0.42, 0.48, 0.60, 0.28)   // cool grey hairline: shows on white and on dark
    readonly property real grainOpacity: dark ? Tokens.material.dockGrainDark : Tokens.material.dockGrainLight

    property bool shown: false
    property bool pointerIn: false
    readonly property bool holdOpen: menuOn || drag.active || allCell.holding

    // ---- Jelly motion ---------------------------------------------------------------
    // Everything is drawn in (u, v): u runs along the screen edge, v is the distance from it.
    // `d` is the gap between the screen edge and the pill's near side; an under-damped spring
    // drives it, so the pill overshoots and wobbles. The speed stretches the glass along v and
    // squeezes it along u (squash and stretch). While the pill is within `neckMax` of the edge it
    // stays joined to it by a concave neck that thins as the pill leaves and pinches off, the way
    // the island's notch merges with the top edge; coming back, it fuses again.
    readonly property real restD: 14
    readonly property real neckMax: 46
    property real conn: 1          // 1 = the glass is tied to the edge, 0 = free; eases separately from `d`
    Behavior on conn { NumberAnimation { duration: root.shown ? 360 : 220; easing.type: Easing.InOutQuad } }
    readonly property real hiddenD: -thickness - 8
    readonly property real popupRoom: 300                       // transparent room for the tooltip and the menu
    readonly property real vWin: thickness + restD + 36 + popupRoom   // + room for the overshoot
    readonly property real uPad: 14                            // room for the neck's flares
    property real d: hiddenD
    property real vel: 0
    property real lastD: hiddenD
    property real lastT: 0
    Behavior on d {
        SpringAnimation {
            spring: 3.6                              // the island's own spring
            damping: root.shown ? 0.22 : 0.36
            mass: 1
            epsilon: 0.3
        }
    }
    onDChanged: {
        const now = Date.now()
        const dt = Math.max(1, now - lastT)
        if (lastT > 0 && dt < 80) vel = vel * 0.5 + 0.5 * (d - lastD) / dt * 16
        lastD = d; lastT = now
    }
    onShownChanged: {
        d = shown ? restD : hiddenD; conn = shown ? 0 : 1
        if (!shown) { menuOn = false; tipOn = false }
    }
    readonly property real stretch: Math.max(-0.3, Math.min(0.3, vel * 0.012))

    // ---- Window geometry: strip while hidden, pill-sized while shown or moving ------------
    readonly property bool open: shown || d > hiddenD + 2
    readonly property real lWin: along + 2 * uPad
    function applyWindow() {
        const w = open ? (horiz ? Math.ceil(lWin) : vWin) : (horiz ? dock.screenWidth : 10)
        const h = open ? (horiz ? vWin : Math.ceil(lWin)) : (horiz ? 10 : dock.screenHeight)
        dock.setWindowSize(w, h)
    }
    onOpenChanged: applyWindow()
    onLWinChanged: if (open) applyWindow()
    Component.onCompleted: { applyWindow(); reorder() }

    // Window coordinates of (u, v).
    function px(u, v) { return horiz ? u : v }
    function py(u, v) { return horiz ? vWin - v : u }

    // The silhouette: pill + (while close to the edge) the neck, as one closed outline.
    readonly property var segments: {
        const K = 0.5523
        const T = thickness * (1 + Math.abs(stretch)), L = along * (1 - Math.abs(stretch) * 0.4)
        const c = uPad + along / 2
        const uL = c - L / 2, uR = c + L / 2
        const R = Math.min(radius, T / 2)
        const dd = d, dN = dd + T
        if (dN <= 0) return []
        const k = dd >= 0 && dd < neckMax ? conn * (1 - dd / neckMax) : 0   // 1 = fused with the edge, 0 = detached
        const hw = 34 * k
        const out = []
        function M(u, v) { out.push({ t: "M", x: px(u, v), y: py(u, v) }) }
        function Ln(u, v) { out.push({ t: "L", x: px(u, v), y: py(u, v) }) }
        function C(u1, v1, u2, v2, u, v) {
            out.push({ t: "C", x1: px(u1, v1), y1: py(u1, v1), x2: px(u2, v2), y2: py(u2, v2), x: px(u, v), y: py(u, v) })
        }
        if (hw > 2) {
            const se = Math.min(10 * k, dd / 2, 12)
            const cl = c - hw, cr = c + hw
            M(cl - se, 0)
            C(cl - se + K * se, 0, cl, se - K * se, cl, se)
            Ln(cl, dd - se)
            C(cl, dd - se + K * se, cl - se + K * se, dd, cl - se, dd)
            Ln(uL + R, dd)
            C(uL + R - K * R, dd, uL, dd + R - K * R, uL, dd + R)
            Ln(uL, dN - R)
            C(uL, dN - R + K * R, uL + R - K * R, dN, uL + R, dN)
            Ln(uR - R, dN)
            C(uR - R + K * R, dN, uR, dN - R + K * R, uR, dN - R)
            Ln(uR, dd + R)
            C(uR, dd + R - K * R, uR - R + K * R, dd, uR - R, dd)
            Ln(cr + se, dd)
            C(cr + se - K * se, dd, cr, dd - se + K * se, cr, dd - se)
            Ln(cr, se)
            C(cr, se - K * se, cr + se - K * se, 0, cr + se, 0)
        } else {
            M(uL + R, dd)
            C(uL + R - K * R, dd, uL, dd + R - K * R, uL, dd + R)
            Ln(uL, dN - R)
            C(uL, dN - R + K * R, uL + R - K * R, dN, uL + R, dN)
            Ln(uR - R, dN)
            C(uR - R + K * R, dN, uR, dN - R + K * R, uR, dN - R)
            Ln(uR, dd + R)
            C(uR, dd + R - K * R, uR - R + K * R, dd, uR - R, dd)
        }
        return out
    }
    function svg(cmds) {
        let s = ""
        for (const c of cmds) {
            if (c.t === "M") s += "M " + c.x + " " + c.y + " "
            else if (c.t === "L") s += "L " + c.x + " " + c.y + " "
            else s += "C " + c.x1 + " " + c.y1 + " " + c.x2 + " " + c.y2 + " " + c.x + " " + c.y + " "
        }
        return s + "Z"
    }
    readonly property string outline: svg(segments)
    readonly property rect hotRect: open ? (horiz ? Qt.rect(0, vWin - 2, lWin, 2) : Qt.rect(0, 0, 2, lWin))
                                         : (horiz ? Qt.rect(0, height - 2, width, 2) : Qt.rect(0, 0, 2, height))   // input only on the 2px edge strip
    function report() { dock.setLayout(segments, hotRect, popupRects) }
    onSegmentsChanged: report()
    onHotRectChanged: report()
    onPopupRectsChanged: report()

    function setShown(s) {
        if (s === shown) return
        peekTimer.stop(); leaveTimer.stop()
        shown = s
        if (s) dock.notifyShown()
    }
    Connections {
        target: dock
        function onStateRequested(state) { root.setShown(state === "shown") }
    }

    HoverHandler {
        onHoveredChanged: {
            root.pointerIn = hovered
            if (hovered) {
                leaveTimer.stop()
                if (!root.shown) peekTimer.restart()
            } else {
                peekTimer.stop()
                if (root.shown) leaveTimer.restart()
            }
        }
    }
    Timer { id: peekTimer; interval: 140; onTriggered: if (root.pointerIn) root.setShown(true) }
    Timer {
        id: leaveTimer
        interval: 600
        onTriggered: {
            if (root.pointerIn || root.holdOpen) leaveTimer.restart()
            else root.setShown(false)
        }
    }

    // Edge hint, like a phone's home indicator: a tiny, very faint line where the dock lives, gone as
    // the pill comes out.
    Rectangle {
        width: root.horiz ? 34 : 2
        height: root.horiz ? 2 : 34
        radius: 1
        x: root.horiz ? (root.width - width) / 2 : 6
        y: root.horiz ? root.height - 8 : (root.height - height) / 2   // inset from the edge
        color: root.ink
        opacity: root.shown || root.open ? 0 : 0.22
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Home indicator: the bar's quiet grab line, just inside the screen edge while the bar is out.
    Rectangle {
        readonly property real len: Math.round(root.along * Tokens.dock.homeW)
        width: root.horiz ? len : Tokens.dock.homeH
        height: root.horiz ? Tokens.dock.homeH : len
        radius: Tokens.dock.homeH / 2
        x: root.horiz ? root.uPad + (root.along - len) / 2 : Tokens.dock.homeInset
        y: root.horiz ? root.vWin - Tokens.dock.homeInset - height : root.uPad + (root.along - len) / 2
        color: root.dark ? Theme.text : "white"
        opacity: root.shown ? (root.dark ? 0.45 : 0.9) : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    }

    // ---- Tasks -------------------------------------------------------------------
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        // Not filterHidden: on Wayland "hidden" includes minimized windows, which would drop a
        // minimized app back to a bare launcher with nothing to restore. Skip-taskbar windows
        // (the media window, panels) stay out regardless.
        filterHidden: false
        filterMinimized: false
        filterByVirtualDesktop: false
        separateLaunchers: false
        sortMode: TaskManager.TasksModel.SortManual
        launcherList: dock.launchers
    }
    property int rev: 0     // delegates re-read the model on every change
    Connections {
        target: tasks
        function onCountChanged() { root.rev++ }
        function onDataChanged() { root.rev++ }
        function onActiveTaskChanged() { root.rev++ }
        function onLauncherListChanged() { root.rev++ }
    }
    function row(i) { return tasks.index(i, 0) }
    function role(i, r) { root.rev; const idx = row(i); return idx.valid ? tasks.data(idx, r) : undefined }
    function isWindow(i) { return role(i, TaskManager.AbstractTasksModel.IsWindow) === true }
    function isActive(i) { return role(i, TaskManager.AbstractTasksModel.IsActive) === true }
    function isMinimized(i) { return role(i, TaskManager.AbstractTasksModel.IsMinimized) === true }
    function isStartup(i) { return role(i, TaskManager.AbstractTasksModel.IsStartup) === true }
    function baseOf(u) { const s = String(u); return s.slice(Math.max(s.lastIndexOf("/"), s.lastIndexOf(":")) + 1) }
    function launcherBase(i) { return baseOf(role(i, TaskManager.AbstractTasksModel.LauncherUrl)) }
    function pinnedHas(base) { for (const u of tasks.launcherList) if (baseOf(u) === base) return true; return false }

    // The model keeps insertion order (idle launchers first, then windows as they appeared), so the
    // dock orders the rows itself: pinned apps in pin order, then free windows. `order` holds model rows.
    function pinPos(base) {
        const l = tasks.launcherList
        for (let i = 0; i < l.length; i++) if (baseOf(l[i]) === base) return i
        return -1
    }
    property var order: []
    property int firstFree: -1      // position in `order` of the first free window
    onRevChanged: reorder()
    function reorder() {
        const pinned = [], free = []
        for (let i = 0; i < tasks.count; i++) {
            const p = pinPos(launcherBase(i))
            if (p >= 0) pinned.push({ i: i, p: p }); else free.push(i)
        }
        pinned.sort((a, b) => a.p - b.p)
        const o = pinned.map(x => x.i).concat(free)
        const ff = free.length > 0 && pinned.length > 0 ? pinned.length : -1
        if (JSON.stringify(o) !== JSON.stringify(order)) order = o
        if (ff !== firstFree) firstFree = ff
    }
    // Three dots at the end of the dock: minimize every window; once all are down, bring them back.
    function minimizeAll() {
        let up = []
        for (let i = 0; i < tasks.count; i++) if (isWindow(i) && !isMinimized(i)) up.push(i)
        const targets = []
        if (up.length > 0) targets.push(...up)
        else for (let i = 0; i < tasks.count; i++) if (isWindow(i)) targets.push(i)
        for (const i of targets) tasks.requestToggleMinimized(row(i))
    }
    function savePins() { dock.launchers = tasks.launcherList }

    // ---- The glass: the island's material on the silhouette --------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.horiz ? 0 : root.width; y2: root.horiz ? root.height : 0
                GradientStop { position: 0.0; color: root.horiz ? root.bodyTop : root.bodyBottom }
                GradientStop { position: 1.0; color: root.horiz ? root.bodyBottom : root.bodyTop }
            }
            strokeColor: root.rim
            strokeWidth: 1
            PathSvg { path: root.outline }
        }
    }
    Shape {
        id: maskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        ShapePath { strokeWidth: -1; fillColor: "white"; PathSvg { path: root.outline } }
    }
    Image { id: grain; anchors.fill: parent; source: Theme.grain; fillMode: Image.Tile; visible: false }
    MultiEffect {
        anchors.fill: parent
        source: grain
        maskEnabled: true
        maskSource: maskShape
        opacity: root.grainOpacity
    }

    Grid {
        id: grid
        readonly property real implicitLength: (root.horiz ? implicitWidth : implicitHeight)
        readonly property real centerV: root.d + thicknessNow / 2
        readonly property real thicknessNow: root.thickness * (1 + Math.abs(root.stretch))
        x: root.horiz ? root.uPad + root.pad + allCell.startPad : centerV - root.cell / 2
        y: root.horiz ? root.vWin - centerV - root.cell / 2 : root.uPad + root.pad + allCell.startPad
        layoutDirection: Qt.LeftToRight
        LayoutMirroring.enabled: false
        flow: root.horiz ? Grid.LeftToRight : Grid.TopToBottom
        rows: root.horiz ? 1 : 1000
        columns: root.horiz ? 1000 : 1
        spacing: root.gap
        opacity: Math.max(0, Math.min(1, (root.d - root.hiddenD) / (root.restD - root.hiddenD) * 1.5 - 0.4))

        Repeater {
            model: root.order
            delegate: Item {
                id: cellItem
                readonly property int mi: modelData
                readonly property bool startup: root.isStartup(mi)
                readonly property bool sepBefore: root.firstFree === index
                readonly property int extra: sepBefore ? root.sepExtra : 0
                width: startup ? 0 : (root.horiz ? root.cell + extra : root.cell)
                height: startup ? 0 : (root.horiz ? root.cell : root.cell + extra)
                visible: !startup

                Rectangle {   // pinned | running hairline
                    visible: cellItem.sepBefore
                    width: root.horiz ? 1 : root.cell * 0.5
                    height: root.horiz ? root.cell * 0.5 : 1
                    x: root.horiz ? (root.sepExtra - root.gap) / 2 - 0.5 : (root.cell - width) / 2
                    y: root.horiz ? (root.cell - height) / 2 : (root.sepExtra - root.gap) / 2 - 0.5
                    color: root.ink
                    opacity: 0.22
                }

                Item {
                    id: box
                    x: root.horiz ? cellItem.extra : 0
                    y: root.horiz ? 0 : cellItem.extra
                    width: root.cell; height: root.cell
                    scale: ma.pressed ? 0.88 : 1
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }

                    Rectangle {   // hover: one calm tonal chip
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: root.ink
                        opacity: ma.containsMouse ? Tokens.material.tintHover : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: root.iconSize; height: root.iconSize
                        // One size for every icon: no snapping to the theme's nearest raster size.
                        roundToIconSize: false
                        source: {
                            root.rev
                            const idx = root.row(mi)
                            if (!idx.valid) return "application-x-executable"
                            const d = tasks.data(idx, Qt.DecorationRole)
                            return d !== undefined && d !== null && d !== false ? d : "application-x-executable"
                        }
                        opacity: !root.isWindow(mi) || (root.isMinimized(mi) && root.pinPos(root.launcherBase(mi)) < 0) ? 0.5 : 1   // faded: a pinned app that is not running (a minimized pinned one is not)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {   // running: dot, focused: short pill; on the screen-edge side
                        property int len: root.isActive(mi) ? 14 : 4
                        width: root.horiz ? len : 4
                        height: root.horiz ? 4 : len
                        radius: 2
                        color: Theme.accent
                        x: root.horiz ? (parent.width - width) / 2 : 1
                        y: root.horiz ? parent.height - 5 : (parent.height - height) / 2
                        opacity: root.isWindow(mi) ? (root.isMinimized(mi) ? 0.4 : 0.9) : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on len { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onContainsMouseChanged: root.hoverIcon(mi, box, containsMouse)
                        onClicked: (mouse) => {
                            const idx = root.row(mi)
                            if (!idx.valid) return
                            if (mouse.button === Qt.RightButton) {
                                root.openMenu(mi, box)
                            } else if (mouse.button === Qt.MiddleButton || root.role(mi, TaskManager.AbstractTasksModel.IsLauncher) === true) {
                                tasks.requestNewInstance(idx)
                            } else {
                                tasks.requestActivate(idx)
                            }
                        }
                    }
                }
            }
        }

    }

    // Show desktop: a dotted hairline, the separator's quiet sibling. Click = minimize every window
    // (again = bring them back). Long-press and drag it along the row: it follows the pointer and
    // settles at whichever end is nearer, and stays there.
    Item {
        id: allCell
        readonly property real span: 22
        readonly property real reserve: span + root.gap          // room the dots take from the row
        readonly property real gridLen: grid.implicitLength + reserve
        property bool holding: false
        property real dragPos: 0
        readonly property bool atStart: holding ? dragPos + span / 2 < gridLen / 2 : dock.allAtStart

        // Everything here moves on springs, the island's own feel: while held, the dots chase the
        // pointer with a little lag; on release they overshoot and wobble in; the icons
        // slide aside on a spring of their own (startPad) instead of snapping.
        property real pos: target
        property real target: holding ? dragPos : (atStart ? 0 : gridLen - span)
        Behavior on pos { SpringAnimation { spring: allCell.holding ? 6.5 : 3.6; damping: allCell.holding ? 0.34 : 0.22; epsilon: 0.2 } }
        property real slide: atStart ? 1 : 0
        Behavior on slide { SpringAnimation { spring: 3.6; damping: 0.26; epsilon: 0.005 } }
        readonly property real startPad: slide * reserve

        x: root.horiz ? root.uPad + root.pad + pos : grid.x
        y: root.horiz ? grid.y : root.uPad + root.pad + pos
        width: root.horiz ? span : root.cell
        height: root.horiz ? root.cell : span
        opacity: grid.opacity
        scale: holding ? 1.35 : 1
        Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }
        Grid {
            anchors.centerIn: parent
            flow: Grid.LeftToRight
            columns: root.horiz ? 1 : 3   // a vertical dotted line in the bottom dock, a row in the side dock
            spacing: 5
            Repeater {
                model: 3
                Rectangle {
                    width: 3; height: 3; radius: 1.5; color: root.ink
                    opacity: allMa.containsMouse || allCell.holding ? 0.85 : 0.28
                    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
                }
            }
        }
        MouseArea {
            id: allMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property point pressAt
            // A drag starts after a half-second hold, or as soon as the pointer travels a little.
            Timer { id: holdTimer; interval: 350; onTriggered: allCell.holding = true }
            onPressed: (mouse) => { pressAt = Qt.point(mouse.x, mouse.y); holdTimer.restart() }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                if (!allCell.holding && Math.hypot(mouse.x - pressAt.x, mouse.y - pressAt.y) > 12) {
                    holdTimer.stop()
                    allCell.holding = true
                }
                if (!allCell.holding) return
                const p = mapToItem(root, mouse.x, mouse.y)
                const along = (root.horiz ? p.x : p.y) - (root.uPad + root.pad)
                allCell.dragPos = Math.max(0, Math.min(allCell.gridLen - allCell.span, along - allCell.span / 2))
            }
            onReleased: {
                holdTimer.stop()
                if (!allCell.holding) return
                allCell.holding = false
                dock.allAtStart = allCell.dragPos + allCell.span / 2 < allCell.gridLen / 2
                suppressClick = true
            }
            property bool suppressClick: false
            onCanceled: { holdTimer.stop(); allCell.holding = false }
            onClicked: { if (suppressClick) suppressClick = false; else root.minimizeAll() }
        }
    }

    DragHandler { id: drag; target: null; enabled: false }   // reserved: reorder gestures hold the dock open

    // ---- Tooltip and context menu --------------------------------------------------------
    // Glass cards in the island's material, drawn in the dock's own (taller, transparent) window:
    // hovering an icon shows its name and state; a right-click opens a short, state-aware menu.
    readonly property int popGap: 12
    property bool tipOn: false
    property int tipMi: -1
    property point tipAnchor: Qt.point(0, 0)      // icon centre, window coordinates
    property bool menuOn: false
    property point menuAnchor: Qt.point(0, 0)
    property var menuItems: []

    function iconCenter(item) { const p = item.mapToItem(root, item.width / 2, item.height / 2); return Qt.point(p.x, p.y) }
    // Where a popup of size w x h sits: above the icon (bottom dock) or to its right (left dock).
    function popPos(anchor, w, h) {
        if (horiz) return Qt.point(Math.max(4, Math.min(lWin - w - 4, anchor.x - w / 2)), vWin - (d + thickness) - popGap - h)
        return Qt.point(d + thickness + popGap, Math.max(4, Math.min(lWin - h - 4, anchor.y - h / 2)))
    }
    function stateText(mi) {
        root.rev
        if (mi < 0) return ""
        if (!isWindow(mi)) return "Not running"
        if (isMinimized(mi)) return "Minimized"
        const t = String(role(mi, Qt.DisplayRole)), n = String(role(mi, TaskManager.AbstractTasksModel.AppName))
        return t === n ? "" : t
    }
    function hoverIcon(mi, item, inside) {
        if (inside) {
            tipMi = mi; tipAnchor = iconCenter(item)
            if (!menuOn) tipTimer.restart()
        } else if (tipMi === mi) {
            tipTimer.stop(); tipOn = false
        }
    }
    Timer { id: tipTimer; interval: 400; onTriggered: root.tipOn = root.shown && !root.menuOn }
    Timer { id: menuLeave; interval: 700; onTriggered: root.menuOn = false }
    onPointerInChanged: { if (menuOn) { if (pointerIn) menuLeave.stop(); else menuLeave.restart() } }

    function openMenu(mi, item) {
        buildMenu(mi)
        menuAnchor = iconCenter(item)
        tipTimer.stop(); tipOn = false
        menuLeave.stop()
        menuOn = true
    }
    function buildMenu(mi) {
        const idx = row(mi), base = launcherBase(mi)
        const run = isWindow(mi), down = isMinimized(mi) || !isActive(mi)
        const url = role(mi, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon)
        const it = [{ kind: "head", title: String(role(mi, TaskManager.AbstractTasksModel.AppName)), sub: stateText(mi) }]
        if (!run) it.push({ text: "Open", fn: () => tasks.requestNewInstance(idx) })
        else it.push({ text: down ? "Show" : "Minimize", fn: () => down ? tasks.requestActivate(idx) : tasks.requestToggleMinimized(idx) })
        if (run) it.push({ text: "New window", fn: () => tasks.requestNewInstance(idx) })
        for (const a of dock.appActions(base)) it.push({ text: a.name, fn: () => dock.runExec(a.exec) })
        it.push({ kind: "sep" })
        const pinned = pinPos(base) >= 0
        it.push({ text: pinned ? "Unpin" : "Pin to dock", fn: () => {
            if (pinned) tasks.requestRemoveLauncher(url); else tasks.requestAddLauncher(url)
            savePins()
        } })
        if (run) {
            it.push({ kind: "sep" })
            it.push({ text: "Close", danger: true, fn: () => tasks.requestClose(idx) })
        }
        menuItems = it
    }

    readonly property var popupRects: {
        const r = []
        if (tip.opacity > 0.05) r.push({ x: tip.x, y: tip.y, w: tip.width, h: tip.height, r: Tokens.radius.md })
        if (menuCard.opacity > 0.05) r.push({ x: menuCard.x, y: menuCard.y, w: menuCard.width, h: menuCard.height, r: Tokens.radius.lg })
        return r
    }

    // Hover label: name, and below it the window title or the state - quiet, two lines at most.
    Item {
        id: tip
        readonly property point pos: root.popPos(root.tipAnchor, width, height)
        readonly property bool on: root.tipOn && !root.menuOn
        x: pos.x; y: pos.y
        width: Math.min(280, Math.max(tipName.implicitWidth, tipSub.implicitWidth) + 24)
        height: tipCol.implicitHeight + 16
        visible: opacity > 0.01
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.96
        transformOrigin: root.horiz ? Item.Bottom : Item.Left
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on scale { SpringAnimation { spring: 3.6; damping: 0.4; epsilon: 0.001 } }
        CardSurface { anchors.fill: parent; radius: Tokens.radius.md }
        Column {
            id: tipCol
            x: 12; y: 8
            spacing: 2
            Text {
                id: tipName
                width: Math.min(implicitWidth, 256)
                text: { root.rev; return root.tipMi < 0 ? "" : String(root.role(root.tipMi, TaskManager.AbstractTasksModel.AppName)) }
                color: Theme.text; elide: Text.ElideRight
                font.pixelSize: Tokens.type.body; font.family: Theme.font; font.weight: Font.Medium
            }
            Text {
                id: tipSub
                width: Math.min(implicitWidth, 256)
                visible: text !== ""
                text: root.stateText(root.tipMi)
                color: Theme.subtext; elide: Text.ElideRight
                font.pixelSize: Tokens.type.label; font.family: Theme.font
            }
        }
    }

    // Right-click menu: head (name + state), primary action, the app's own actions, pin, close last.
    Item {
        id: menuCard
        readonly property point pos: root.popPos(root.menuAnchor, width, height)
        x: pos.x; y: pos.y
        width: 220
        height: menuCol.implicitHeight + 16
        visible: opacity > 0.01
        opacity: root.menuOn ? 1 : 0
        scale: root.menuOn ? 1 : 0.94
        transformOrigin: root.horiz ? Item.Bottom : Item.Left
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Behavior on scale { SpringAnimation { spring: 3.6; damping: 0.3; epsilon: 0.001 } }
        CardSurface { anchors.fill: parent; radius: Tokens.radius.lg }
        Column {
            id: menuCol
            x: 8; y: 8
            width: parent.width - 16
            Repeater {
                model: root.menuItems
                delegate: Item {
                    id: row
                    readonly property var it: modelData
                    readonly property bool plain: !it.kind
                    width: menuCol.width
                    height: it.kind === "head" ? 52 : it.kind === "sep" ? 9 : 36
                    Column {   // head
                        visible: it.kind === "head"
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: it.title || ""; color: Theme.text; font.pixelSize: Tokens.type.body; font.family: Theme.font; font.weight: Font.Medium }
                        Text { visible: text !== ""; text: it.sub || ""; width: row.width - 24; elide: Text.ElideRight
                               color: Theme.subtext; font.pixelSize: Tokens.type.label; font.family: Theme.font }
                    }
                    Rectangle {   // separator
                        visible: it.kind === "sep"
                        x: 8; width: parent.width - 16; height: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text; opacity: 0.08
                    }
                    Rectangle {   // hover: one calm tonal chip
                        visible: row.plain
                        anchors.fill: parent
                        radius: Tokens.radius.sm
                        color: Theme.text
                        opacity: ima.containsMouse ? Tokens.material.tintHover : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                    }
                    Text {
                        visible: row.plain
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: it.text || ""
                        color: it.danger ? Tokens.palette.red200 : Theme.text
                        font.pixelSize: Tokens.type.body; font.family: Theme.font
                    }
                    MouseArea {
                        id: ima
                        anchors.fill: parent
                        enabled: row.plain
                        hoverEnabled: true
                        onClicked: { root.menuOn = false; it.fn() }
                    }
                }
            }
        }
    }
}
