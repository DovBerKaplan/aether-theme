import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import AetherShared
import "."

// Aether Console - the connection shelf, a 400px glass column on the right edge.
//   at rest  only a quiet "ear" at the top-right corner (hover or click opens; Meta+C, D-Bus)
//   open     the shelf slides out with the island's jelly spring; SSH, containers and pods in
//            one list; a tap connects - into tmux on the server, so nothing is ever lost
//
// The window spans the whole screen so a click outside the shelf can close it; the input mask
// decides what is really clickable and follows the same path QML draws (setLayout).
Item {
    id: root

    readonly property int pwList: 400             // the list
    readonly property int pwDetail: 640           // a destination's visual card
    readonly property real rad: 26                // every corner - the glass floats, dock-style
    readonly property real edgeGap: 14            // the dock's rest distance from the edges
    readonly property real shelfY: edgeGap
    readonly property real shelfH: height - 2 * edgeGap
    property bool open: false
    readonly property bool detailOpen: content.page === "detail"
    readonly property int pw: detailOpen ? pwDetail : pwList
    // The glass width springs alongside px with the same constants, so while the card grows the
    // right edge stays pinned at width - edgeGap and only the far edge moves.
    property real gw: pw
    Behavior on gw { SpringAnimation { spring: 3.6; damping: 0.22; epsilon: 3 } }
    property real px: open ? root.width - edgeGap - pw : root.width
    readonly property bool panelIn: px < root.width - 1
    property real closedAt: 0
    Behavior on px {
        enabled: true
        SpringAnimation { spring: 3.6; damping: root.open ? 0.22 : 0.36; epsilon: 3 }
    }
    onPxChanged: report()
    onGwChanged: report()
    onOpenChanged: {
        closedAt = open ? 0 : Date.now()
        ctl.setKeyboard(open)
        discovery.setPolling(open)
        if (open) mainPage.filterField.forceFocus()
        else content.page = "main"
        report()
    }
    onWidthChanged: report()

    // The island's accent colour and language flow in through the controller's file watch -
    // a colour picked in the bar tints this shelf the same way.
    Binding { target: Theme; property: "accentOverride"; value: ctl.accent }
    Binding { target: Theme; property: "accentTint"; value: 0.07 }
    Binding { target: I18n; property: "lang"; value: ctl.lang }

    Component.onCompleted: {
        ctl.setWindowSize(ctl.screenWidth, ctl.screenHeight)
        report()
        rebuild()
        if (testDetail.length > 0) {
            root.open = true
            detailTimer.restart()
        }
    }
    Timer {
        id: detailTimer
        interval: 2000
        onTriggered: {
            if (testDetail === "cont" && discovery.containers.length > 0) {
                root.openDetail("cont", discovery.containers[0])
                logsTimer.restart()
            }
            else if (testDetail === "session") {
                // the fixture host resolves through ~/.ssh/config - no saved session needed
                root.openDetail("session", { id: "fixture", name: "kot-prod", host: "kot-prod" })
                logsTimer.restart()
            }
        }
    }
    Timer {
        id: logsTimer
        interval: 3000
        onTriggered:
            if (testDetail === "cont") { root.detailView = root.logsIdx; root.syncDetail() }
            else if (testDetail === "session") { root.detailView = root.filesIdx; root.syncDetail() }
    }

    Connections {
        target: ctl
        function onStateRequested(state) {
            if (state === "shown" || (state === "toggle" && !root.open)) root.open = true
            else root.open = false
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

    // Esc: back out of a sub-page first, then close the shelf.
    Shortcut {
        sequences: [StandardKey.Cancel]
        enabled: root.open
        onActivated: content.page !== "main" ? content.page = "main" : root.open = false
    }

    function report() {
        if (panelIn) {
            ctl.setLayout(panelCmds(root.px, root.shelfY, root.gw, root.shelfH, root.rad),
                          Qt.rect(0, 0, 0, 0), true)
        } else {
            ctl.setLayout(earCmds(), Qt.rect(root.width - 14, ear.y - 10, 16, ear.height + 20), false)
        }
    }
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
        const x = root.width - 5
        return [{ t: "M", x: x, y: ear.y }, { t: "L", x: x + 5, y: ear.y },
                { t: "L", x: x + 5, y: ear.y + ear.height }, { t: "L", x: x, y: ear.y + ear.height }]
    }
    function yFromRatio(r) {
        const minY = root.edgeGap, maxY = root.height - 72 - root.edgeGap
        return minY + (maxY - minY) * Math.min(1, Math.max(0, r))
    }
    function ratioFromY(y) {
        const minY = root.edgeGap, maxY = root.height - 72 - root.edgeGap
        return Math.min(1, Math.max(0, (y - minY) / Math.max(1, maxY - minY)))
    }

    function connectSession(s) { if (launcher.sshSession(s)) store.markLaunched(s.id) }
    function connectContainer(c) { launcher.container(c.name) }
    function connectPod(p) { launcher.pod(p.name, p.ns, discovery.context) }
    function openEditor(s) { editorPage.begin(s); content.page = "editor" }

    // A row-level lifecycle action: a quiet glyph revealed on hover. Destructive ones arm
    // first - accent colour, a second tap within 2.5s executes - ConfirmTile's language
    // in miniature.
    component ActionGlyph: Item {
        id: ag
        property string glyph
        property bool needsArm: false
        property bool armed: false
        signal act()
        width: 20; height: 28
        Rectangle {
            anchors.fill: parent; radius: 8
            color: Qt.rgba(1, 1, 1, seat.hovered ? Tokens.material.tintHover : 0)
        }
        Glyph {
            anchors.centerIn: parent
            name: ag.glyph; size: 13
            color: ag.armed ? Theme.accent : Theme.subtext
        }
        HoverHandler { id: seat; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                if (!ag.needsArm || ag.armed) {
                    ag.armed = false
                    ag.act()
                } else {
                    ag.armed = true
                    armTimer.restart()
                }
            }
        }
        Timer { id: armTimer; interval: 2500; onTriggered: ag.armed = false }
    }

    // A value bar for the detail card: label left, mono value right, a quiet accent fill.
    component StatBar: Column {
        id: sb
        property string label
        property real frac: 0
        property string value
        width: parent ? parent.width : 0
        spacing: Tokens.space.xs
        Item {
            width: parent.width; height: 16
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: sb.label; textFormat: Text.PlainText
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: sb.value; textFormat: Text.PlainText
                font { family: Theme.mono; pixelSize: Tokens.type.label }
                color: Theme.text
            }
        }
        Rectangle {
            width: parent.width; height: 6; radius: 3
            color: Theme.chip
            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: Math.max(0, Math.min(1, sb.frac)) * parent.width
                height: parent.height; radius: 3
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Easing.OutCubic } }
            }
        }
    }

    function gb(b) { return (b / 1073741824).toFixed(1) }
    function hsize(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return Math.round(b / 1024) + " KB"
        return b + " B"
    }
    function logColor(line) {
        if (/error|fatal|panic|fail|exception|traceback/i.test(line)) return Tokens.role.island.negative
        if (/warn|deprecat/i.test(line)) return "#c9a26d"
        return Theme.text
    }
    readonly property var logShown: {
        const f = logSearch.text.trim().toLowerCase()
        return !f ? logStream.lines : logStream.lines.filter(l => l.toLowerCase().indexOf(f) >= 0)
    }
    // which segment index holds each view for the current kind
    //   session: [Dashboard, Files, Logs, Terminal] · cont: [Overview, Logs, Terminal] · pod: [Logs, Terminal]
    readonly property int filesIdx: detailKind === "session" ? 1 : -1
    readonly property int logsIdx: detailKind === "pod" ? 0 : detailKind === "cont" ? 1 : 2
    readonly property int termIdx: detailKind === "pod" ? 1 : detailKind === "cont" ? 2 : 3

    // ---------- the detail card ----------
    property string detailKind: ""            // "session" | "cont" | "pod"
    property var detailData: ({})
    property int detailView: 0
    property string metricKey: ""
    property string streamKey: ""
    property string sftpKey: ""

    function openDetail(kind, d) {
        detailKind = kind
        detailData = d
        detailView = 0
        content.page = "detail"
    }
    function launchTerminal(kind, d) {
        if (kind === "session") { if (launcher.sshSession(d)) store.markLaunched(d.id) }
        else if (kind === "cont") launcher.container(d.name)
        else launcher.pod(d.name, d.ns, discovery.context)
    }
    // Starts/stops the pollers so they match exactly what is on screen: metrics for the
    // dashboard/overview views, a log stream for the logs view, nothing anywhere else.
    function syncDetail() {
        if (content.page !== "detail" || detailKind === "") {
            if (metricKey !== "") { metrics.stop(); metricKey = "" }
            if (streamKey !== "") { logStream.stop(); streamKey = "" }
            sftpKey = ""
            return
        }
        if (detailKind === "session" && detailView === 0) {
            if (metricKey !== "s") { metrics.watchSession(detailData); metricKey = "s" }
        } else if (detailKind === "cont" && detailView === 0) {
            if (metricKey !== "c:" + detailData.name) { metrics.watchContainer(detailData.name); metricKey = "c:" + detailData.name }
        } else if (metricKey !== "") {
            metrics.stop(); metricKey = ""
        }
        if (detailView === logsIdx) {
            let k = "", begin = null
            if (detailKind === "session") { k = "s:" + detailData.id; begin = () => logStream.startSession(detailData) }
            else if (detailKind === "cont") { k = "c:" + detailData.name; begin = () => logStream.startContainer(detailData.name) }
            else { k = "p:" + detailData.name + "/" + detailData.ns; begin = () => logStream.startPod(detailData.name, detailData.ns, discovery.context) }
            if (streamKey !== k) { logStream.clear(); begin(); streamKey = k }
        } else if (streamKey !== "") {
            logStream.stop(); streamKey = ""
        }
        // the files view keeps its browsing position while the card is open; a new entry
        // into the card (or another session) starts fresh at the home folder
        if (detailKind === "session" && detailView === filesIdx) {
            if (sftpKey !== "s:" + detailData.id) { sftp.open(detailData); sftpKey = "s:" + detailData.id }
        }
    }

    // ---------- the list model: one flat block list, rebuilt on any data change ----------
    property var blocks: []
    function rebuild() {
        const f = mainPage.filterField.text.trim().toLowerCase()
        const hit = (s) => !f || (s.name || "").toLowerCase().indexOf(f) >= 0
                      || (s.host || "").toLowerCase().indexOf(f) >= 0
                      || (s.group || "").toLowerCase().indexOf(f) >= 0
        const out = []
        const sessions = store.sessions
        const act = sessions.filter(s => s.open && hit(s))
        if (act.length > 0) {
            out.push({ t: "label", text: I18n.tr("Active now") })
            act.forEach(s => out.push({ t: "session", s: s, active: true }))
        }
        const saved = sessions.filter(s => !s.open && hit(s))
        const groups = []
        saved.forEach(s => { const g = s.group || I18n.tr("General"); if (groups.indexOf(g) < 0) groups.push(g) })
        groups.sort((a, b) => a.localeCompare(b))
        groups.forEach(g => {
            out.push({ t: "label", text: g })
            saved.filter(s => (s.group || I18n.tr("General")) === g)
                 .forEach(s => out.push({ t: "session", s: s }))
        })
        if (discovery.hasContainers) {
            let labeled = false
            discovery.containers.filter(c => !f || (c.name || "").toLowerCase().indexOf(f) >= 0
                                         || (c.image || "").toLowerCase().indexOf(f) >= 0)
                .forEach(c => {
                    if (!labeled) { out.push({ t: "label", text: I18n.tr("Containers") }); labeled = true }
                    out.push({ t: "cont", c: c })
                })
        }
        if (discovery.hasKubectl && discovery.context.length > 0) {
            const ps = discovery.pods.filter(p => !f || (p.name || "").toLowerCase().indexOf(f) >= 0
                                              || (p.ns || "").toLowerCase().indexOf(f) >= 0)
            if (ps.length > 0 || (discovery.contexts.length > 1 && !f)) {
                if (discovery.contexts.length > 1 && !f) out.push({ t: "ctx" })
                if (ps.length > 0) {
                    out.push({ t: "label", text: I18n.tr("Pods") + " · " + I18n.ltr(discovery.context) })
                    ps.forEach(p => out.push({ t: "pod", p: p }))
                }
            }
        }
        blocks = out
    }

    // ---------- the resting tab: the phone's Smart-Sidebar handle, in our glass ----------
    // A thin capsule hugging the right edge in the screen's upper quarter (drag it along the
    // edge - the position is saved), pull it inward to open the drawer, or click / hover it.
    Rectangle {
        id: ear
        visible: !root.panelIn
        x: root.width - width + pull
        y: root.yFromRatio(ctl.tabRatio)
        width: 5; height: 72; radius: width / 2
        color: "transparent"
        // the tab lives directly on the desktop: a light rim, a touch thick, against a dark
        // scheme; an ink hairline against a light one. The rim stands on its own - only the
        // glass body inside fades at rest and wakes on approach.
        border {
            width: ctl.systemDark ? 2 : 1.5
            color: ctl.systemDark ? Qt.rgba(1, 1, 1, 0.45)
                                  : Qt.rgba(0.13, 0.15, 0.20, 0.55)
        }
        Behavior on border.width { NumberAnimation { duration: Tokens.motion.duration.micro } }
        Behavior on border.color { ColorAnimation { duration: Tokens.motion.duration.base } }
        Rectangle {
            anchors { fill: parent; margins: parent.border.width }
            radius: Math.max(0, parent.radius - parent.border.width / 2)
            color: Theme.bodyTop
            opacity: earHover.hovered || tabDrag.active ? 1 : 0.35
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        }
        transform: Scale {
            xScale: 1 + Math.min(0.6, Math.abs(ear.pull) / 50)
            origin.x: ear.width; origin.y: ear.height / 2   // stretches leftward from the edge
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
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.open = false
    }
    Item {
        id: shelf
        x: root.px; y: root.shelfY; width: root.gw; height: root.shelfH
        clip: true

        TapHandler { onTapped: (e) => e.accepted = true }   // the glass eats its own clicks

        Shape {
            id: glass
            anchors.fill: parent
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.rim
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
            }
        }
        Shape {
            id: glassMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            ShapePath {
                fillColor: "#fff"
                startX: root.rad; startY: 0
                PathLine { x: glassMask.width - root.rad; y: 0 }
                PathQuad { x: glassMask.width; y: root.rad; controlX: glassMask.width; controlY: 0 }
                PathLine { x: glassMask.width; y: glassMask.height - root.rad }
                PathQuad { x: glassMask.width - root.rad; y: glassMask.height; controlX: glassMask.width; controlY: glassMask.height }
                PathLine { x: root.rad; y: glassMask.height }
                PathQuad { x: 0; y: glassMask.height - root.rad; controlX: 0; controlY: glassMask.height }
                PathLine { x: 0; y: root.rad }
                PathQuad { x: root.rad; y: 0; controlX: 0; controlY: 0 }
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
            property string page: "main"
            onPageChanged: root.syncDetail()
            anchors.fill: parent
            LayoutMirroring.enabled: I18n.rtl
            LayoutMirroring.childrenInherit: true

            function openImport() { importPage.reload(); content.page = "import" }

            // ---- main list: a fixed-width page; the detail card opens beside it ----
            Item {
                id: listPage
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: root.pwList
                opacity: content.page === "detail" ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }

                PanelScaffold {
                    id: mainPage
                    anchors.fill: parent
                    showBack: false
                    maxHeight: root.shelfH
                    footerHeight: 56
                    busy: discovery.busy
                    title: I18n.tr("Console")
                subtitle: blocks.length === 0 ? I18n.tr("servers · containers · pods")
                                              : I18n.f("%1 destinations", blocks.filter(b => b.t === "session" || b.t === "cont" || b.t === "pod").length)
                property alias filterField: filter
                onBackRequested: content.page = "main"

                headerTrailing: Item {
                    width: 40; height: 40
                    Glyph {
                        id: refreshGlyph
                        anchors.centerIn: parent
                        name: "restart"; size: 16
                        color: refreshHover.hovered ? Theme.text : Theme.subtext
                        NumberAnimation on rotation {
                            from: 0; to: 360; duration: 900
                            running: discovery.busy; loops: Animation.Infinite
                        }
                    }
                    HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: discovery.refresh() }
                }

                footer: Row {
                    spacing: Tokens.space.sm
                    anchors { left: parent.left; right: parent.right; leftMargin: Tokens.space.md; rightMargin: Tokens.space.md }
                    Button { text: I18n.tr("New connection"); kind: "filled"; onClicked: root.openEditor({}) }
                    Button { text: I18n.tr("Import"); onClicked: content.openImport() }
                }

                TextField {
                    id: filter
                    width: parent.width - 2 * Tokens.space.md
                    x: Tokens.space.md
                    placeholder: I18n.tr("Filter")
                    onTextChanged: root.rebuild()
                }

                // empty state: an affordance, not a blank wall
                Column {
                    visible: root.blocks.length === 0 && filter.text.length === 0
                    x: Tokens.space.md
                    width: parent.width - 2 * Tokens.space.md
                    topPadding: Tokens.space.xl
                    spacing: Tokens.space.md
                    Glyph { name: "terminal"; size: 44; color: Theme.subtext; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("No saved connections yet")
                        font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                        color: Theme.text
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("Every connection is wrapped in tmux on the server - a drop, a crash or a reboot only needs one more tap.")
                        wrapMode: Text.Wrap
                        font { family: Theme.font; pixelSize: Tokens.type.label }
                        color: Theme.subtext
                    }
                    Row {
                        spacing: Tokens.space.sm
                        anchors.horizontalCenter: parent.horizontalCenter
                        Button { text: I18n.tr("Import"); kind: "filled"; onClicked: content.openImport() }
                        Button { text: I18n.tr("New connection"); onClicked: root.openEditor({}) }
                    }
                }

                Repeater {
                    model: root.blocks
                    Loader {
                        required property int index
                        required property var modelData
                        width: parent ? parent.width : 0
                        sourceComponent: modelData.t === "label" ? lblComp
                                       : modelData.t === "session" ? sessComp
                                       : modelData.t === "cont" ? contComp
                                       : modelData.t === "ctx" ? ctxComp : podComp
                    }
                }
            }
            }

            // ---- detail card: one destination, three views, the glass grows for it ----
            Item {
                id: detailPage
                // the card owns the whole glass; the list fades out beneath it while the
                // glass grows - the old 240px strip left the far half of the glass dead
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                visible: content.page === "detail"
                opacity: content.page === "detail" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

                PanelScaffold {
                    anchors.fill: parent
                    showBack: true
                    maxHeight: root.shelfH
                    onBackRequested: content.page = "main"
                    title: root.detailKind === "session"
                           ? (root.detailData.name || root.detailData.host || "")
                           : (root.detailData.name || "")
                    subtitle: root.detailKind === "session"
                              ? I18n.ltr((root.detailData.user ? root.detailData.user + "@" : "") + root.detailData.host
                                         + (root.detailData.port && root.detailData.port !== "22" ? ":" + root.detailData.port : ""))
                              : I18n.ltr(root.detailKind === "cont"
                                         ? (root.detailData.image || "")
                                         : (root.detailData.ns || "") + "  ·  " + (root.detailData.phase || ""))
                    footerHeight: 0

                    headerTrailing: Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: root.detailKind === "cont"
                               ? (root.detailData.running ? Theme.accent : Theme.subtext)
                               : root.detailKind === "pod"
                                 ? (root.detailData.phase === "Running" ? Theme.accent : Theme.subtext)
                                 : Theme.accent
                        opacity: color === Theme.subtext ? 0.45 : 1
                    }

                    SegmentedControl {
                        width: Math.min(320, parent.width - 2 * Tokens.space.md)
                        x: Tokens.space.md
                        model: root.detailKind === "session" ? [I18n.tr("Dashboard"), I18n.tr("Files"), I18n.tr("Logs"), I18n.tr("Terminal")]
                             : root.detailKind === "cont" ? [I18n.tr("Overview"), I18n.tr("Logs"), I18n.tr("Terminal")]
                             : [I18n.tr("Logs"), I18n.tr("Terminal")]
                        currentIndex: root.detailView
                        onActivated: (i) => { root.detailView = i; root.syncDetail() }
                    }

                    // ----- dashboard (ssh session) -----
                    Column {
                        visible: root.detailKind === "session" && root.detailView === 0
                        width: parent.width
                        spacing: Tokens.space.lg
                        topPadding: Tokens.space.sm
                        Text {
                            visible: metrics.data.err !== undefined && metrics.data.err !== ""
                            x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
                            text: I18n.tr("Could not read metrics - connect once so the host knows the key.")
                            wrapMode: Text.Wrap
                            font { family: Theme.font; pixelSize: Tokens.type.label }
                            color: Tokens.role.island.negative
                        }
                        Text {
                            visible: Object.keys(metrics.data).length === 0
                            x: Tokens.space.md
                            text: I18n.tr("Waiting for the first reading…")
                            font { family: Theme.font; pixelSize: Tokens.type.label }
                            color: Theme.subtext
                        }
                        StatBar {
                            visible: !metrics.data.err
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            label: I18n.tr("CPU")
                            frac: metrics.data.cpu || 0
                            value: Math.round((metrics.data.cpu || 0) * 100) + "%"
                        }
                        StatBar {
                            visible: !metrics.data.err
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            label: I18n.tr("Memory")
                            frac: metrics.data.memTotal > 0 ? (metrics.data.memUsed || 0) / metrics.data.memTotal : 0
                            value: root.gb(metrics.data.memUsed || 0) + " / " + root.gb(metrics.data.memTotal || 0) + " GB"
                        }
                        StatBar {
                            visible: !metrics.data.err
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            label: I18n.tr("Disk")
                            frac: metrics.data.diskTotal > 0 ? (metrics.data.diskUsed || 0) / metrics.data.diskTotal : 0
                            value: Math.round(((metrics.data.diskUsed || 0) / Math.max(1, metrics.data.diskTotal || 1)) * 100) + "%"
                        }
                        Column {
                            visible: !metrics.data.err
                            width: parent.width
                            spacing: Tokens.space.xs
                            SectionLabel {
                                x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
                                text: I18n.tr("Top processes")
                            }
                            Repeater {
                                model: metrics.processes
                                Item {
                                    required property var modelData
                                    x: Tokens.space.md
                                    width: parent ? parent.width - 2 * Tokens.space.md : 0
                                    height: 24
                                    Text {
                                        anchors { left: parent.left; right: procCpu.left; verticalCenter: parent.verticalCenter }
                                        text: I18n.ltr(modelData.cmd); textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        font { family: Theme.mono; pixelSize: Tokens.type.label }
                                        color: Theme.text
                                    }
                                    Text {
                                        id: procCpu
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: I18n.ltr(modelData.cpu.toFixed(1) + "%")
                                        font { family: Theme.mono; pixelSize: Tokens.type.label }
                                        color: modelData.cpu > 50 ? Tokens.role.island.negative : Theme.subtext
                                    }
                                }
                            }
                        }
                    }

                    // ----- overview (local container) -----
                    Column {
                        visible: root.detailKind === "cont" && root.detailView === 0
                        width: parent.width
                        spacing: Tokens.space.lg
                        topPadding: Tokens.space.sm
                        StatBar {
                            label: I18n.tr("CPU")
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            frac: metrics.data.cpu || 0
                            value: Math.round((metrics.data.cpu || 0) * 100) + "%"
                        }
                        Item {
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            height: 20
                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: I18n.tr("Memory")
                                font { family: Theme.font; pixelSize: Tokens.type.label }
                                color: Theme.subtext
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: metrics.data.memText || "…"
                                font { family: Theme.mono; pixelSize: Tokens.type.label }
                                color: Theme.text
                            }
                        }
                        Text {
                            x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
                            text: I18n.ltr(root.detailData.image || "")
                            elide: Text.ElideRight
                            font { family: Theme.mono; pixelSize: Tokens.type.caption }
                            color: Theme.subtext
                        }
                        Row {
                            x: Tokens.space.md
                            spacing: Tokens.space.sm
                            Button {
                                text: root.detailData.running ? I18n.tr("Stop") : I18n.tr("Start")
                                onClicked: discovery.containerAction(root.detailData.running ? "stop" : "start", root.detailData.name)
                            }
                            Button {
                                text: I18n.tr("Restart")
                                onClicked: discovery.containerAction("restart", root.detailData.name)
                            }
                        }
                    }

                    // ----- files (ssh session): the stock sftp client over the same master -----
                    Column {
                        visible: root.detailKind === "session" && root.detailView === root.filesIdx && content.page === "detail"
                        width: parent.width
                        spacing: Tokens.space.sm
                        topPadding: Tokens.space.sm
                        Row {
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            spacing: Tokens.space.xs
                            ActionGlyph { glyph: "up"; onAct: sftp.up() }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30
                                text: I18n.ltr(sftp.path)
                                textFormat: Text.PlainText
                                elide: Text.ElideMiddle
                                font { family: Theme.mono; pixelSize: Tokens.type.label }
                                color: Theme.subtext
                            }
                        }
                        LinearProgress {
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            running: sftp.busy
                        }
                        Text {
                            visible: sftp.err.length > 0
                            x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
                            text: sftp.err
                            wrapMode: Text.WrapAnywhere
                            font { family: Theme.mono; pixelSize: Tokens.type.caption }
                            color: Tokens.role.island.negative
                        }
                        Item {
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            height: Math.max(180, Math.min(360, root.height - 460))
                            ListView {
                                id: fileList
                                anchors.fill: parent
                                clip: true
                                reuseItems: true
                                boundsBehavior: Flickable.StopAtBounds
                                LayoutMirroring.enabled: false
                                model: sftp.entries
                                delegate: ListRow {
                                    required property var modelData
                                    width: fileList.width
                                    title: modelData.name
                                    subtitle: modelData.dir ? I18n.tr("Folder") + " · " + I18n.ltr(modelData.date)
                                                            : I18n.ltr(root.hsize(modelData.size) + "  ·  " + modelData.date)
                                    leadingGlyphSource: Qt.resolvedUrl(modelData.dir ? "assets/glyphs/folder.svg"
                                                                                     : "assets/glyphs/file.svg")
                                    onClicked: if (modelData.dir) sftp.list(sftp.path + "/" + modelData.name)
                                    trailing: [
                                        ActionGlyph {
                                            glyph: "download"
                                            visible: !modelData.dir
                                            onAct: sftp.download(modelData.name)
                                        }
                                    ]
                                }
                            }
                            DropArea {
                                id: fileDrop
                                anchors.fill: parent
                                onEntered: (d) => d.accepted = d.hasUrls
                                onDropped: (d) => { if (d.hasUrls) d.urls.forEach(u => sftp.upload(u)); d.accept() }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: fileDrop.containsDrag
                                text: I18n.tr("Drop to upload here")
                                font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                                color: Theme.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: sftp.entries.length === 0 && !sftp.busy && sftp.err.length === 0
                                text: I18n.tr("Empty folder")
                                font { family: Theme.font; pixelSize: Tokens.type.label }
                                color: Theme.subtext
                            }
                        }
                        Row {
                            x: Tokens.space.md
                            spacing: Tokens.space.sm
                            Button { text: I18n.tr("Upload…"); onClicked: sftp.chooseUpload() }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("or drop files here")
                                font { family: Theme.font; pixelSize: Tokens.type.caption }
                                color: Theme.subtext
                            }
                        }
                    }

                    // ----- logs (all kinds) -----
                    Column {
                        visible: root.detailView === root.logsIdx && content.page === "detail"
                        width: parent.width
                        spacing: Tokens.space.sm
                        topPadding: Tokens.space.sm
                        Row {
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            spacing: Tokens.space.sm
                            TextField {
                                id: logSearch
                                width: parent.width - 70
                                placeholder: I18n.tr("Search in logs")
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: logStream.running ? "● " + I18n.tr("Live") : "○"
                                color: logStream.running ? Theme.accent : Theme.subtext
                                font { family: Theme.font; pixelSize: Tokens.type.caption }
                            }
                        }
                        Text {
                            visible: logStream.err.length > 0 && logStream.lines.length === 0
                            x: Tokens.space.md; width: parent.width - 2 * Tokens.space.md
                            text: logStream.err
                            wrapMode: Text.WrapAnywhere
                            font { family: Theme.mono; pixelSize: Tokens.type.caption }
                            color: Tokens.role.island.negative
                        }
                        ListView {
                            id: logList
                            x: Tokens.space.md
                            width: parent.width - 2 * Tokens.space.md
                            height: Math.max(200, Math.min(430, root.height - 380))
                            clip: true
                            reuseItems: true
                            boundsBehavior: Flickable.StopAtBounds
                            LayoutMirroring.enabled: false
                            model: root.logShown
                            onCountChanged: if (atYEnd) Qt.callLater(positionViewAtEnd)
                            delegate: Text {
                                required property int index
                                required property string modelData
                                width: logList.width
                                text: modelData
                                color: root.logColor(modelData)
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAnywhere
                                font { family: Theme.mono; pixelSize: Tokens.type.caption }
                            }
                        }
                    }

                    // ----- terminal (all kinds): the honest card until the glass seat lands -----
                    Column {
                        visible: root.detailView === root.termIdx && content.page === "detail"
                        width: parent.width
                        spacing: Tokens.space.lg
                        topPadding: Tokens.space.lg
                        Glyph {
                            name: "terminal"; size: 40; color: Theme.subtext
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            x: Tokens.space.lg; width: parent.width - 2 * Tokens.space.lg
                            horizontalAlignment: Text.AlignHCenter
                            text: I18n.tr("The full session opens in Konsole with the Aether profile - tmux on the server keeps everything alive.")
                            wrapMode: Text.Wrap
                            font { family: Theme.font; pixelSize: Tokens.type.label }
                            color: Theme.subtext
                        }
                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Open terminal")
                            kind: "filled"
                            onClicked: root.launchTerminal(root.detailKind, root.detailData)
                        }
                    }
                }
            }

            // ---- sub-pages ----
            SessionEditor {
                id: editorPage
                anchors.fill: parent
                maxHeight: root.shelfH
                opacity: content.page === "editor" ? 1 : 0
                enabled: content.page === "editor"
                visible: opacity > 0.01
                onSaved: content.page = "main"
                onBackRequested: content.page = "main"
            }
            ImportPage {
                id: importPage
                anchors.fill: parent
                maxHeight: root.shelfH
                opacity: content.page === "import" ? 1 : 0
                enabled: content.page === "import"
                visible: opacity > 0.01
                onBackRequested: content.page = "main"
            }
        }
    }

    // ---------- block delegates ----------
    Component {
        id: lblComp
        Item {
            width: parent ? parent.width : 0
            height: 32
            SectionLabel {
                anchors { left: parent.left; leftMargin: Tokens.space.md; right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
                text: modelData.text
            }
        }
    }
    Component {
        id: sessComp
        ListRow {
            width: parent ? parent.width : 0
            property var s: modelData.s
            highlighted: modelData.active === true
            title: s.name || s.host
            subtitle: I18n.ltr((s.user ? s.user + "@" : "") + s.host
                               + (s.port && s.port !== "22" ? ":" + s.port : ""))
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/terminal.svg")
            showChevron: true
            onClicked: root.openDetail("session", s)
            HoverHandler { id: rowHover }
            trailing: [
                Row {
                    spacing: Tokens.space.xs
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        visible: modelData.active === true
                        width: 6; height: 6; radius: 3; color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Row {
                        spacing: Tokens.space.xs
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                        ActionGlyph { glyph: "terminal"; onAct: root.launchTerminal("session", s) }
                        ActionGlyph { glyph: "edit"; onAct: root.openEditor(s) }
                    }
                }
            ]
        }
    }
    Component {
        id: contComp
        ListRow {
            width: parent ? parent.width : 0
            property var c: modelData.c
            title: c.name
            subtitle: I18n.ltr(c.image + (c.ports && c.ports.length > 0 ? "  ·  " + c.ports : ""))
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/container.svg")
            onClicked: root.openDetail("cont", c)
            HoverHandler { id: rowHover }
            trailing: [
                Row {
                    spacing: Tokens.space.xs
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        id: acts
                        spacing: Tokens.space.xs
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                        ActionGlyph { glyph: "terminal"; onAct: root.launchTerminal("cont", c) }
                        ActionGlyph {
                            glyph: "restart"
                            visible: c.running
                            onAct: discovery.containerAction("restart", c.name)
                        }
                        ActionGlyph {
                            glyph: c.running ? "stop" : "play"
                            onAct: discovery.containerAction(c.running ? "stop" : "start", c.name)
                        }
                    }
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: c.running ? Theme.accent : Theme.subtext
                        opacity: c.running ? 1 : 0.45
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            ]
        }
    }
    Component {
        id: podComp
        ListRow {
            width: parent ? parent.width : 0
            property var p: modelData.p
            title: p.name
            subtitle: I18n.ltr(p.ns + "  ·  " + p.phase + (p.restarts > 0 ? "  ·  " + I18n.f("%1 restarts", p.restarts) : ""))
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/pod.svg")
            onClicked: root.openDetail("pod", p)
            HoverHandler { id: rowHover }
            trailing: [
                Row {
                    spacing: Tokens.space.xs
                    anchors.verticalCenter: parent.verticalCenter
                    Row {
                        spacing: Tokens.space.xs
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                        ActionGlyph { glyph: "terminal"; onAct: root.launchTerminal("pod", p) }
                        ActionGlyph {
                            glyph: "restart"
                            needsArm: true
                            onAct: discovery.deletePod(p.name, p.ns)
                        }
                    }
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: p.phase === "Running" ? Theme.accent : Theme.subtext
                        opacity: p.phase === "Running" ? 1 : 0.45
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            ]
        }
    }
    Component {
        id: ctxComp
        ListRow {
            width: parent ? parent.width : 0
            title: I18n.tr("Kubernetes context")
            subtitle: I18n.ltr(discovery.context)
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/server.svg")
            onClicked: {
                const i = discovery.contexts.indexOf(discovery.context)
                discovery.context = discovery.contexts[(i + 1) % discovery.contexts.length]
            }
        }
    }
}
