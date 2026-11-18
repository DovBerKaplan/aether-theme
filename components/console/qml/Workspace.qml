import QtQuick
import AetherShared
import "."
import "SplitModel.js" as SM
import "ListBlocks.js" as LB

// The shelf's workspace, without any pixels: which tabs exist, which pane holds them, how the
// panes are split, what is being dragged, which terminals are seated. Console.qml extends this
// with the glass, the ear and the geometry (areaW/areaH/mapToArea tell us how big the panes'
// area is). Every collection is only ever replaced, never mutated in place.
Item {
    id: root
    property bool open: false
    readonly property real gap: 6                 // between panes (the dividers live here)
    property real areaW: 0                        // the panes' area, set by the visuals
    property real areaH: 0
    property var mapToArea: function (x, y) { return Qt.point(x, y) }
    property bool overlayOpen: false              // an editor/import page covers the panes
    signal reportRequested()
    signal closeOverlay()

    // ---------- the workspace ----------
    // tabs: every open tab (home is always there). groups: pane id -> { tabIds, active }.
    // tree: the split layout over group ids (SplitModel.js). All of them are only ever
    // replaced, never mutated in place, so bindings and handlers see consistent snapshots.
    property var tabs: [{ id: "home", kind: "home", title: I18n.tr("Console") }]
    property var groups: ({ g1: { tabIds: ["home"], active: "home" } })
    property var tree: SM.leaf("g1")
    property string focusGroup: "g1"
    property string maxGroup: ""                  // a zoomed pane hides the others
    property int groupSeq: 1
    property var groupIds: ["g1"]                 // the Repeater model: replaced only on a real change
    property var dividerKeys: []
    property string filterText: ""
    property bool resizing: false

    function clone(o) { return JSON.parse(JSON.stringify(o)) }
    function tabById(id) {
        for (let i = 0; i < tabs.length; ++i) if (tabs[i].id === id) return tabs[i]
        return null
    }
    function groupOf(tabId) {
        for (const g in groups) if (groups[g].tabIds.indexOf(tabId) >= 0) return g
        return ""
    }
    readonly property var focusTab: tabById((groups[focusGroup] || { active: "home" }).active) || tabs[0]
    readonly property string focusKind: focusTab ? focusTab.kind : "home"

    onTreeChanged: refreshStructure()
    function refreshStructure() {
        const ids = tree ? SM.groupsIn(tree) : []
        if (JSON.stringify(ids) !== JSON.stringify(groupIds)) groupIds = ids
        const keys = tree ? SM.dividers(tree, 0, 0, 1000, 1000, gap).map(d => d.path.join("/") + ":" + d.i) : []
        if (JSON.stringify(keys) !== JSON.stringify(dividerKeys)) dividerKeys = keys
    }

    function openTab(kind, id, title, data, dtype, gid) {
        if (tabById(id)) { revealTab(id); return }
        const t = { id: id, kind: kind, title: title, data: data || {}, dtype: dtype || "", path: "/", sid: (data || {}).id || "",
                    slot: (kind === "term" || kind === "local") ? freeSlot(kind, (data || {}).id || (data || {}).host || "") : 0 }
        const target = (gid && groups[gid]) ? gid : focusGroup
        const g = clone(groups)
        g[target].tabIds.push(id)
        g[target].active = id
        tabs = tabs.concat([t])
        groups = g
        focusGroup = target
    }
    // Terminals of one destination get their own tmux session each (slot 0 is the main one), so
    // split panes never mirror each other.
    function freeSlot(kind, key) {
        const used = {}
        tabs.forEach(t => { if (t.kind === kind && (t.data.id || t.data.host || "") === key) used[t.slot || 0] = true })
        let n = 0
        while (used[n]) n++
        return n
    }
    function activateTab(gid, id) {
        if (!groups[gid]) return
        const g = clone(groups)
        g[gid].active = id
        groups = g
        focusGroup = gid
    }
    function revealTab(id) { const g = groupOf(id); if (g) activateTab(g, id) }
    function setTabPath(id, path) { tabs = tabs.map(t => t.id === id ? Object.assign({}, t, { path: path }) : t) }

    function closeTab(id) {
        if (id === "home") return
        const pid = seats[id] || 0
        if (pid > 0) {
            seatHideNow(pid)
            launcher.killPid(pid)   // the tmux session (server or local) survives
            const sm = Object.assign({}, seats); delete sm[id]; seats = sm
        }
        setHole(id, null)
        const from = groupOf(id)
        tabs = tabs.filter(t => t.id !== id)
        if (from) removeFromGroup(id, from)
    }
    // Takes a tab out of its pane; an emptied pane leaves the layout (its neighbour grows).
    function removeFromGroup(id, from, g, t) {
        const ng = g || clone(groups)
        let nt = t === undefined ? tree : t
        ng[from].tabIds = ng[from].tabIds.filter(x => x !== id)
        if (ng[from].tabIds.length === 0) {
            delete ng[from]
            nt = SM.closeGroup(nt, from)
            if (maxGroup === from) maxGroup = ""
            if (focusGroup === from) focusGroup = SM.groupsIn(nt)[0]
        } else if (ng[from].active === id) {
            ng[from].active = ng[from].tabIds[ng[from].tabIds.length - 1]
        }
        groups = ng
        tree = nt
    }
    // Drop a tab on a pane: its middle moves it there, an edge splits that pane.
    function dropTab(id, target, zone) {
        const from = groupOf(id)
        if (!from || !groups[target]) return
        const g = clone(groups)
        let t = tree
        let focus = target
        if (zone === "center") {
            if (from === target) return
            g[target].tabIds.push(id)
            g[target].active = id
        } else {
            if (from === target && g[from].tabIds.length === 1) return
            const ngid = "g" + (++groupSeq)
            t = SM.splitGroup(t, target, zone, ngid)
            g[ngid] = { tabIds: [id], active: id }
            focus = ngid
        }
        // the tab is in two panes for a moment; leave the old one
        g[from].tabIds = g[from].tabIds.filter(x => x !== id)
        if (g[from].tabIds.length === 0) {
            delete g[from]
            t = SM.closeGroup(t, from)
            if (maxGroup === from) maxGroup = ""
        } else if (g[from].active === id) {
            g[from].active = g[from].tabIds[g[from].tabIds.length - 1]
        }
        groups = g
        tree = t
        focusGroup = focus
        maxGroup = ""
        saveLayout()
    }
    // A pane menu split: with several tabs the active one moves out; with one, a copy opens.
    function splitPane(gid, side) {
        const act = groups[gid].active
        if (groups[gid].tabIds.length >= 2) { dropTab(act, gid, side); return }
        const t = tabById(act)
        if (!t || t.kind === "home") return
        const copy = Object.assign({}, t, { id: t.kind + ":" + (t.data.id || t.data.name || "x") + ":" + Date.now(),
                                           slot: (t.kind === "term" || t.kind === "local") ? freeSlot(t.kind, t.data.id || t.data.host || "") : 0 })
        const g = clone(groups)
        g[gid].tabIds.push(copy.id)
        tabs = tabs.concat([copy])
        groups = g
        dropTab(copy.id, gid, side)
    }
    function canSplitPane(gid, side) {
        const g = groups[gid]
        if (!g) return false
        const t = tabById(g.active)
        if (g.tabIds.length < 2 && (!t || t.kind === "home")) return false
        return SM.canSplit(tree, gid, side, areaW, areaH, gap)
    }
    function paneAction(gid, act) {
        menuGid = ""
        if (act === "right" || act === "bottom") splitPane(gid, act)
        else if (act === "equalize") { tree = SM.equalize(tree, [], true); saveLayout() }
        else if (act === "max") maxGroup = maxGroup === gid ? "" : gid
        else if (act === "close") closePane(gid)
        else if (act.indexOf("preset:") === 0) applyPreset(act.substring(7))
    }
    // Closing a pane never closes its tabs: they join the neighbouring pane.
    function closePane(gid) {
        if (groupIds.length < 2 || !groups[gid]) return
        const ids = groups[gid].tabIds.slice()
        const nb = SM.neighbor(tree, gid, "left", areaW, areaH)
              || SM.neighbor(tree, gid, "up", areaW, areaH)
              || SM.neighbor(tree, gid, "right", areaW, areaH)
              || SM.neighbor(tree, gid, "down", areaW, areaH)
              || groupIds.filter(x => x !== gid)[0]
        const g = clone(groups)
        g[nb].tabIds = g[nb].tabIds.concat(ids)
        g[nb].active = groups[gid].active
        delete g[gid]
        groups = g
        tree = SM.closeGroup(tree, gid)
        if (maxGroup === gid) maxGroup = ""
        focusGroup = nb
        saveLayout()
    }
    function resizeTo(startTree, path, i, deltaFrac, extent) { tree = SM.resize(startTree, path, i, deltaFrac, extent) }
    function equalizeAt(path) { tree = SM.equalize(tree, path); saveLayout() }

    // ---------- persistence: the arrangement comes back; terminals only reconnect when shown ----------
    function saveLayout() { if (testDetail.length === 0) saveTimer.restart() }   // fixtures never touch the real config
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: ctl.setSetting("Layout", JSON.stringify({ v: 1, tabs: root.tabs, groups: root.groups, tree: root.tree,
                                                                focus: root.focusGroup, seq: root.groupSeq }))
    }
    onTabsChanged: saveLayout()
    onGroupsChanged: saveLayout()
    function restoreLayout() {
        let o = null
        try { o = JSON.parse(ctl.setting("Layout")) } catch (e) { return }
        if (!o || o.v !== 1 || !Array.isArray(o.tabs) || !o.groups || !o.tree) return
        // trust nothing: every tab in exactly one pane, every pane in the tree, home present
        const have = {}
        o.tabs.forEach(t => have[t.id] = 0)
        const leaves = SM.groupsIn(o.tree)
        if (have.home === undefined || leaves.length !== Object.keys(o.groups).length) return
        for (const g of leaves) {
            const grp = o.groups[g]
            if (!grp || !grp.tabIds.length || grp.tabIds.indexOf(grp.active) < 0) return
            for (const id of grp.tabIds) { if (have[id] === undefined) return; have[id]++ }
        }
        if (Object.keys(have).some(id => have[id] !== 1)) return
        o.tabs.forEach(t => { if (t.id === "home") t.title = I18n.tr("Console") })
        tabs = o.tabs
        groups = o.groups
        groupSeq = o.seq || leaves.length
        tree = o.tree
        focusGroup = o.groups[o.focus] ? o.focus : leaves[0]
    }

    // Ready-made layouts: the open tabs are dealt into as many panes as the layout has slots
    // (fewer tabs than slots = fewer panes; the surplus tabs share the last pane).
    function applyPreset(name) {
        const order = []
        groupIds.forEach(g => groups[g].tabIds.forEach(id => order.push(id)))
        const slots = Math.min(SM.PRESET_SLOTS[name] || 1, order.length)
        const ng = {}
        const gids = []
        for (let i = 0; i < slots; ++i) {
            const gid = groupIds[i] || ("g" + (++groupSeq))
            gids.push(gid)
            ng[gid] = { tabIds: [], active: "" }
        }
        order.forEach((id, i) => { const g = ng[gids[Math.min(i, slots - 1)]]; g.tabIds.push(id) })
        gids.forEach(gid => {
            const keep = (groups[gid] || {}).active
            ng[gid].active = ng[gid].tabIds.indexOf(keep) >= 0 ? keep : ng[gid].tabIds[0]
        })
        groups = ng
        tree = SM.preset(name, gids)
        maxGroup = ""
        focusGroup = gids[0]
    }
    // Ctrl+Shift+arrows: move the divider on that side of the focused pane
    function nudge(gid, dir) {
        const path = SM.findPath(tree, gid)
        if (!path) return
        const axis = (dir === "left" || dir === "right") ? "row" : "col"
        for (let depth = path.length - 1; depth >= 0; --depth) {
            const parent = SM.nodeAt(tree, path.slice(0, depth))
            if (parent.dir !== axis) continue
            const idx = path[depth]
            const forward = dir === "right" || dir === "down"
            const i = forward ? idx : idx - 1
            if (i < 0 || i >= parent.kids.length - 1) continue
            const d = dividerMap[path.slice(0, depth).join("/") + ":" + i]
            if (!d) return
            resizeTo(tree, path.slice(0, depth), i, (forward ? 0.04 : -0.04), d.extent)
            return
        }
    }
    function focusNeighbor(dir) {
        const n = SM.neighbor(tree, focusGroup, dir, areaW, areaH)
        if (n) focusGroup = n
    }

    // ---------- pane geometry ----------
    readonly property var layoutList: {
        if (!tree || areaW <= 0) return []
        if (maxGroup !== "" && groups[maxGroup]) return [{ group: maxGroup, x: 0, y: 0, w: areaW, h: areaH }]
        return SM.layoutRects(tree, 0, 0, areaW, areaH, gap)
    }
    readonly property var rects: { const m = {}; layoutList.forEach(r => m[r.group] = r); return m }
    readonly property var dividerMap: {
        const m = {}
        if (tree && maxGroup === "" && areaW > 0)
            SM.dividers(tree, 0, 0, areaW, areaH, gap).forEach(d => m[d.path.join("/") + ":" + d.i] = d)
        return m
    }

    // ---------- terminals: seats and the holes they leave in the glass ----------
    property var seats: ({})        // tab id -> the konsole window living for it
    property var downIds: ({})      // tabs whose terminal window died (orange dot)
    property var holes: ({})        // tab id -> its seat's rect in shelf coordinates (only while on stage)
    function setSeat(id, pid) { const m = Object.assign({}, seats); m[id] = pid; seats = m }

    // A terminal view can be destroyed and rebuilt in the same breath (a tab moves to another
    // pane, a layout preset): hiding the window at once would race the new view's "show" and the
    // script would never announce it again. So a leaving view only schedules the hide; a view
    // that appears meanwhile adopts the window - already revealed - instead.
    property var revealed: ({})      // pid -> true while its window is on stage
    property var liveViews: ({})     // tab id -> true while a view for it exists
    property var leaving: ({})       // tab id -> pid whose hide is pending
    function seatEnter(id) {
        const v = Object.assign({}, liveViews); v[id] = true; liveViews = v
        delete leaving[id]
    }
    function seatLeave(id, pid) {
        const v = Object.assign({}, liveViews); delete v[id]; liveViews = v
        if (pid > 0) { leaving[id] = pid; leaveTimer.restart() }
    }
    function seatHideNow(pid) {
        ctl.hideSeat(pid)
        const r = Object.assign({}, revealed); delete r[pid]; revealed = r
    }
    Timer {
        id: leaveTimer
        interval: 200
        onTriggered: {
            for (const id in root.leaving) if (!root.liveViews[id]) root.seatHideNow(root.leaving[id])
            root.leaving = ({})
        }
    }
    Connections {
        target: ctl
        function onSeatReady(pid) { const r = Object.assign({}, root.revealed); r[pid] = true; root.revealed = r }
    }
    function clearDown(id) {
        if (downIds[id] === undefined) return
        const d = Object.assign({}, downIds); delete d[id]; downIds = d
    }
    function sessionDown(sid) {
        for (let i = 0; i < tabs.length; ++i)
            if (tabs[i].sid === sid && downIds[tabs[i].id] === true) return true
        return false
    }
    function setHole(id, rect) {
        if (!rect && holes[id] === undefined) return
        const h = Object.assign({}, holes)
        if (rect) h[id] = rect; else delete h[id]
        holes = h
    }
    onHolesChanged: reportRequested()
    function rrPath(x, y, w, h, r) {
        return "M" + (x + r) + " " + y + " H" + (x + w - r) + " Q" + (x + w) + " " + y + " " + (x + w) + " " + (y + r)
             + " V" + (y + h - r) + " Q" + (x + w) + " " + (y + h) + " " + (x + w - r) + " " + (y + h)
             + " H" + (x + r) + " Q" + x + " " + (y + h) + " " + x + " " + (y + h - r)
             + " V" + (y + r) + " Q" + x + " " + y + " " + (x + r) + " " + y + " Z "
    }
    readonly property string holesSvg: {
        let s = ""
        for (const id in holes) { const h = holes[id]; s += rrPath(h.x, h.y, h.w, h.h, 12) }
        return s || "M0 0"
    }

    // ---------- tab drag: long press picks a tab up, a pane's edge splits, its middle moves ----------
    property string dragTab: ""
    property point dragPos: Qt.point(0, 0)      // window coordinates
    property string dropGid: ""
    property string dropZone: ""                // left | right | top | bottom | center
    function beginDrag(id, p) { dragTab = id; moveDrag(p) }
    function moveDrag(p) {
        dragPos = p
        const q = mapToArea(p.x, p.y)
        let hit = "", zone = ""
        for (const gid in rects) {
            const r = rects[gid]
            if (q.x < r.x || q.x > r.x + r.w || q.y < r.y || q.y > r.y + r.h) continue
            hit = gid
            const u = (q.x - r.x) / r.w, v = (q.y - r.y) / r.h
            const edges = [[u, "left"], [1 - u, "right"], [v, "top"], [1 - v, "bottom"]].sort((a, b) => a[0] - b[0])
            zone = edges[0][0] < 0.28 ? edges[0][1] : "center"
            if (zone !== "center" && !SM.canSplit(tree, gid, zone, areaW, areaH, gap)) zone = "center"
            break
        }
        // dropping a pane's only tab on itself would change nothing
        const from = groupOf(dragTab)
        if (hit === from && (zone === "center" || groups[from].tabIds.length === 1)) { hit = ""; zone = "" }
        dropGid = hit
        dropZone = zone
    }
    function endDrag() {
        const id = dragTab, gid = dropGid, zone = dropZone
        cancelDrag()
        if (id && gid && zone) dropTab(id, gid, zone)
    }
    function cancelDrag() { dragTab = ""; dropGid = ""; dropZone = "" }

    // ---------- the pane menu ----------
    property string menuGid: ""
    property point menuPos: Qt.point(0, 0)
    function openPaneMenu(gid, p) { menuPos = p; menuGid = gid }

    // ---------- opening things ----------
    function openDetail(kind, d) {
        openTab("card", "card:" + (d.id || d.name || kind), d.name || d.host || d.name || "", d, kind)
    }
    function launchTerminal(kind, d) {
        if (kind === "session") { if (launcher.sshSession(d)) store.markLaunched(d.id) }
        else if (kind === "cont") launcher.container(d.name)
        else launcher.pod(d.name, d.ns, discovery.context)
    }

    // ---------- the list model: one flat block list, rebuilt on any data change ----------
    property var blocks: []
    function rebuild() { blocks = LB.build(store.sessions, discovery, filterText, I18n.tr, I18n.ltr) }

    // Esc: back out of a sub-page first, then close the focused tab, then the shelf.
    Shortcut {
        sequences: [StandardKey.Cancel]
        enabled: root.open
        onActivated: {
            if (root.menuGid !== "") root.menuGid = ""
            else if (root.dragTab !== "") root.cancelDrag()
            else if (root.overlayOpen) root.closeOverlay()
            else if (root.focusKind !== "home") closeTab(root.focusTab.id)
            else root.open = false
        }
    }

    // keyboard: split, move focus between panes, close the tab, nudge dividers
    Shortcut { sequence: "Ctrl+\\"; enabled: root.open; onActivated: root.splitPane(root.focusGroup, "right") }
    Shortcut { sequence: "Ctrl+Shift+\\"; enabled: root.open; onActivated: root.splitPane(root.focusGroup, "bottom") }
    Shortcut { sequence: "Ctrl+W"; enabled: root.open && root.focusKind !== "home"; onActivated: root.closeTab(root.focusTab.id) }
    Shortcut { sequence: "Ctrl+Alt+Left"; enabled: root.open; onActivated: root.focusNeighbor("left") }
    Shortcut { sequence: "Ctrl+Alt+Right"; enabled: root.open; onActivated: root.focusNeighbor("right") }
    Shortcut { sequence: "Ctrl+Alt+Up"; enabled: root.open; onActivated: root.focusNeighbor("up") }
    Shortcut { sequence: "Ctrl+Alt+Down"; enabled: root.open; onActivated: root.focusNeighbor("down") }
    Shortcut { sequence: "Ctrl+Shift+Left"; enabled: root.open; onActivated: root.nudge(root.focusGroup, "left") }
    Shortcut { sequence: "Ctrl+Shift+Right"; enabled: root.open; onActivated: root.nudge(root.focusGroup, "right") }
    Shortcut { sequence: "Ctrl+Shift+Up"; enabled: root.open; onActivated: root.nudge(root.focusGroup, "up") }
    Shortcut { sequence: "Ctrl+Shift+Down"; enabled: root.open; onActivated: root.nudge(root.focusGroup, "down") }
}
