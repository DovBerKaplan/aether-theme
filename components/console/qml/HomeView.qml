import QtQuick
import AetherShared
import "."

// The home tab: servers, containers and pods in one list; a tap opens the destination's card.
Item {
    id: view
    property var shell
    property var tab
    property string gid
    property bool active: true
    readonly property var blocks: shell.blocks

    PanelScaffold {
        id: mainPage
        anchors.fill: parent
        showBack: false
        bottomInset: 14
        maxHeight: view.height
        busy: discovery.busy
        title: I18n.tr("Console")
        subtitle: view.blocks.length === 0 ? I18n.tr("servers · containers · pods")
                                      : I18n.f("%1 destinations", view.blocks.filter(b => b.t === "session" || b.t === "cont" || b.t === "pod").length)

        // a narrow pane wraps the buttons onto a second line instead of clipping them; the footer is exactly as tall as they are
        footerHeight: footerFlow.implicitHeight + Tokens.space.sm
        footer: Flow {
            id: footerFlow
            spacing: Tokens.space.sm
            anchors { left: parent.left; right: parent.right; leftMargin: Tokens.space.md; rightMargin: Tokens.space.md }
            Button { text: I18n.tr("New connection"); kind: "filled"; onClicked: shell.openEditor({}) }
            Button { text: I18n.tr("Import"); onClicked: shell.openImport() }
            Button { text: I18n.tr("Local terminal"); onClicked: launcher.localTerminal() }
        }

        TextField {
            id: filter
            fillAlpha: 0.4
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            placeholder: I18n.tr("Filter")
            text: shell.filterText
            onTextChanged: if (text !== shell.filterText) { shell.filterText = text; shell.rebuild() }
        }
        Item { width: 1; height: Tokens.space.xs }

        // empty state: an affordance, not a blank wall
        Column {
            visible: view.blocks.length === 0 && filter.text.length === 0
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
                Button { text: I18n.tr("Import"); kind: "filled"; onClicked: shell.openImport() }
                Button { text: I18n.tr("New connection"); onClicked: shell.openEditor({}) }
            }
        }

        Repeater {
            model: view.blocks
            Loader {
                required property int index
                required property var modelData
                // rows are inset like cards so a highlight never runs into the glass rim
                x: Tokens.space.sm
                width: parent ? parent.width - 2 * Tokens.space.sm : 0
                sourceComponent: modelData.t === "label" ? lblComp
                               : modelData.t === "session" ? sessComp
                               : modelData.t === "cont" ? contComp
                               : modelData.t === "ctx" ? ctxComp : podComp
            }
        }
    }

    // ---------- block delegates ----------
    Component {
        id: lblComp
        Item {
            width: parent ? parent.width : 0
            height: 38
            SectionLabel {
                anchors { left: parent.left; leftMargin: Tokens.space.md; right: parent.right; rightMargin: Tokens.space.md; bottom: parent.bottom; bottomMargin: Tokens.space.xs }
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
            onClicked: shell.openDetail("session", s)
            HoverHandler { id: rowHover }
            trailing: [
                Row {
                    spacing: Tokens.space.xs
                    anchors.verticalCenter: parent.verticalCenter
                    StatusDot {
                        visible: modelData.active === true || shell.downIds[s.id] === true
                        down: shell.downIds[s.id] === true || (!ctl.online && modelData.active === true)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Row {
                        spacing: Tokens.space.xs
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                        ActionGlyph { glyph: "terminal"; onAct: shell.launchTerminal("session", s) }
                        ActionGlyph { glyph: "edit"; onAct: shell.openEditor(s) }
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
            onClicked: shell.openDetail("cont", c)
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
                        ActionGlyph { glyph: "terminal"; onAct: shell.launchTerminal("cont", c) }
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
            onClicked: shell.openDetail("pod", p)
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
                        ActionGlyph { glyph: "terminal"; onAct: shell.launchTerminal("pod", p) }
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
