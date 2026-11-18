import QtQuick
import AetherShared
import "."

// A terminal tab: a Konsole window seated in the hole of this view (the media-seat handshake,
// one seat per view so split panes can hold several). The window lives for the tab - it is
// concealed while the tab is hidden or the shelf is closed, and tmux keeps the session anyway.
// A window the script reports dead (ssh drop, user close) is relaunched when the tab is on
// screen, and marked with the orange dot otherwise.
Item {
    id: view
    property var shell
    property var tab
    property string gid
    property bool active: true

    readonly property bool isLocal: tab.kind === "local"
    // on stage: this tab is its pane's visible one, the shelf is open, no overlay covers it
    readonly property bool wantSeat: active && shell.open && !shell.overlayOpen
    readonly property bool focusedPane: shell.focusGroup === gid
    property int pid: 0
    property bool ready: false      // the KWin script seated it and revealed it
    property bool failed: false
    property string sent: ""        // the last geometry handed to the script

    function ensure() {
        let p = shell.seats[tab.id] || 0
        if (p === 0 || shell.downIds[tab.id] === true) {
            if (p > 0) shell.seatHideNow(p)   // the dead window may still be on stage
            p = isLocal ? launcher.localPid(tab.slot || 0)
                        : launcher.sshSessionPid(Object.assign({}, tab.data, { slot: tab.slot || 0 }))
            console.warn("SEATLAUNCH kind=", tab.kind, "host=", tab.data.host, "pid=", p)
            if (!p) { pid = 0; failed = true; return }
            failed = false
            shell.setSeat(tab.id, p)
            ctl.registerSeat(p)
            shell.clearDown(tab.id)
        }
        pid = p
        // a view rebuilt in the same breath finds the window already on stage: adopt it
        ready = shell.revealed[p] === true
    }
    function release() {
        if (pid > 0) shell.seatHideNow(pid)
        ready = false
        sent = ""
        shell.setHole(tab.id, null)
    }
    function sync() {
        if (!wantSeat) { release(); return }
        if (pid === 0 || shell.downIds[tab.id] === true) { ready = false; sent = ""; ensure() }
        place()
        if (focusedPane && pid > 0) ctl.focusSeat(pid)
    }
    // Measured only once the glass has settled: opening a tab can resize the shelf and the
    // window follows at once while the glass is still springing, so an early measurement mixes
    // the two and parks Konsole beside the glass. Re-sent whenever the hole moves (a divider
    // drag, a spring); the script just re-places a window that is already up.
    function place() {
        if (!wantSeat || pid <= 0 || !shell.settled || seatHost.width < 8 || seatHost.height < 8) return
        const r = seatHost.mapToItem(shell, 0, 0)
        const g = [Math.round(r.x), Math.round(r.y), Math.round(seatHost.width), Math.round(seatHost.height)]
        const key = pid + ":" + g.join(",")
        if (key === sent) return
        sent = key
        ctl.showSeat(pid, g[0], g[1], g[2], g[3])
        updateHole()
    }
    function updateHole() {
        if (!ready) return
        const s = seatHost.mapToItem(shell.shelfItem, 0, 0)
        shell.setHole(tab.id, { x: Math.round(s.x), y: Math.round(s.y), w: Math.round(seatHost.width), h: Math.round(seatHost.height) })
    }

    onWantSeatChanged: sync()
    onFocusedPaneChanged: if (wantSeat && focusedPane && pid > 0) ctl.focusSeat(pid)
    Component.onCompleted: { shell.seatEnter(tab.id); sync() }
    Component.onDestruction: {
        shell.seatLeave(tab.id, wantSeat ? pid : 0)   // hidden views already hid their window
        shell.setHole(tab.id, null)
    }

    // follows every cause of movement at once: springs, divider drags, pane moves
    Timer { interval: 50; repeat: true; running: view.wantSeat; onTriggered: view.place() }
    Connections {
        target: shell
        function onSettledChanged() { if (shell.settled) view.place() }
        function onDownIdsChanged() { if (view.wantSeat && shell.downIds[view.tab.id] === true) view.sync() }
    }
    Connections {
        target: ctl
        function onSeatReady(p) {
            if (p !== view.pid) return
            view.ready = true
            shell.clearDown(view.tab.id)
            view.updateHole()
        }
    }

    // the tab already names the terminal - this strip only offers another one
    Row {
        x: Tokens.space.md
        height: 34
        spacing: Tokens.space.xs
        ActionGlyph {
            glyph: "plus"
            anchors.verticalCenter: parent.verticalCenter
            onAct: shell.openTab(view.tab.kind,
                                 view.tab.kind + ":" + (view.tab.data.id || "local") + ":" + Date.now(),
                                 view.tab.title, view.tab.data, view.tab.dtype || "local", view.gid)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("New terminal")
            font { family: Theme.font; pixelSize: Tokens.type.caption }
            color: Theme.subtext
        }
    }
    Item {
        id: seatHost
        x: Tokens.space.md
        y: 34
        width: parent.width - 2 * Tokens.space.md
        height: parent.height - 34
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.bodyTop
            visible: view.wantSeat && view.pid > 0 && !view.ready
            Column {
                anchors.centerIn: parent
                spacing: Tokens.space.sm
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Opening the session…")
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("tmux on the server holds your place")
                    font { family: Theme.font; pixelSize: Tokens.type.caption }
                    color: Theme.subtext
                    opacity: 0.6
                }
            }
        }
        Column {
            anchors.centerIn: parent
            visible: view.failed
            spacing: Tokens.space.sm
            Glyph {
                name: "terminal"; size: 36; color: Theme.subtext
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("The terminal could not open - check the host")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Try again")
                onClicked: view.sync()
            }
        }
    }
}
