import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Effects
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import AetherShared

// The dock: one glass pill per screen edge ("bottom" or "left", set by the host). The bottom one
// lives Android's way: out on the open desktop, folding back to the strip the moment a window
// covers the screen (still one touch away). The left edge keeps the hidden-at-rest trick - a 2px
// invisible strip that only listens for the pointer; touching it springs the pill out of the edge
// in the island's material, and leaving retracts it.
Item {
    id: root
    // Same colour as the island: the user's pick from its colour panel; the scheme follows the system.
    Binding { target: Theme; property: "accentOverride"; value: dock.accentOverride }
    Binding { target: Theme; property: "dark"; value: dock.dark }
    // Icon order is fixed (pinned first, left to right / top to bottom) whatever the UI locale.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // The vanish shrinks the glass, icons and tooltips toward the grab line: each of them carries this
    // Scale (one object per item). Wrapping them in a parent item dimmed the whole dock, so no wrapper.
    component PopScale: Scale {
        origin.x: root.popOx; origin.y: root.popOy
        xScale: root.popScale; yScale: root.popScale
    }

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
    // denser in dark mode, lighter and clearer in light mode; the grain is the global one.
    readonly property bool dark: dock.dark
    readonly property color ink: dark || Theme.tinted ? Theme.text : Tokens.palette.graphite950
    // Light mode is a white veil over the blur, nothing darker: clear, frosted, with a light rim.
    // The veil's hues are Theme's light material (Theme.dark follows the scheme here), re-alphaed
    // with the dock's own calibration: one owner for the numbers, per-surface density.
    readonly property color bodyTop: Theme.tinted ? Theme.bodyTop : dark ? Qt.alpha(Tokens.palette.ink750, Tokens.material.dockAlphaDark)
                                          : Qt.rgba(Theme.bodyTop.r, Theme.bodyTop.g, Theme.bodyTop.b, Tokens.material.dockAlphaLight)
    readonly property color bodyBottom: Theme.tinted ? Theme.bodyBottom : dark ? Qt.alpha(Tokens.palette.ink850, Tokens.material.dockAlphaDark)
                                             : Qt.rgba(Theme.bodyBottom.r, Theme.bodyBottom.g, Theme.bodyBottom.b, Tokens.material.dockAlphaLight * 0.8)
    readonly property color rim: Theme.rim   // cool grey hairline on the light veil; white hairline on dark glass
    readonly property real grainOpacity: Tokens.material.grainOpacity   // the global frost grain

    property bool shown: false
    property bool pointerIn: false
    readonly property bool holdOpen: menuOn || winOn || drag.active || dKey !== "" || allCell.holding || lensProg > 0

    // ---- Pinned open -----------------------------------------------------------------
    // Android's home-screen model: the bottom bar lives out while the desktop shows, and the task
    // model folds it back - to the 2px peek strip, still one touch away - the moment any window
    // covers the screen (a floating window over the bottom just as much as fullscreen; minimized
    // ones don't count). While it is out, Hide is refused - the leave timer and the D-Bus call
    // both - so only the model closes it. The top island never talks to the dock, so it keeps
    // opening over the bar freely.
    property bool covered: true    // covered until proven otherwise: no flash open at startup
    readonly property bool pinned: dock.edge === "bottom" && !covered
    function probeCovered() {
        let c = false
        for (let i = 0; i < tasks.count; i++) {
            if (isWindow(i) && !isMinimized(i)) { c = true; break }
        }
        if (c !== covered) covered = c
    }
    onPinnedChanged: {
        if (pinned) root.setShown(true)
        else if (root.shown && !root.pointerIn && !root.holdOpen) root.setShown(false)
    }

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
    // Transparent room for the popups. The chooser card (364 wide) reaches across the left dock's
    // short axis, so there the room grows to cover it: icon run + gap + card + air.
    readonly property real popupRoom: horiz ? 300 : Math.max(300, restD + thickness + popGap + winCard.width + 24)
    readonly property real vWin: thickness + restD + 36 + popupRoom   // + room for the overshoot
    readonly property real uPad: 14                            // room for the neck's flares
    property real d: hiddenD
    property real vel: 0
    property real lastD: hiddenD
    property real lastT: 0
    Behavior on d {
        SpringAnimation {
            id: dSpring
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
        if (!shown) { menuOn = false; tipOn = false; winOn = false }
    }
    readonly property real stretch: Math.max(-0.3, Math.min(0.3, vel * 0.012))

    // ---- Window geometry: strip while hidden, pill-sized while shown or moving ------------
    // The window only shrinks back to the idle strip once the spring has fully settled: the closing
    // spring bounces around its target, and resizing the surface on every bounce flickered.
    readonly property bool open: shown || dSpring.running || d > hiddenD + 2
    readonly property real lWin: along + 2 * uPad
    function applyWindow() {
        const w = open ? (horiz ? Math.ceil(lWin) : vWin) : (horiz ? dock.screenWidth : 10)
        const h = open ? (horiz ? vWin : Math.ceil(lWin)) : (horiz ? 10 : dock.screenHeight)
        dock.setWindowSize(w, h)
    }
    onOpenChanged: applyWindow()
    onLWinChanged: if (open) applyWindow()
    Component.onCompleted: { applyWindow(); reorder(); probeCovered() }

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
    // The vanish: a hold on the grab line pops the whole dock like a bubble - a small swell, then it
    // shrinks into the line and is gone. The glass is drawn through the Scale below; the blur and
    // input regions get the same scaling here so they follow it.
    property real popScale: 1
    property real popOx: width / 2
    property real popOy: height
    function popped(cmds) {
        const k = popScale
        if (k >= 0.999) return cmds
        if (k <= 0.01) return []
        const ox = popOx, oy = popOy
        return cmds.map(c => {
            const o = { t: c.t }
            if (c.x !== undefined) { o.x = ox + (c.x - ox) * k; o.y = oy + (c.y - oy) * k }
            if (c.x1 !== undefined) {
                o.x1 = ox + (c.x1 - ox) * k; o.y1 = oy + (c.y1 - oy) * k
                o.x2 = ox + (c.x2 - ox) * k; o.y2 = oy + (c.y2 - oy) * k
            }
            return o
        })
    }
    onPopScaleChanged: report()
    function report() { dock.setLayout(popped(segments), hotRect, popupRects, grabRect) }
    onSegmentsChanged: report()
    onHotRectChanged: report()
    onPopupRectsChanged: report()

    function setShown(s) {
        if (s === shown) return
        if (!s && pinned) return   // the pinned bar only folds when a window covers the screen
        peekTimer.stop(); leaveTimer.stop()
        shown = s
        if (s) dock.notifyShown()
    }
    Connections {
        target: dock
        function onStateRequested(state) { root.setShown(state === "shown") }
    }

    // Test hook (qdbus org.aether.Dock /Dock org.aether.Dock.PreviewWindows): the chooser opens on
    // the app owning the most windows. The delegate's box anchors it where its icon would.
    function previewWindows() {
        root.setShown(true)
        let best = null
        for (const g of root.groups) if (g.wins.length >= 1 && (!best || g.wins.length > best.wins.length)) best = g
        if (!best) return
        for (const c of grid.children) if (c.g && c.g.key === best.key) { root.openWindows(best, c.children[1] || c, false); return }
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
    // Holding it charges Circle to Search (see HomeLine); the hold lands after lensCharge.
    HomeLine {
        id: homeLine
        z: 5
        readonly property real len: Math.round(root.along * Tokens.dock.homeW)
        horiz: root.horiz
        width: root.horiz ? len : Tokens.dock.homeH
        height: root.horiz ? Tokens.dock.homeH : len
        x: root.horiz ? root.uPad + (root.along - len) / 2 : Tokens.dock.homeInset
        y: root.horiz ? root.vWin - Tokens.dock.homeInset - height : root.uPad + (root.along - len) / 2
        baseColor: "white"
        baseOpacity: 0.92
        pressed: root.lensGrow
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    }

    // The hold: charge for 560 ms (the colour builds along the line), then the dock folds away and
    // Lens opens out of this point on the screen edge. Letting go early relaxes it.
    property real lensProg: 0
    property bool lensGrow: false          // the line stretches only once the bar has vanished
    readonly property rect grabRect: !shown || !dock.lensEnabled ? Qt.rect(0, 0, 0, 0)
        : (horiz ? Qt.rect(homeLine.x - 24, vWin - 14, homeLine.width + 48, 14)
                 : Qt.rect(0, homeLine.y - 24, 14, homeLine.height + 48))
    onGrabRectChanged: report()
    NumberAnimation { id: lensCharge; target: root; property: "lensProg"; to: 1; duration: 560; easing.type: Easing.InOutQuad; onFinished: { root.lensFire() } }
    NumberAnimation { id: lensRelax; target: root; property: "lensProg"; to: 0; duration: 220; easing.type: Easing.OutQuad }
    property real lensFrac: 0.5
    function lensFire() {
        lensFrac = horiz ? (homeLine.x + homeLine.width / 2) / width : (homeLine.y + homeLine.height / 2) / height
        popOx = homeLine.x + homeLine.width / 2
        popOy = homeLine.y + homeLine.height / 2
        pop.restart()
    }
    SequentialAnimation {
        id: pop
        NumberAnimation { target: root; property: "popScale"; to: 1.05; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "popScale"; to: 0; duration: 280; easing.type: Easing.InCubic }
        // The bar is completely gone (a beat of just the line), only then the line stretches, then it
        // fades and Lens captures the screen.
        PauseAnimation { duration: 140 }
        ScriptAction { script: root.lensGrow = true }
        PauseAnimation { duration: 280 }
        ScriptAction { script: { root.setShown(false); lensGo.restart() } }
    }
    Timer { id: lensGo; interval: 200; onTriggered: { dock.activateLens(dock.edge, root.lensFrac); lensReset.restart() } }
    Timer { id: lensReset; interval: 700; onTriggered: { root.popScale = 1; root.lensGrow = false; lensRelax.restart() } }
    // The hold zone over the grab line. A TapHandler, not a MouseArea: a MouseArea there swallowed the
    // hover that opens and keeps the dock, so merely reaching for the line closed the bar.
    Item {
        id: lensGrab
        z: 6
        x: root.grabRect.x; y: root.grabRect.y; width: root.grabRect.width; height: root.grabRect.height
        enabled: root.shown && !lensGo.running && !lensReset.running
        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onPressedChanged: {
                if (pressed) { lensRelax.stop(); lensCharge.restart() }
                else if (lensCharge.running) { lensCharge.stop(); lensRelax.restart() }
            }
        }
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

    // The model keeps insertion order (idle launchers first, then windows as they appeared). The dock
    // groups the rows itself: one cell per app - pinned apps in pin order first (their idle launchers
    // among them), then free apps in first-seen order. A group holds every model row of its app:
    // the windows in `wins`, and a pinned app's launcher row alone when it is not running at all.
    function pinPos(base) {
        const l = tasks.launcherList
        for (let i = 0; i < l.length; i++) if (baseOf(l[i]) === base) return i
        return -1
    }
    function groupKey(i) {
        const b = launcherBase(i)
        if (b !== "") return b
        return "\u0001" + String(role(i, TaskManager.AbstractTasksModel.AppName))   // no .desktop: keep same-app rows together by name
    }
    property var groups: []
    property int firstFree: -1      // position in `groups` of the first free app
    onRevChanged: { reorder(); refreshWinRows(); probeCovered() }
    function reorder() {
        const byKey = new Map(), keys = []
        for (let i = 0; i < tasks.count; i++) {
            if (isStartup(i)) continue
            const k = groupKey(i)
            if (!byKey.has(k)) { byKey.set(k, { key: k, pin: -1, rows: [], wins: [] }); keys.push(k) }
            byKey.get(k).rows.push(i)
        }
        for (const g of byKey.values()) {
            if (g.key.charAt(0) !== "\u0001") g.pin = pinPos(g.key)
            for (const i of g.rows) if (isWindow(i)) g.wins.push(i)
        }
        const pinned = keys.map(k => byKey.get(k)).filter(g => g.pin >= 0).sort((a, b) => a.pin - b.pin)
        const free = keys.map(k => byKey.get(k)).filter(g => g.pin < 0)
        const gs = pinned.concat(free)
        const ff = free.length > 0 && pinned.length > 0 ? pinned.length : -1
        if (JSON.stringify(gs) !== JSON.stringify(groups)) groups = gs
        if (ff !== firstFree) firstFree = ff
    }
    function repOf(g) { return g.wins.length > 0 ? g.wins[0] : g.rows[0] }   // icon and menu: first window, else the launcher row
    function groupActive(g) { for (const i of g.wins) if (isActive(i)) return true; return false }
    function groupMinimized(g) { for (const i of g.wins) if (!isMinimized(i)) return false; return g.wins.length > 0 }
    function newInstance(g) { const idx = row(repOf(g)); if (idx.valid) tasks.requestNewInstance(idx) }
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

    // ---- Reorder: drag a pinned app along the row ---------------------------------------
    // The grabbed icon follows the pointer, its neighbours slide aside on springs to open the slot,
    // and on release it settles into place before the new pin order is written. Only pinned apps
    // have an order of their own (the free ones follow first-seen), so the drag stays inside them.
    readonly property real stride: cell + gap
    readonly property int pinnedN: { let n = 0; for (const g of groups) if (g.pin >= 0) n++; return n }
    property string dKey: ""          // the grabbed app's group key, "" when nothing is held
    property real dOff: 0             // its offset from its own cell along the row
    property int dTo: -1              // the slot it would land in
    property bool dAnim: false        // neighbours spring only while a drag is live
    property bool dSettle: false      // released: the icon is gliding into its slot
    property bool dCommit: false      // the new order is written, waiting for the row to rebuild
    readonly property int dFrom: dKey === "" ? -1 : groups.findIndex(g => g.key === dKey)
    function shiftOf(i) {
        if (dKey === "" || dFrom < 0) return 0
        if (i === dFrom) return dOff
        if (dFrom < dTo && i > dFrom && i <= dTo) return -stride
        if (dFrom > dTo && i >= dTo && i < dFrom) return stride
        return 0
    }
    function beginDrag(g) {
        prevTimer.stop(); tipTimer.stop(); tipOn = false; winOn = false
        dAnim = true; dOff = 0; dSettle = false; dCommit = false
        dKey = g.key
        dTo = dFrom
    }
    function dragTo(off) {
        if (dFrom < 0) return
        dOff = Math.max(-dFrom * stride, Math.min((pinnedN - 1 - dFrom) * stride, off))
        dTo = Math.max(0, Math.min(pinnedN - 1, Math.round(dFrom + dOff / stride)))
    }
    function endDrag() {
        if (dKey === "" || dSettle) return
        dSettle = true
        settleAnim.to = (dTo - dFrom) * stride
        settleAnim.restart()
    }
    function clearDrag() {
        settleAnim.stop(); settleTimer.stop()
        dAnim = false; dKey = ""; dOff = 0; dTo = -1; dSettle = false; dCommit = false
    }
    function commitDrag() {
        if (dFrom < 0 || dTo === dFrom) { clearDrag(); return }
        const from = groups[dFrom].pin, to = groups[dTo].pin
        const l = tasks.launcherList.slice()
        l.splice(to, 0, l.splice(from, 1)[0])
        dCommit = true
        settleTimer.restart()      // fallback: never leave the row held if the rebuild does not come
        dock.launchers = l
    }
    onGroupsChanged: {
        if (dCommit) clearDrag()
        else if (dKey !== "" && dFrom < 0) clearDrag()
    }
    NumberAnimation { id: settleAnim; target: root; property: "dOff"; duration: 170; easing.type: Easing.OutCubic; onFinished: root.commitDrag() }
    Timer { id: settleTimer; interval: 400; onTriggered: root.clearDrag() }

    // ---- The glass: the island's material on the silhouette --------------------------
    Shape {
        transform: PopScale {}
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
        transform: PopScale {}
        id: maskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        ShapePath { strokeWidth: -1; fillColor: "white"; PathSvg { path: root.outline } }
    }
    Image { id: grain; anchors.fill: parent; source: Theme.grain; fillMode: Image.Tile; visible: false }
    MultiEffect {
        transform: PopScale {}
        anchors.fill: parent
        source: grain
        maskEnabled: true
        maskSource: maskShape
        opacity: root.grainOpacity
    }

    Grid {
        transform: PopScale {}
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
            model: root.groups
            delegate: Item {
                id: cellItem
                readonly property var g: modelData
                readonly property bool sepBefore: root.firstFree === index
                readonly property int extra: sepBefore ? root.sepExtra : 0
                readonly property int mi: root.repOf(g)   // the icon's row: the first window, else the idle launcher
                width: root.horiz ? root.cell + extra : root.cell
                height: root.horiz ? root.cell : root.cell + extra
                readonly property bool held: root.dKey === g.key
                z: held ? 10 : 0
                property real sx: root.shiftOf(index)     // reorder: slides aside / follows the pointer
                Behavior on sx { enabled: root.dAnim && !cellItem.held; SpringAnimation { spring: 5; damping: 0.55; epsilon: 0.2 } }

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
                    x: root.horiz ? cellItem.extra + cellItem.sx : 0
                    y: root.horiz ? 0 : cellItem.extra + cellItem.sx
                    width: root.cell; height: root.cell
                    scale: cellItem.held ? 1.14 : ma.pressed ? 0.88 : 1
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }

                    Rectangle {   // hover: one calm tonal chip
                        anchors.fill: parent
                        radius: Tokens.radius.md
                        color: root.ink
                        opacity: ma.containsMouse ? Tokens.material.tintHover : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    Rectangle {   // the stack: a ghost card peeking from behind the icon - this app owns several windows
                        readonly property bool on: cellItem.g.wins.length > 1
                        x: -4; y: -4
                        width: root.iconSize * 0.8; height: width
                        radius: Tokens.radius.sm
                        color: root.ink
                        opacity: on ? 0.14 : 0
                        scale: on ? 1 : 0.75
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: root.iconSize; height: root.iconSize
                        // One size for every icon: no snapping to the theme's nearest raster size.
                        roundToIconSize: false
                        source: {
                            root.rev
                            const idx = root.row(cellItem.mi)
                            if (!idx.valid) return "application-x-executable"
                            const d = tasks.data(idx, Qt.DecorationRole)
                            return d !== undefined && d !== null && d !== false ? d : "application-x-executable"
                        }
                        opacity: cellItem.g.wins.length === 0 ? 0.5 : 1   // faded: a pinned app that is not running
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle {   // running: dot, focused: short pill; on the screen-edge side
                        property int len: root.groupActive(cellItem.g) ? 14 : 4
                        width: root.horiz ? len : 4
                        height: root.horiz ? 4 : len
                        radius: 2
                        color: Theme.accent   // the user's accent, as in the island
                        // Below the icon, in the glass's own padding (left dock: to its screen-edge side).
                        x: root.horiz ? (parent.width - width) / 2 : -5
                        y: root.horiz ? parent.height + 2 : (parent.height - height) / 2
                        opacity: cellItem.g.wins.length === 0 ? 0
                                 : (root.groupMinimized(cellItem.g) ? 0.3 : (root.groupActive(cellItem.g) ? 0.9 : 0.55))
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on len { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onContainsMouseChanged: if (root.dKey === "") root.hoverIcon(cellItem.g, box, containsMouse)
                        // Reorder: a pinned app dragged a little leaves its cell and follows the pointer.
                        property real pressAt: 0
                        property bool suppressClick: false
                        function along(mouse) { const p = mapToItem(root, mouse.x, mouse.y); return root.horiz ? p.x : p.y }
                        onPressed: (mouse) => { if (mouse.button === Qt.LeftButton) pressAt = along(mouse) }
                        onPositionChanged: (mouse) => {
                            if (!pressed || !(pressedButtons & Qt.LeftButton) || cellItem.g.pin < 0 || root.pinnedN < 2 || root.dSettle) return
                            const a = along(mouse)
                            if (root.dKey === "") {
                                if (Math.abs(a - pressAt) < 8) return
                                root.beginDrag(cellItem.g)
                                pressAt = a
                            } else if (!cellItem.held) return
                            root.dragTo(a - pressAt)
                        }
                        onReleased: { if (cellItem.held) { suppressClick = true; root.endDrag() } }
                        onCanceled: { if (cellItem.held) root.clearDrag() }
                        onClicked: (mouse) => {
                            if (suppressClick) { suppressClick = false; return }
                            const g = cellItem.g
                            if (mouse.button === Qt.RightButton) {
                                root.openMenu(g, box)
                            } else if (mouse.button === Qt.MiddleButton || g.wins.length === 0) {
                                root.newInstance(g)
                            } else if (g.wins.length === 1) {
                                // a click means the window: even when the hover preview is already
                                // open on this very icon - that card must not swallow the click.
                                root.winOn = false
                                tasks.requestActivate(root.row(g.wins[0]))
                            } else {
                                root.cycleWindow(g)         // several windows: raise the least visible
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
        transform: PopScale {}
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
    property var tipG: null
    property point tipAnchor: Qt.point(0, 0)      // icon centre, window coordinates
    property bool menuOn: false
    property point menuAnchor: Qt.point(0, 0)
    property var menuItems: []
    // The window chooser: opened by a left-click on an app that owns several windows. `winG` is the
    // group at open time; every rebuild re-finds it by key (`winCur`), so the card lives across
    // model churn. `winRows` is only re-published when its content actually changes, so hovering a
    // row survives the model's progress ticks.
    property bool winOn: false
    property var winG: null
    property point winAnchor: Qt.point(0, 0)      // icon centre, window coordinates
    readonly property string winKey: winG ? winG.key : ""
    readonly property var winCur: {
        root.rev
        const k = root.winKey
        if (k === "") return null
        for (const g of root.groups) if (g.key === k) return g
        return null
    }
    property var winRows: []
    property bool winFromHover: false     // hover previews fold when the pointer moves off; clicked ones stay
    property var prevG: null              // the group the pointer is hovering, waiting out the show delay
    property point prevAnchor: Qt.point(0, 0)
    property var prevItem: null
    Timer { id: prevTimer; interval: 400; onTriggered: if (root.shown && !root.menuOn && root.prevG) root.openWindows(root.prevG, root.prevItem, true) }
    Timer { id: prevLeave; interval: 350; onTriggered: if (root.winFromHover && !winCard.hov) root.winOn = false }
    function refreshWinRows() {
        const g = root.winCur, out = []
        if (g) for (const i of g.wins) {
            const t = role(i, Qt.DisplayRole)
            const wids = role(i, TaskManager.AbstractTasksModel.WinIdList)
            out.push({
                mi: i,
                title: t !== undefined && t !== null ? String(t) : "",
                active: isActive(i),
                minimized: isMinimized(i),
                uuid: wids !== undefined && wids !== null && wids.length > 0 ? String(wids[0]) : "",
                live: role(i, TaskManager.AbstractTasksModel.IsMapped) === true,
                born: Number(role(i, TaskManager.AbstractTasksModel.LastActivated) || 0)
            })
        }
        // Most comfortable to pick from: the window you were just in, then the ones before it.
        out.sort((a, b) => (b.active - a.active) || (b.born - a.born))
        if (JSON.stringify(out) !== JSON.stringify(winRows)) winRows = out
        if (root.winOn && (!g || g.wins.length === 0)) root.winOn = false   // the app is gone: fold the card
    }
    function openWindows(g, item, byHover) {
        winG = g
        winAnchor = iconCenter(item)
        tipTimer.stop(); tipOn = false
        menuOn = false
        menuLeave.stop()
        prevTimer.stop(); prevLeave.stop()
        winFromHover = byHover
        winOn = true
        refreshWinRows()      // don't wait for the model's next tick: the rows are wanted now
    }
    function pickWindow(mi) {
        winOn = false
        const idx = row(mi)
        if (idx.valid) tasks.requestActivate(idx)
    }
    function closeWindow(mi) { const idx = row(mi); if (idx.valid) tasks.requestClose(idx) }
    // A click on a grouped icon raises the least-visible window (Dov's rule): a folded one wins
    // over an open one, among folded - the last that was used, among open - the one that has been
    // sitting in the back the longest, so repeated clicks walk the windows from back to front.
    function cycleWindow(g) {
        winOn = false
        let best = -1, bestMin = false, bestBorn = 0, found = false
        for (const i of g.wins) {
            const min = isMinimized(i)
            const born = Number(role(i, TaskManager.AbstractTasksModel.LastActivated) || 0)
            let better
            if (!found) better = true
            else if (min !== bestMin) better = min
            else better = min ? born > bestBorn : born < bestBorn
            if (better) { best = i; bestMin = min; bestBorn = born; found = true }
        }
        if (best >= 0) {
            const idx = row(best)
            if (idx.valid) tasks.requestActivate(idx)
        }
    }

    function iconCenter(item) { const p = item.mapToItem(root, item.width / 2, item.height / 2); return Qt.point(p.x, p.y) }
    // Where a popup of size w x h sits: above the icon (bottom dock) or to its right (left dock).
    function popPos(anchor, w, h) {
        if (horiz) return Qt.point(Math.max(4, Math.min(lWin - w - 4, anchor.x - w / 2)), vWin - (d + thickness) - popGap - h)
        return Qt.point(d + thickness + popGap, Math.max(4, Math.min(lWin - h - 4, anchor.y - h / 2)))
    }
    function stateText(g) {
        root.rev
        if (!g) return ""
        if (g.wins.length === 0) return "Not running"
        if (g.wins.length > 1) return g.wins.length + " windows"
        const i = g.wins[0]
        if (isMinimized(i)) return "Minimized"
        const t = String(role(i, Qt.DisplayRole)), n = String(role(i, TaskManager.AbstractTasksModel.AppName))
        return t === n ? "" : t
    }
    // Hovering an icon: a running app shows its windows' preview card (any count - one tile or
    // several, like the big systems); an idle pinned app keeps the quiet two-line text tip.
    function hoverIcon(g, item, inside) {
        if (inside) {
            tipTimer.stop(); tipOn = false
            if (g.wins.length === 0) {
                if (!menuOn && !winOn) { tipG = g; tipAnchor = iconCenter(item); tipTimer.restart() }
            } else if (!menuOn) {
                prevG = g; prevItem = item; prevAnchor = iconCenter(item)
                prevLeave.stop()
                if (winOn && winFromHover && winKey === g.key) return   // already showing this app
                if (winOn && winFromHover) { openWindows(g, item, true); return }   // hop: switch at once
                prevTimer.restart()
            }
        } else {
            if (tipG === g) { tipTimer.stop(); tipOn = false }
            if (winOn && winFromHover && winKey === g.key && !winCard.hov) prevLeave.restart()
        }
    }
    Timer { id: tipTimer; interval: 400; onTriggered: root.tipOn = root.shown && !root.menuOn && !root.winOn }
    Timer { id: menuLeave; interval: 700; onTriggered: { root.menuOn = false; root.winOn = false } }
    onPointerInChanged: { if (menuOn || winOn) { if (pointerIn) menuLeave.stop(); else menuLeave.restart() } }

    function openMenu(g, item) {
        buildMenu(g)
        menuAnchor = iconCenter(item)
        tipTimer.stop(); tipOn = false
        winOn = false
        menuLeave.stop()
        menuOn = true
    }
    // One window: the short state-aware menu as before. Several: the app-level menu - the windows
    // themselves live in the chooser on a left-click, so here only "Close all" stands for them.
    function buildMenu(g) {
        const rep = repOf(g), idx = row(rep), base = launcherBase(rep)
        const run = g.wins.length > 0, many = g.wins.length > 1
        const down = run && (isMinimized(rep) || !isActive(rep))
        const url = role(rep, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon)
        const it = [{ kind: "head", title: String(role(rep, TaskManager.AbstractTasksModel.AppName)), sub: stateText(g) }]
        if (!run) it.push({ text: "Open", fn: () => tasks.requestNewInstance(idx) })
        else {
            if (!many) it.push({ text: down ? "Show" : "Minimize", fn: () => down ? tasks.requestActivate(idx) : tasks.requestToggleMinimized(idx) })
            it.push({ text: "New window", fn: () => tasks.requestNewInstance(idx) })
        }
        for (const a of dock.appActions(base)) it.push({ text: a.name, fn: () => dock.runExec(a.exec) })
        it.push({ kind: "sep" })
        const pinned = pinPos(base) >= 0
        it.push({ text: pinned ? "Unpin" : "Pin to dock", fn: () => {
            if (pinned) tasks.requestRemoveLauncher(url); else tasks.requestAddLauncher(url)
            savePins()
        } })
        if (run) {
            it.push({ kind: "sep" })
            it.push(many ? { text: "Close all", danger: true, fn: () => { for (const i of g.wins) tasks.requestClose(row(i)) } }
                         : { text: "Close", danger: true, fn: () => tasks.requestClose(idx) })
        }
        menuItems = it
    }

    readonly property var popupRects: {
        const r = []
        if (tip.opacity > 0.05) r.push({ x: tip.x, y: tip.y, w: tip.width, h: tip.height, r: Tokens.radius.md })
        if (menuCard.opacity > 0.05) r.push({ x: menuCard.x, y: menuCard.y, w: menuCard.width, h: menuCard.height, r: Tokens.radius.lg })
        if (winCard.opacity > 0.05) r.push({ x: winCard.x, y: winCard.y, w: winCard.width, h: winCard.height, r: Tokens.radius.lg })
        return r
    }

    // Hover label: name, and below it the window title or the state - quiet, two lines at most.
    Item {
        transform: PopScale {}
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
                text: { root.rev; return root.tipG ? String(root.role(root.repOf(root.tipG), TaskManager.AbstractTasksModel.AppName)) : "" }
                color: Theme.text; elide: Text.ElideRight
                font.pixelSize: Tokens.type.body; font.family: Theme.font; font.weight: Font.Medium
            }
            Text {
                id: tipSub
                width: Math.min(implicitWidth, 256)
                visible: text !== ""
                text: root.stateText(root.tipG)
                color: Theme.subtext; elide: Text.ElideRight
                font.pixelSize: Tokens.type.label; font.family: Theme.font
            }
        }
    }

    // Right-click menu: head (name + state), primary action, the app's own actions, pin, close last.
    Item {
        transform: PopScale {}
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

    // Window chooser: left-click on an app that owns several windows, hover on any running one.
    // The card keeps showing while it fades: `winCur` and `winRows` stay even after `winOn` drops.
    Connections {
        target: winCard
        function onHovChanged() {
            if (!root.winOn || !root.winFromHover) return
            if (winCard.hov) prevLeave.stop(); else prevLeave.restart()
        }
    }
    WindowsCard {
        transform: PopScale {}
        id: winCard
        transformOrigin: root.horiz ? Item.Bottom : Item.Left
        readonly property point pos: root.popPos(root.winAnchor, width, height)
        x: pos.x; y: pos.y
        on: root.winOn && root.winCur !== null
        appName: root.winCur ? String(root.role(root.repOf(root.winCur), TaskManager.AbstractTasksModel.AppName)) : ""
        icon: {
            root.rev
            if (!root.winCur) return ""
            const idx = root.row(root.repOf(root.winCur))
            if (!idx.valid) return ""
            const d = tasks.data(idx, Qt.DecorationRole)
            return d !== undefined && d !== null && d !== false ? d : "application-x-executable"
        }
        count: root.winCur ? root.winCur.wins.length : 0
        rows: root.winRows
        onPick: (mi) => root.pickWindow(mi)
        onCloseOne: (mi) => root.closeWindow(mi)
    }
}
