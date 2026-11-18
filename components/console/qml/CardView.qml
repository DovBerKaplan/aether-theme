import QtQuick
import AetherShared
import AetherConsole
import "."

// A destination's card: dashboard / overview and logs. Files and Terminal open as tabs next
// to it. Every card polls and tails with its own backends, so two cards can sit side by side.
Item {
    id: view
    property var shell
    property var tab
    property string gid
    property bool active: true

    readonly property string detailKind: tab.dtype
    readonly property var detailData: tab.data || ({})
    property int detailView: 0
    // which segment index holds the logs for this kind
    //   session: [Dashboard, Files, Logs, Terminal] · cont: [Overview, Logs] · pod: [Logs]
    readonly property int logsIdx: detailKind === "pod" ? 0 : detailKind === "cont" ? 1 : 2

    Metrics { id: metrics }
    LogStream { id: logStream }

    function gb(b) { return (b / 1073741824).toFixed(1) }
    function logColor(line) {
        if (/error|fatal|panic|fail|exception|traceback/i.test(line)) return Tokens.role.island.negative
        if (/warn|deprecat/i.test(line)) return Tokens.role.island.warning
        return Theme.text
    }
    readonly property var logShown: {
        const f = logSearch.text.trim().toLowerCase()
        return !f ? logStream.lines : logStream.lines.filter(l => l.toLowerCase().indexOf(f) >= 0)
    }

    // Starts/stops the pollers so they match exactly what is on screen: metrics for the
    // dashboard/overview view, a log stream for the logs view, nothing while hidden.
    property string metricKey: ""
    property string streamKey: ""
    function sync() {
        const on = active && shell.open
        if (on && detailKind === "session" && detailView === 0) {
            if (metricKey !== "s") { metrics.watchSession(detailData); metricKey = "s" }
        } else if (on && detailKind === "cont" && detailView === 0) {
            const k = "c:" + detailData.name
            if (metricKey !== k) { metrics.watchContainer(detailData.name); metricKey = k }
        } else if (metricKey !== "") {
            metrics.stop(); metricKey = ""
        }
        if (on && detailView === logsIdx) {
            let k = "", begin = null
            if (detailKind === "session") { k = "s:" + detailData.id; begin = () => logStream.startSession(detailData) }
            else if (detailKind === "cont") { k = "c:" + detailData.name; begin = () => logStream.startContainer(detailData.name) }
            else { k = "p:" + detailData.name + "/" + detailData.ns; begin = () => logStream.startPod(detailData.name, detailData.ns, discovery.context) }
            if (streamKey !== k) { logStream.clear(); begin(); streamKey = k }
        } else if (streamKey !== "") {
            logStream.stop(); streamKey = ""
        }
    }
    onActiveChanged: sync()
    Connections { target: view.shell; function onOpenChanged() { view.sync() } }
    Component.onCompleted: sync()
    Component.onDestruction: { metrics.stop(); logStream.stop() }

    PanelScaffold {
        anchors.fill: parent
        showBack: true
        bottomInset: 14
        maxHeight: view.height
        onBackRequested: shell.revealTab("home")
        title: view.detailKind === "session"
               ? (view.detailData.name || view.detailData.host || "")
               : (view.detailData.name || "")
        subtitle: view.detailKind === "session"
                  ? I18n.ltr((view.detailData.user ? view.detailData.user + "@" : "") + view.detailData.host
                             + (view.detailData.port && view.detailData.port !== "22" ? ":" + view.detailData.port : ""))
                  : I18n.ltr(view.detailKind === "cont"
                             ? (view.detailData.image || "")
                             : (view.detailData.ns || "") + "  ·  " + (view.detailData.phase || ""))
        footerHeight: 0

        headerTrailing: StatusDot {
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            down: view.detailKind === "session"
                  && (shell.downIds[view.detailData.id] === true || !ctl.online)
            color: down ? Tokens.role.island.attention
                  : view.detailKind === "cont"
                    ? (view.detailData.running ? Theme.accent : Theme.subtext)
                    : view.detailKind === "pod"
                      ? (view.detailData.phase === "Running" ? Theme.accent : Theme.subtext)
                      : Theme.accent
            opacity: color === Theme.subtext ? 0.45 : 1
            // no blink here: the header dot's opacity is a binding, and the row
            // dots carry the down-pulse for the whole card
        }

        SegmentedControl {
            width: Math.min(320, parent.width - 2 * Tokens.space.md)
            x: Tokens.space.md
            model: view.detailKind === "session" ? [I18n.tr("Dashboard"), I18n.tr("Files"), I18n.tr("Logs"), I18n.tr("Terminal")]
                 : view.detailKind === "cont" ? [I18n.tr("Overview"), I18n.tr("Logs")]
                 : [I18n.tr("Logs")]
            currentIndex: view.detailView
            // Files and Terminal open as workspace tabs; Dashboard/Logs stay in the card
            onActivated: (i) => {
                if (view.detailKind === "session" && i === 1) {
                    shell.openTab("files", "files:" + view.detailData.id,
                                 (view.detailData.name || view.detailData.host || "") + " · " + I18n.tr("Files"),
                                 view.detailData, "session", view.gid)
                    view.detailView = 0
                } else if (view.detailKind === "session" && i === 3) {
                    shell.openTab("term", "term:" + view.detailData.id,
                                 (view.detailData.name || view.detailData.host || "") + " · " + I18n.tr("Terminal"),
                                 view.detailData, "session", view.gid)
                    view.detailView = 0
                } else {
                    view.detailView = view.detailKind === "session" ? (i === 0 ? 0 : 1) : i
                    view.sync()
                }
            }
        }
        Item { width: 1; height: Tokens.space.md }   // air between the switcher and the view

        // ----- dashboard (ssh session) -----
        Column {
            visible: view.detailKind === "session" && view.detailView === 0
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
                value: view.gb(metrics.data.memUsed || 0) + " / " + view.gb(metrics.data.memTotal || 0) + " GB"
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
            visible: view.detailKind === "cont" && view.detailView === 0
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
                text: I18n.ltr(view.detailData.image || "")
                elide: Text.ElideRight
                font { family: Theme.mono; pixelSize: Tokens.type.caption }
                color: Theme.subtext
            }
            Row {
                x: Tokens.space.md
                spacing: Tokens.space.sm
                Button {
                    text: view.detailData.running ? I18n.tr("Stop") : I18n.tr("Start")
                    onClicked: discovery.containerAction(view.detailData.running ? "stop" : "start", view.detailData.name)
                }
                Button {
                    text: I18n.tr("Restart")
                    onClicked: discovery.containerAction("restart", view.detailData.name)
                }
            }
        }

        // ----- logs (all kinds) -----
        Column {
            visible: view.detailView === view.logsIdx 
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
                height: Math.max(120, view.height - 260)
                clip: true
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                LayoutMirroring.enabled: false
                model: view.logShown
                onCountChanged: if (atYEnd) Qt.callLater(positionViewAtEnd)
                delegate: Text {
                    required property int index
                    required property string modelData
                    width: logList.width
                    text: modelData
                    color: view.logColor(modelData)
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    font { family: Theme.mono; pixelSize: Tokens.type.caption }
                }
            }
        }

    }
}
