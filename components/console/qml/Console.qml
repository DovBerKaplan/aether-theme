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

    readonly property int pw: 400                 // shelf width
    readonly property real rad: 26                // the left corners
    property bool open: false
    property real px: open ? root.width - pw : root.width
    readonly property bool panelIn: px < root.width - 1
    property real closedAt: 0
    Behavior on px {
        enabled: true
        SpringAnimation { spring: 3.6; damping: root.open ? 0.22 : 0.36; epsilon: 3 }
    }
    onPxChanged: report()
    onOpenChanged: {
        closedAt = open ? 0 : Date.now()
        ctl.setKeyboard(open)
        discovery.setPolling(open)
        if (open) mainPage.filterField.forceFocus()
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
            ctl.setLayout(panelCmds(px, pw, root.height, rad), Qt.rect(0, 0, 0, 0), true)
        } else {
            ctl.setLayout(earCmds(), Qt.rect(root.width - 5, 14, 5, 64), false)
        }
    }
    function panelCmds(x, w, h, r) {
        return [
            { t: "M", x: x + r, y: 0 },
            { t: "L", x: x + w, y: 0 },
            { t: "L", x: x + w, y: h },
            { t: "L", x: x + r, y: h },
            { t: "C", x: x, y: h - r, x1: x, y1: h, x2: x, y2: h },
            { t: "L", x: x, y: r },
            { t: "C", x: x + r, y: 0, x1: x, y1: r, x2: x, y2: r },
        ]
    }
    function earCmds() {
        const x = root.width - 5
        return [{ t: "M", x: x, y: 14 }, { t: "L", x: x + 4, y: 14 },
                { t: "L", x: x + 4, y: 78 }, { t: "L", x: x, y: 78 }]
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

    // ---------- the resting ear ----------
    Rectangle {
        id: ear
        visible: !root.panelIn
        x: root.width - 5; y: 14; width: 4; height: 64; radius: 2
        color: Theme.bodyTop
        border { width: 1; color: Theme.rim }
        opacity: earHover.hovered ? 0.9 : 0.3
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        HoverHandler { id: earHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) peek.restart() }
        TapHandler { onTapped: root.open = true }
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
        x: root.px; y: 0; width: root.pw; height: root.height
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
                PathLine { x: glass.width; y: 0 }
                PathLine { x: glass.width; y: glass.height }
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
                PathLine { x: glassMask.width; y: 0 }
                PathLine { x: glassMask.width; y: glassMask.height }
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
            anchors.fill: parent
            LayoutMirroring.enabled: I18n.rtl
            LayoutMirroring.childrenInherit: true

            function openImport() { importPage.reload(); content.page = "import" }

            // ---- main list ----
            PanelScaffold {
                id: mainPage
                anchors.fill: parent
                showBack: false
                maxHeight: root.height
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

            // ---- sub-pages ----
            SessionEditor {
                id: editorPage
                anchors.fill: parent
                maxHeight: root.height
                opacity: content.page === "editor" ? 1 : 0
                enabled: content.page === "editor"
                visible: opacity > 0.01
                onSaved: content.page = "main"
                onBackRequested: content.page = "main"
            }
            ImportPage {
                id: importPage
                anchors.fill: parent
                maxHeight: root.height
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
            onClicked: root.connectSession(s)
            trailing: [
                Item {
                    width: 30; height: 36
                    Rectangle {
                        visible: modelData.active === true
                        anchors { verticalCenter: parent.verticalCenter }
                        x: I18n.rtl ? parent.width - 10 : 0
                        width: 6; height: 6; radius: 3; color: Theme.accent
                    }
                    Glyph {
                        anchors.centerIn: parent
                        name: "edit"; size: 15; color: Theme.subtext
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.openEditor(s) }
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
            onClicked: root.connectContainer(c)
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
            onClicked: root.connectPod(p)
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
